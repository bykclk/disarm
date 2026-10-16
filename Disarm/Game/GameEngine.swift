import Foundation
import Observation
import UIKit
import DisarmCore

enum Tool: Equatable {
    case select, belt, erase
    case place(ModuleKind)
}

enum SheetKind: Identifiable, Equatable {
    case contracts, upgrades, locations, help, log, campaign, deliveries
    case module(GridPos)
    case file(UUID)
    case delivery(UUID)
    case offline(seconds: Double, earned: Int)

    var id: String {
        switch self {
        case .contracts: "contracts"
        case .upgrades: "upgrades"
        case .locations: "locations"
        case .help: "help"
        case .log: "log"
        case .campaign: "campaign"
        case .deliveries: "deliveries"
        case .module(let p): "module-\(p.x)-\(p.y)"
        case .file(let id): "file-\(id)"
        case .delivery(let id): "delivery-\(id)"
        case .offline: "offline"
        }
    }
}

struct Toast: Identifiable, Equatable {
    enum Style { case info, good, bad, warn }
    let id = UUID()
    var text: String
    var style: Style
    var until: Date
}

/// Sahnenin tükettiği görsel efekt istekleri.
enum FxEvent {
    case processed(GridPos, text: String, removed: Bool)
    case delivered(pay: Int, good: Bool)
    /// Şikayetin kısa nedeni, teslimat noktasında uçar; dokununca o teslimat açılır.
    case complaint(text: String, id: UUID)
    /// Kaçan zararlı türleri etiketi + sarsıntı, flaş, halka; dokununca o teslimat açılır.
    case breach(text: String, id: UUID)
    case contractCompleted
    case contractFailed
    case campaignCompleted
}

struct LogEntry: Identifiable {
    let id = UUID()
    var time: Date
    var text: String
    var style: Toast.Style
    /// Bir teslimata bağlıysa günlük satırından o teslimat açılır.
    var deliveryID: UUID? = nil
}

/// Teslim edilmiş dosyanın kopyası: banttan silindikten sonra da incelenebilsin.
struct DeliveryRecord: Identifiable {
    var id: UUID { file.id }
    var time: Date
    var file: FileItem
    var outcome: DeliveryOutcome
    var contractTitle: String
    var policy: Policy
    var payPerFile: Int
}

@MainActor
@Observable
final class GameEngine {
    var state: GameState
    var sim: Simulation
    var tool: Tool = .select
    var brush: Direction = .right
    var speed: Double = 1
    /// "Sözleşme bitene kadar hızlı": 3×, sözleşme bitince/iptal olunca ya da ihlalde kendiliğinden 1×.
    var rush = false
    static let maxSpeed: Double = 3
    var paused = false
    var layoutVersion = 0
    var toasts: [Toast] = []
    var log: [LogEntry] = []
    var sheet: SheetKind?
    var recentOutcomes: [(id: UUID, good: Bool, at: Date)] = []
    /// Son teslimatlar, en yenisi başta. Kayda girmez.
    var recentDeliveries: [DeliveryRecord] = []
    static let maxRecentDeliveries = 40
    /// Sahne her karede boşaltır.
    var fx: [FxEvent] = []
    let audio = AudioManager.shared

    private var saveTimer: Double = 0
    private var lastComplaintFx = Date.distantPast

    /// Geri alma: yalnızca yerleşim düzenlemeleri (yerleştir, sil, döndür, ayarla, taşı, temizle).
    /// Para farkı iade edilir; teslimat gelirleri korunur. Mekân değişince temizlenir.
    private struct UndoEntry { var grid: Grid; var moneyDelta: Int; var key: String?; var at: Date }
    private var undoStack: [UndoEntry] = []
    private static let maxUndo = 30
    var canUndo: Bool { !undoStack.isEmpty }
    private let store = SaveStore()

    init() {
        if let saved = store.load() {
            var s = saved.state
            let report = OfflineCalculator.settle(state: &s)
            state = s
            sim = saved.sim
            if let report { sheet = .offline(seconds: report.seconds, earned: report.earned) }
            let visible = saved.repairs.filter { if case .migrated = $0 { false } else { true } }
            if !visible.isEmpty {
                addLog(String(localized: "Save file repaired after update: \(visible.count) fixes"), .warn)
            }
        } else {
            let fresh = GameState()
            state = fresh
            sim = Simulation(seed: fresh.rngSeed)
            sheet = .help
        }
        let args = ProcessInfo.processInfo.arguments
        if args.contains("-demo") {
            state = Self.demoState()
            sim = Simulation(seed: 11)
            sheet = nil
        }
        if args.contains("-demoBank") {
            state = Self.demoBankState()
            sim = Simulation(seed: 12)
            sheet = nil
        }
        if args.contains("-demoSiteDone") {
            // Küçük ofis bitmiş, şirket kilitli: sıradaki mekâna yönlendirme.
            var s = Self.demoState()
            let n = LocationKind.smallOffice.spec.contracts.count
            s.progress = ContractProgress(index: n - 1)
            s.progress.completions = n
            s.money = 3000
            s.reputation = 25
            state = s
            sim = Simulation(seed: 11)
            sheet = nil
        }
        if args.contains("-demoBelt") {
            // Görsel test: modülsüz S biçimli bant, art arda köşeler.
            var s = GameState(seed: 7)
            s.money = 5000
            s.tutorialSeen = true
        s.xp = 100_000 // demo: tüm modüller ve yükseltmeler açık
            func belt(_ cells: [(Int, Int)], _ d: Direction) { for (x, y) in cells { s.placeBelt(at: GridPos(x, y), facing: d) } }
            belt([(1, 1), (2, 1), (3, 1), (4, 1)], .right)
            belt([(5, 1), (5, 2)], .down)
            belt([(5, 3), (4, 3), (3, 3), (2, 3)], .left)
            belt([(1, 3), (1, 4)], .down)
            belt([(1, 5), (2, 5), (3, 5), (4, 5), (5, 5)], .right)
            belt([(6, 5), (6, 6), (6, 7)], .down)
            state = s
            sim = Simulation(seed: 7)
            sheet = nil
        }
        if args.contains("-demoDC") {
            state = Self.demoDataCenterState()
            sim = Simulation(seed: 14)
            sheet = nil
        }
        if args.contains("-demoEnd") {
            // Kampanyası bitmiş bir banka hattı: prestij akışını denemek için.
            var s = Self.demoBankState()
            for kind in LocationKind.allCases {
                let n = kind.spec.contracts.count
                var p = ContractProgress(index: n - 1)
                p.completions = n
                s.contracts[kind] = p
                if s.layouts[kind] == nil { s.layouts[kind] = kind.spec.emptyGrid() }
                s.unlockedLocations.insert(kind)
            }
            s.campaignCompleted = true
            s.stats.totalDelivered = 1840; s.stats.totalAccepted = 1702; s.stats.totalBreaches = 9
            s.stats.totalQuarantined = 63; s.stats.totalEarned = 96_420
            s.stats.contractsCompleted = 14; s.stats.campaignsCompleted = 1; s.stats.bestCampaignSeconds = 5_212
            state = s
            sim = Simulation(seed: 13)
            sheet = .campaign
        }
        if args.contains("-fresh") {
            // Kayıt yok sayılır: sıfırdan, yardım kapalı (ilerleme/kilit testleri için).
            state = GameState()
            state.tutorialSeen = true
            sim = Simulation(seed: state.rngSeed)
            sheet = nil
        }
        if args.contains("-skipHelp") { sheet = nil }
        if let i = args.firstIndex(of: "-sheet"), i + 1 < args.count {
            switch args[i + 1] {
            case "contracts": sheet = .contracts
            case "upgrades": sheet = .upgrades
            case "locations": sheet = .locations
            case "log": sheet = .log
            case "campaign": sheet = .campaign
            case "deliveries": sheet = .deliveries
            case "module": sheet = .module(GridPos(4, 2))
            default: break
            }
        }
        layoutVersion += 1
    }

    /// Geliştirme: Özel Bankacılık (seviye 6, şifreli arşivler) için yönlendirici→karantina hattı.
    static func demoBankState() -> GameState {
        var s = GameState(seed: 12)
        s.money = 80_000
        s.reputation = 300
        s.tutorialSeen = true
        s.xp = 100_000 // demo: tüm modüller ve yükseltmeler açık
        _ = s.unlockLocation(.company)
        _ = s.unlockLocation(.bank)
        _ = s.switchLocation(.bank)
        s.progress.index = 2
        s.moduleLevels[.parser] = 3
        s.moduleLevels[.transformer] = 2
        s.placeModule(.router, at: GridPos(1, 6), facing: .right)
        s.configure(at: GridPos(1, 6)) { $0.routeEncrypted = true }
        s.placeModule(.quarantine, at: GridPos(1, 7), facing: .down)
        s.placeModule(.parser, at: GridPos(2, 6), facing: .right)
        s.placeModule(.filter, at: GridPos(3, 6), facing: .right)
        s.configure(at: GridPos(3, 6)) { $0.filterTarget = .macro }
        s.placeModule(.filter, at: GridPos(4, 6), facing: .right)
        s.configure(at: GridPos(4, 6)) { $0.filterTarget = .script }
        s.placeModule(.filter, at: GridPos(5, 6), facing: .right)
        s.configure(at: GridPos(5, 6)) { $0.filterTarget = .embeddedFile }
        s.placeModule(.transformer, at: GridPos(6, 6), facing: .right)
        s.placeModule(.packager, at: GridPos(7, 6), facing: .right)
        s.money = 20_000
        return s
    }

    /// Geliştirme: Veri Merkezi, Adli Bilişim sözleşmesi için kum havuzu hattı.
    static func demoDataCenterState() -> GameState {
        var s = GameState(seed: 14)
        s.money = 500_000
        s.reputation = 400
        s.tutorialSeen = true
        s.xp = 100_000 // demo: tüm modüller ve yükseltmeler açık
        for kind in LocationKind.allCases { _ = s.unlockLocation(kind) }
        _ = s.switchLocation(.dataCenter)
        s.progress.index = 1
        s.moduleLevels[.sandbox] = 3
        s.moduleLevels[.parser] = 3
        s.beltLevel = 3
        s.placeModule(.sandbox, at: GridPos(5, 1), facing: .down)
        s.placeModule(.parser, at: GridPos(5, 2), facing: .down)
        s.placeModule(.filter, at: GridPos(5, 3), facing: .down)
        s.configure(at: GridPos(5, 3)) { $0.filterTarget = .macro }
        s.placeModule(.filter, at: GridPos(5, 4), facing: .down)
        s.configure(at: GridPos(5, 4)) { $0.filterTarget = .script }
        s.placeModule(.packager, at: GridPos(5, 5), facing: .down)
        for y in 6...13 { s.placeBelt(at: GridPos(5, y), facing: .down) }
        s.money = 30_000
        return s
    }

    /// Geliştirme: örnek hat kurulu, yardım kapalı bir başlangıç durumu.
    static func demoState() -> GameState {
        var s = GameState(seed: 11)
        s.money = 2000
        s.tutorialSeen = true
        s.xp = 100_000 // demo: tüm modüller ve yükseltmeler açık
        for x in 1...2 { s.placeBelt(at: GridPos(x, 1), facing: .right) }
        s.placeModule(.scanner, at: GridPos(3, 1), facing: .right)
        s.placeModule(.parser, at: GridPos(4, 1), facing: .down)
        s.placeModule(.filter, at: GridPos(4, 2), facing: .down)
        s.placeBelt(at: GridPos(4, 3), facing: .down)
        s.placeModule(.packager, at: GridPos(4, 4), facing: .right)
        s.placeBelt(at: GridPos(5, 4), facing: .right)
        for y in 4...7 { s.placeBelt(at: GridPos(6, y), facing: .down) }
        return s
    }

    // MARK: - Döngü

    enum TutorialStep: Int, CaseIterable {
        case parser, filter, packager, connect, deliver

        var text: String {
            switch self {
            case .parser: String(localized: "Pick the Parser from the palette and place it in an empty cell to the right of the intake.")
            case .filter: String(localized: "Now place a Filter. It targets macros by default; accounting doesn't want any.")
            case .packager: String(localized: "Place a Packager: if an open file is delivered, the customer can't open it.")
            case .connect: String(localized: "With the Belt tool, drag your finger to draw Intake → modules → Delivery. Mind the module output arrows.")
            case .deliver: String(localized: "Line connected! Watch the first file get delivered. Tap a file to see what's inside.")
            }
        }
    }

    /// Küçük ofiste, ilk teslimata kadar gösterilen adım. Durumdan türetilir, ayrı kayıt gerekmez.
    var tutorialStep: TutorialStep? {
        guard !state.tutorialSeen, state.currentLocation == .smallOffice else { return nil }
        let g = state.grid
        if g.positions(of: .parser).isEmpty { return .parser }
        if g.positions(of: .filter).isEmpty { return .filter }
        if g.positions(of: .packager).isEmpty { return .packager }
        if !lineConnected { return .connect }
        return .deliver
    }

    var lineConnected: Bool { state.grid.sinkReachable(from: state.location.sourcePos) }

    /// Tek seferlik ipucu kartı; öğretici adımı yoksa gösterilir.
    var pendingHint: Hint? { tutorialStep == nil ? Hint.pending(for: state) : nil }

    func dismissHint(_ h: Hint) {
        state.seenHints.insert(h)
        audio.play(.tap, volume: 0.5)
        save()
    }

    func perform(_ action: Hint.Action, from hint: Hint) {
        dismissHint(hint)
        switch action {
        case .openContracts: sheet = .contracts
        case .openUpgrades: sheet = .upgrades
        case .openCampaign: sheet = .campaign
        case .openLocations: sheet = .locations
        }
    }

    func tick(dt rawDt: Double) {
        guard !paused else { return }
        if case .file = sheet { return } // dosya incelenirken hat durur
        let dt = min(rawDt, 0.1) * speed
        var events: [GameEvent] = []
        var s = state
        var sm = sim
        // Büyük dt'yi küçük adımlara böl: bant aralıkları stabil kalsın.
        let steps = max(1, Int((dt / 0.05).rounded(.up)))
        let stepDt = dt / Double(steps)
        for _ in 0..<steps { sm.tick(dt: stepDt, state: &s, events: &events) }
        // Gözlenen alanlara yalnızca gerçekten değişince yaz: 120 Hz'de HUD her karede yeniden çizilmesin.
        if s != state { state = s }
        sim = sm
        handle(events)

        let now = Date()
        if toasts.contains(where: { $0.until < now }) { toasts.removeAll { $0.until < now } }
        if recentOutcomes.contains(where: { now.timeIntervalSince($0.at) > 1.2 }) {
            recentOutcomes.removeAll { now.timeIntervalSince($0.at) > 1.2 }
        }

        saveTimer += rawDt
        if saveTimer > 10 { save() }
    }

    private func handle(_ events: [GameEvent]) {
        for e in events {
            switch e {
            case .delivered(let file, let o):
                let id = file.id
                let good = !o.breach && o.usability >= 0.9
                recentOutcomes.append((id, good, Date()))
                let contract = state.activeContract
                recentDeliveries.insert(DeliveryRecord(time: Date(), file: file, outcome: o, contractTitle: contract.title,
                                                       policy: contract.policy, payPerFile: contract.payPerFile), at: 0)
                if recentDeliveries.count > Self.maxRecentDeliveries { recentDeliveries.removeLast() }
                fx.append(.delivered(pay: o.pay, good: good))
                if !state.tutorialSeen && !o.breach {
                    state.tutorialSeen = true
                    toast(String(localized: "First delivery! The line is yours now."), .good, 3)
                }
                if o.breach {
                    endRush(String(localized: "Breach! Slowed back to 1× so you can react."))
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    audio.play(.breach)
                    fx.append(.breach(text: o.issues.first?.shortText ?? "", id: id))
                    toast(String(localized: "BREACH! \(o.issues.first?.text ?? "") \(money(o.pay))"), .bad, 3)
                    addLog(o.issues.first?.text ?? String(localized: "Breach"), .bad, deliveryID: id)
                } else if o.usability < 0.9 {
                    audio.play(.complaint, volume: 0.7)
                    addLog("Complaint: \(o.issues.first?.text ?? String(localized: "low quality")) (+\(money(o.pay)))", .warn, deliveryID: id)
                    // Neden etiketi: yoğun akışta üst üste binmesin diye en çok saniyede bir.
                    if let issue = o.issues.first, Date().timeIntervalSince(lastComplaintFx) > 1.0 {
                        lastComplaintFx = Date()
                        fx.append(.complaint(text: issue.shortText, id: id))
                    }
                } else {
                    audio.play(.deliver, volume: 0.6)
                }
            case .contractCompleted(let c):
                endRush(String(localized: "Contract finished, back to 1×."))
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                audio.play(.contract)
                fx.append(.contractCompleted)
                toast(String(localized: "Contract complete: \(c.title) +\(money(c.completionBonus))"), .good, 4)
                addLog(String(localized: "Contract complete: \(c.title). Bonus \(money(c.completionBonus)), reputation +\(c.reputationReward)"), .good)
            case .contractFailed(let c):
                endRush(String(localized: "Contract cancelled, back to 1×."))
                audio.play(.error)
                fx.append(.contractFailed)
                toast(String(localized: "Contract cancelled: \(c.title). Too many breaches."), .bad, 4)
                addLog(String(localized: "Contract cancelled: \(c.title). Reputation -5"), .bad)
            case .levelUp(let level):
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                audio.play(.unlock)
                fx.append(.contractCompleted)
                let unlocked = GameState.modulesUnlocked(atLevel: level)
                if unlocked.isEmpty {
                    toast(String(localized: "Level \(level)!"), .good, 4)
                } else {
                    let names = unlocked.map(\.displayName).joined(separator: ", ")
                    toast(String(localized: "Level \(level)! Unlocked: \(names)"), .good, 5)
                }
                if level == Progression.requiredLevel(forUpgradeTo: 2) {
                    toast(String(localized: "Module upgrades to level 2 are now available."), .info, 5)
                } else if level == Progression.requiredLevel(forUpgradeTo: 3) {
                    toast(String(localized: "Module upgrades to level 3 are now available."), .info, 5)
                }
                addLog(String(localized: "Reached operator level \(level)"), .good)
            case .achievementUnlocked(let a):
                audio.play(.contract, volume: 0.8)
                toast(String(localized: "Achievement: \(a.displayName) (+\(money(a.rewardMoney)), +\(a.rewardXP) XP)"), .good, 4)
                addLog(String(localized: "Achievement unlocked: \(a.displayName)"), .good)
            case .locationFinished(let site):
                fx.append(.contractCompleted)
                if let next = site.next {
                    toast(String(localized: "\(site.spec.displayName) complete! Next site: \(next.spec.displayName)"), .good, 5)
                    addLog(String(localized: "\(site.spec.displayName) complete. Next site: \(next.spec.displayName) (\(money(next.spec.unlockCost)), reputation \(next.spec.unlockReputation))"), .good)
                } else {
                    toast(String(localized: "\(site.spec.displayName) complete!"), .good, 4)
                }
            case .campaignCompleted:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                audio.play(.unlock)
                fx.append(.campaignCompleted)
                addLog(String(localized: "Campaign complete: every contract in every site delivered. A new campaign is available."), .good)
                sheet = .campaign
            case .processed(_, let pos, _, let notes):
                for n in notes {
                    switch n {
                    case .removed(let k, let c):
                        fx.append(.processed(pos, text: "−\(c > 1 ? "\(c)× " : "")\(k.displayName)", removed: true))
                    case .opened, .closed, .imageDegraded, .formulasFlattened, .polyglotUnhandled:
                        if let t = Simulation.describe([n]) { fx.append(.processed(pos, text: t, removed: false)) }
                    case .noEffect:
                        break
                    }
                }
            case .dropped, .spawned, .quarantined:
                break
            }
        }
    }

    func toast(_ text: String, _ style: Toast.Style = .info, _ seconds: Double = 2) {
        toasts.append(Toast(text: text, style: style, until: Date().addingTimeInterval(seconds)))
        if toasts.count > 3 { toasts.removeFirst(toasts.count - 3) }
    }

    private func addLog(_ text: String, _ style: Toast.Style, deliveryID: UUID? = nil) {
        log.insert(LogEntry(time: Date(), text: text, style: style, deliveryID: deliveryID), at: 0)
        if log.count > 80 { log.removeLast() }
    }

    func delivery(_ id: UUID) -> DeliveryRecord? { recentDeliveries.first { $0.id == id } }

    func openDelivery(_ id: UUID) {
        guard delivery(id) != nil else { return }
        sheet = .delivery(id)
    }

    // MARK: - Dokunma

    func tapped(_ p: GridPos) {
        guard state.grid.contains(p) else { return }
        switch tool {
        case .select:
            if let m = state.grid[p]?.module {
                if m.kind == .sink { sheet = .deliveries }
                else if m.kind.isPlaceable || m.kind == .source { sheet = .module(p) }
            } else if state.grid[p]?.beltDirection != nil {
                layoutEdit(state.rotate(at: p), sound: .rotate)
            }
        case .belt:
            if state.grid[p]?.beltDirection != nil {
                layoutEdit(state.rotate(at: p), sound: .rotate)
            } else {
                layoutEdit(state.placeBelt(at: p, facing: brush), sound: .place)
            }
        case .erase:
            layoutEdit(state.remove(at: p), sound: .remove)
        case .place(let kind):
            if let m = state.grid[p]?.module, m.kind == kind {
                layoutEdit(state.rotate(at: p), sound: .rotate)
            } else {
                layoutEdit(state.placeModule(kind, at: p, facing: brush), sound: .place)
            }
        }
    }

    /// Parmakla bant çizme: önceki hücre yeni hücreye doğru döner, yeni hücre aynı yönde bant olur.
    func dragBelt(from a: GridPos, to b: GridPos) {
        guard tool == .belt, a != b,
              let dir = Direction.from(dx: b.x - a.x, dy: b.y - a.y) else { return }
        if state.grid[a]?.beltDirection != nil {
            layoutEdit(state.placeBelt(at: a, facing: dir), quiet: true, coalesce: "belt")
        } else if state.grid[a] == nil {
            layoutEdit(state.placeBelt(at: a, facing: dir), quiet: true, sound: .tap, coalesce: "belt")
        }
        if state.grid[b]?.module == nil {
            layoutEdit(state.placeBelt(at: b, facing: dir), quiet: true, sound: .tap, coalesce: "belt")
        }
        layoutVersion += 1
    }

    func dragErase(_ p: GridPos) {
        guard tool == .erase, state.grid[p]?.beltDirection != nil else { return }
        layoutEdit(state.remove(at: p), quiet: true, sound: .tap, coalesce: "erase")
    }

    func itemTapped(_ id: UUID) {
        sheet = .file(id)
    }

    /// Yerleşim düzenlemesi: başarılıysa önceki yerleşimi geri alma yığınına koyar. `coalesce` aynı anahtarlı
    /// ardışık düzenlemeleri (bant sürükleme) 1,5 sn içinde tek adımda toplar.
    @discardableResult
    private func layoutEdit(_ edit: @autoclosure () -> Result<Void, GameState.ActionError>,
                            quiet: Bool = false, sound: AudioManager.Sfx? = nil, coalesce: String? = nil) -> Bool {
        let beforeGrid = state.grid
        let beforeMoney = state.money
        let r = edit()
        if case .success = r {
            pushUndo(grid: beforeGrid, moneyDelta: beforeMoney - state.money, key: coalesce)
        }
        report(r, quiet: quiet, sound: sound)
        return r.isSuccess
    }

    private func pushUndo(grid: Grid, moneyDelta: Int, key: String?) {
        let now = Date()
        if let key, var top = undoStack.last, top.key == key, now.timeIntervalSince(top.at) < 1.5 {
            top.moneyDelta += moneyDelta
            top.at = now
            undoStack[undoStack.count - 1] = top
            return
        }
        undoStack.append(UndoEntry(grid: grid, moneyDelta: moneyDelta, key: key, at: now))
        if undoStack.count > Self.maxUndo { undoStack.removeFirst() }
    }

    func undo() {
        guard let e = undoStack.popLast() else { return }
        state.grid = e.grid
        state.money += e.moneyDelta
        layoutVersion += 1
        sheet = nil
        audio.play(.remove)
        toast(String(localized: "Undone"), .info, 1.5)
    }

    func moveModule(from a: GridPos, to b: GridPos?) {
        guard let b else { layoutVersion += 1; return } // ızgara dışına bırakıldı: yerine döner
        if !layoutEdit(state.moveModule(from: a, to: b), sound: .place) { layoutVersion += 1 }
    }

    private func report(_ r: Result<Void, GameState.ActionError>, quiet: Bool = false, sound: AudioManager.Sfx? = nil) {
        switch r {
        case .success:
            layoutVersion += 1
            if let sound { audio.play(sound) }
        case .failure(let e):
            if quiet { return }
            audio.play(.error, volume: 0.5)
            switch e {
            case .insufficientFunds(let n): toast(String(localized: "Insufficient funds: \(money(n)) needed"), .warn)
            case .cellOccupied: toast(String(localized: "Cell is occupied"), .warn)
            case .outOfBounds: break
            case .notPlaceable: break
            case .notAvailableHere: toast(String(localized: "This module isn't available at this site"), .warn)
            case .protected: toast(String(localized: "Intake and delivery are fixed"), .warn)
            case .maxLevel: toast(String(localized: "Already at max level"), .info)
            case .locked: toast(String(localized: "Kilitli"), .warn)
            case .reputationTooLow(let n): toast(String(localized: "Reputation too low: \(n) needed"), .warn)
            case .levelTooLow(let n): toast(String(localized: "Unlocks at operator level \(n)"), .warn)
            }
        }
    }

    // MARK: - Eylemler

    func rotate(at p: GridPos) { layoutEdit(state.rotate(at: p), sound: .rotate) }
    func remove(at p: GridPos) { layoutEdit(state.remove(at: p), sound: .remove); sheet = nil }
    func setFilter(at p: GridPos, _ k: PartKind) { layoutEdit(state.configure(at: p) { $0.filterTarget = k }) }
    func setRoute(at p: GridPos, _ c: ContainerKind) { layoutEdit(state.configure(at: p) { $0.routeTarget = c }) }
    func setRouteEncrypted(at p: GridPos, _ on: Bool) { layoutEdit(state.configure(at: p) { $0.routeEncrypted = on }) }
    func upgrade(_ k: ModuleKind) {
        report(state.upgradeModule(k), sound: .upgrade)
        if state.level(of: k) > 1 { layoutVersion += 1 }
        settleProgression()
    }

    func lockedModuleTapped(_ kind: ModuleKind) {
        audio.play(.error, volume: 0.4)
        toast(String(localized: "\(kind.displayName) unlocks at operator level \(kind.requiredLevel). You are level \(state.level)."), .warn, 3)
    }

    /// Simülasyon dışı bir durum değişikliğinden (yükseltme, mekân açma) sonra başarımları ve seviyeyi işler.
    private func settleProgression() {
        let before = state.level
        var events: [GameEvent] = state.claimAchievements().map { .achievementUnlocked($0) }
        if state.level > before { events.append(.levelUp(state.level)) }
        if !events.isEmpty { handle(events) }
    }
    func upgradeBelt() { report(state.upgradeBelt(), sound: .upgrade) }
    func upgradeIntake() { report(state.upgradeIntake(), sound: .upgrade) }

    func unlock(_ l: LocationKind) {
        let r = state.unlockLocation(l)
        report(r)
        if r.isSuccess {
            audio.play(.unlock)
            toast(String(localized: "\(l.spec.displayName) unlocked!"), .good, 3)
            switchLocation(l)
            settleProgression()
        }
    }

    func switchLocation(_ l: LocationKind) {
        guard l != state.currentLocation else { return }
        let r = state.switchLocation(l)
        report(r)
        if r.isSuccess {
            sim.clear()
            tool = .select
            sheet = nil
            undoStack.removeAll()
            layoutVersion += 1
        }
    }

    func clearLayout() {
        let beforeGrid = state.grid
        let beforeMoney = state.money
        defer { pushUndo(grid: beforeGrid, moneyDelta: beforeMoney - state.money, key: nil) }
        for p in state.grid.allPositions where state.grid[p]?.module?.kind.isPlaceable != false {
            if state.grid[p] != nil { _ = state.remove(at: p) }
        }
        sim.clear()
        layoutVersion += 1
        toast(String(localized: "Line cleared, costs refunded"), .info)
    }

    /// Dokunma: 1× → 2× → 3× → 1×. Elle hız seçmek rush modunu kapatır.
    func cycleSpeed() {
        rush = false
        speed = speed >= Self.maxSpeed ? 1 : speed + 1
        audio.play(.tap, volume: 0.5)
    }

    /// Basılı tutma: sözleşme bitene kadar 3×.
    func toggleRush() {
        rush.toggle()
        speed = rush ? Self.maxSpeed : 1
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        toast(rush ? String(localized: "Rushing at 3× until the contract ends") : String(localized: "Back to 1×"), .info, 2)
    }

    private func endRush(_ reason: String) {
        guard rush else { return }
        rush = false
        speed = 1
        toast(reason, .info, 3)
    }

    func resetGame() {
        state = GameState()
        sim = Simulation(seed: state.rngSeed)
        log.removeAll()
        tool = .select
        layoutVersion += 1
        save()
    }

    /// Prestij: kampanya bitmişse ilerlemeyi sıfırlar, kalıcı bonusla yeniden başlar.
    func startNewCampaign() {
        guard state.campaignCompleted else { return }
        state.startNewCampaign()
        sim = Simulation(seed: state.rngSeed)
        tool = .select
        sheet = nil
        layoutVersion += 1
        audio.play(.unlock)
        fx.append(.contractCompleted)
        let pay = Int(GameState.prestigePayBonus * 100 * Double(state.prestige))
        toast(String(localized: "Campaign \(state.prestige + 1) begins: pay +\("\(pay)%"), faster flow."), .good, 4)
        addLog(String(localized: "New campaign started at prestige \(state.prestige)."), .good)
        save()
    }

    func item(_ id: UUID) -> MovingItem? { sim.items.first { $0.id == id } }

    // MARK: - Kayıt

    func save() {
        saveTimer = 0
        state.lastSaved = Date()
        store.save(state: state, sim: sim)
    }
}

struct SaveStore {
    private var dir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    private var url: URL { dir.appendingPathComponent("disarm-save.json") }
    /// Kurtarılamayan kayıt silinmez, buraya taşınır.
    private var corruptURL: URL { dir.appendingPathComponent("disarm-save.corrupt.json") }

    /// Eski ve eksik kayıtları onararak yükler; `state` çözülemiyorsa nil döner ve dosyayı kenara koyar.
    func load() -> LoadedSave? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        if let loaded = SaveCodec.decode(data) { return loaded }
        try? FileManager.default.removeItem(at: corruptURL)
        try? FileManager.default.moveItem(at: url, to: corruptURL)
        return nil
    }

    func save(state: GameState, sim: Simulation) {
        guard let data = try? SaveCodec.encode(state: state, sim: sim) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

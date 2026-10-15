import Foundation
import Observation
import UIKit
import DisarmCore

enum Tool: Equatable {
    case select, belt, erase
    case place(ModuleKind)
}

enum SheetKind: Identifiable, Equatable {
    case contracts, upgrades, locations, help, log, campaign
    case module(GridPos)
    case file(UUID)
    case offline(seconds: Double, earned: Int)

    var id: String {
        switch self {
        case .contracts: "contracts"
        case .upgrades: "upgrades"
        case .locations: "locations"
        case .help: "help"
        case .log: "log"
        case .campaign: "campaign"
        case .module(let p): "module-\(p.x)-\(p.y)"
        case .file(let id): "file-\(id)"
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
    case breach
    case contractCompleted
    case contractFailed
    case campaignCompleted
}

struct LogEntry: Identifiable {
    let id = UUID()
    var time: Date
    var text: String
    var style: Toast.Style
}

@MainActor
@Observable
final class GameEngine {
    var state: GameState
    var sim: Simulation
    var tool: Tool = .select
    var brush: Direction = .right
    var speed: Double = 1
    var paused = false
    var layoutVersion = 0
    var toasts: [Toast] = []
    var log: [LogEntry] = []
    var sheet: SheetKind?
    var recentOutcomes: [(id: UUID, good: Bool, at: Date)] = []
    /// Sahne her karede boşaltır.
    var fx: [FxEvent] = []
    let audio = AudioManager.shared

    private var saveTimer: Double = 0
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
        if args.contains("-skipHelp") { sheet = nil }
        if let i = args.firstIndex(of: "-sheet"), i + 1 < args.count {
            switch args[i + 1] {
            case "contracts": sheet = .contracts
            case "upgrades": sheet = .upgrades
            case "locations": sheet = .locations
            case "log": sheet = .log
            case "campaign": sheet = .campaign
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
        state = s
        sim = sm
        handle(events)

        let now = Date()
        toasts.removeAll { $0.until < now }
        recentOutcomes.removeAll { now.timeIntervalSince($0.at) > 1.2 }

        saveTimer += rawDt
        if saveTimer > 10 { save() }
    }

    private func handle(_ events: [GameEvent]) {
        for e in events {
            switch e {
            case .delivered(let id, let o):
                let good = !o.breach && o.usability >= 0.9
                recentOutcomes.append((id, good, Date()))
                fx.append(.delivered(pay: o.pay, good: good))
                if !state.tutorialSeen && !o.breach {
                    state.tutorialSeen = true
                    toast(String(localized: "First delivery! The line is yours now."), .good, 3)
                }
                if o.breach {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    audio.play(.breach)
                    fx.append(.breach)
                    toast(String(localized: "BREACH! \(o.issues.first?.text ?? "") \(money(o.pay))"), .bad, 3)
                    addLog(o.issues.first?.text ?? String(localized: "Breach"), .bad)
                } else if o.usability < 0.9 {
                    audio.play(.complaint, volume: 0.7)
                    addLog("Complaint: \(o.issues.first?.text ?? String(localized: "low quality")) (+\(money(o.pay)))", .warn)
                } else {
                    audio.play(.deliver, volume: 0.6)
                }
            case .contractCompleted(let c):
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                audio.play(.contract)
                fx.append(.contractCompleted)
                toast(String(localized: "Contract complete: \(c.title) +\(money(c.completionBonus))"), .good, 4)
                addLog(String(localized: "Contract complete: \(c.title). Bonus \(money(c.completionBonus)), reputation +\(c.reputationReward)"), .good)
            case .contractFailed(let c):
                audio.play(.error)
                fx.append(.contractFailed)
                toast(String(localized: "Contract cancelled: \(c.title). Too many breaches."), .bad, 4)
                addLog(String(localized: "Contract cancelled: \(c.title). Reputation -5"), .bad)
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

    private func addLog(_ text: String, _ style: Toast.Style) {
        log.insert(LogEntry(time: Date(), text: text, style: style), at: 0)
        if log.count > 80 { log.removeLast() }
    }

    // MARK: - Dokunma

    func tapped(_ p: GridPos) {
        guard state.grid.contains(p) else { return }
        switch tool {
        case .select:
            if let m = state.grid[p]?.module {
                if m.kind.isPlaceable || m.kind == .source || m.kind == .sink { sheet = .module(p) }
            } else if state.grid[p]?.beltDirection != nil {
                report(state.rotate(at: p), sound: .rotate)
            }
        case .belt:
            if state.grid[p]?.beltDirection != nil {
                report(state.rotate(at: p), sound: .rotate)
            } else {
                report(state.placeBelt(at: p, facing: brush), sound: .place)
            }
        case .erase:
            report(state.remove(at: p), sound: .remove)
        case .place(let kind):
            if let m = state.grid[p]?.module, m.kind == kind {
                report(state.rotate(at: p), sound: .rotate)
            } else {
                report(state.placeModule(kind, at: p, facing: brush), sound: .place)
            }
        }
    }

    /// Parmakla bant çizme: önceki hücre yeni hücreye doğru döner, yeni hücre aynı yönde bant olur.
    func dragBelt(from a: GridPos, to b: GridPos) {
        guard tool == .belt, a != b,
              let dir = Direction.from(dx: b.x - a.x, dy: b.y - a.y) else { return }
        if state.grid[a]?.beltDirection != nil {
            state.placeBelt(at: a, facing: dir)
        } else if state.grid[a] == nil {
            report(state.placeBelt(at: a, facing: dir), quiet: true, sound: .tap)
        }
        if state.grid[b]?.module == nil {
            report(state.placeBelt(at: b, facing: dir), quiet: true, sound: .tap)
        }
        layoutVersion += 1
    }

    func dragErase(_ p: GridPos) {
        guard tool == .erase, state.grid[p]?.beltDirection != nil else { return }
        report(state.remove(at: p), quiet: true, sound: .tap)
    }

    func itemTapped(_ id: UUID) {
        sheet = .file(id)
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
            }
        }
    }

    // MARK: - Eylemler

    func rotate(at p: GridPos) { report(state.rotate(at: p), sound: .rotate) }
    func remove(at p: GridPos) { report(state.remove(at: p), sound: .remove); sheet = nil }
    func setFilter(at p: GridPos, _ k: PartKind) { report(state.configure(at: p) { $0.filterTarget = k }) }
    func setRoute(at p: GridPos, _ c: ContainerKind) { report(state.configure(at: p) { $0.routeTarget = c }) }
    func setRouteEncrypted(at p: GridPos, _ on: Bool) { report(state.configure(at: p) { $0.routeEncrypted = on }) }
    func upgrade(_ k: ModuleKind) { report(state.upgradeModule(k), sound: .upgrade); if state.level(of: k) > 1 { layoutVersion += 1 } }
    func upgradeBelt() { report(state.upgradeBelt(), sound: .upgrade) }
    func upgradeIntake() { report(state.upgradeIntake(), sound: .upgrade) }

    func unlock(_ l: LocationKind) {
        let r = state.unlockLocation(l)
        report(r)
        if r.isSuccess {
            audio.play(.unlock)
            toast(String(localized: "\(l.spec.displayName) unlocked!"), .good, 3)
            switchLocation(l)
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
            layoutVersion += 1
        }
    }

    func clearLayout() {
        for p in state.grid.allPositions where state.grid[p]?.module?.kind.isPlaceable != false {
            if state.grid[p] != nil { _ = state.remove(at: p) }
        }
        sim.clear()
        layoutVersion += 1
        toast(String(localized: "Line cleared, costs refunded"), .info)
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

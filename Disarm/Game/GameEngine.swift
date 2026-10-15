import Foundation
import Observation
import DisarmCore

enum Tool: Equatable {
    case select, belt, erase
    case place(ModuleKind)
}

enum SheetKind: Identifiable, Equatable {
    case contracts, upgrades, locations, help, log
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

    private var saveTimer: Double = 0
    private let store = SaveStore()

    init() {
        if let saved = store.load() {
            var s = saved.state
            let report = OfflineCalculator.settle(state: &s)
            state = s
            sim = saved.sim
            if let report { sheet = .offline(seconds: report.seconds, earned: report.earned) }
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
        if args.contains("-skipHelp") { sheet = nil }
        if let i = args.firstIndex(of: "-sheet"), i + 1 < args.count {
            switch args[i + 1] {
            case "contracts": sheet = .contracts
            case "upgrades": sheet = .upgrades
            case "locations": sheet = .locations
            case "log": sheet = .log
            case "module": sheet = .module(GridPos(4, 2))
            default: break
            }
        }
        layoutVersion += 1
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

    func tick(dt rawDt: Double) {
        guard !paused else { return }
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
                recentOutcomes.append((id, !o.breach && o.usability >= 0.9, Date()))
                if o.breach {
                    toast("İHLAL! \(o.issues.first ?? "") \(money(o.pay))", .bad, 3)
                    addLog(o.issues.first ?? "İhlal", .bad)
                } else if o.usability < 0.9 {
                    addLog("Şikayet: " + (o.issues.first ?? "düşük kalite") + " (+\(money(o.pay)))", .warn)
                }
            case .contractCompleted(let c):
                toast("Sözleşme tamamlandı: \(c.title) +\(money(c.completionBonus))", .good, 4)
                addLog("Sözleşme tamamlandı: \(c.title). Bonus \(money(c.completionBonus)), itibar +\(c.reputationReward)", .good)
            case .contractFailed(let c):
                toast("Sözleşme iptal: \(c.title). Çok fazla ihlal.", .bad, 4)
                addLog("Sözleşme iptal edildi: \(c.title). İtibar -5", .bad)
            case .dropped:
                break
            case .spawned, .processed, .quarantined:
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
                report(state.rotate(at: p))
            }
        case .belt:
            if state.grid[p]?.beltDirection != nil {
                report(state.rotate(at: p))
            } else {
                report(state.placeBelt(at: p, facing: brush))
            }
        case .erase:
            report(state.remove(at: p))
        case .place(let kind):
            if let m = state.grid[p]?.module, m.kind == kind {
                report(state.rotate(at: p))
            } else {
                report(state.placeModule(kind, at: p, facing: brush))
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
            report(state.placeBelt(at: a, facing: dir), quiet: true)
        }
        if state.grid[b]?.module == nil {
            report(state.placeBelt(at: b, facing: dir), quiet: true)
        }
        layoutVersion += 1
    }

    func dragErase(_ p: GridPos) {
        guard tool == .erase, state.grid[p]?.beltDirection != nil else { return }
        report(state.remove(at: p), quiet: true)
    }

    func itemTapped(_ id: UUID) {
        sheet = .file(id)
    }

    private func report(_ r: Result<Void, GameState.ActionError>, quiet: Bool = false) {
        switch r {
        case .success:
            layoutVersion += 1
        case .failure(let e):
            if quiet { return }
            switch e {
            case .insufficientFunds(let n): toast("Yetersiz bakiye: \(money(n)) gerekli", .warn)
            case .cellOccupied: toast("Hücre dolu", .warn)
            case .outOfBounds: break
            case .notPlaceable: break
            case .notAvailableHere: toast("Bu modül bu mekânda yok", .warn)
            case .protected: toast("Giriş ve teslimat sabittir", .warn)
            case .maxLevel: toast("Zaten en yüksek seviye", .info)
            case .locked: toast("Kilitli", .warn)
            case .reputationTooLow(let n): toast("İtibar yetersiz: \(n) gerekli", .warn)
            }
        }
    }

    // MARK: - Eylemler

    func rotate(at p: GridPos) { report(state.rotate(at: p)) }
    func remove(at p: GridPos) { report(state.remove(at: p)); sheet = nil }
    func setFilter(at p: GridPos, _ k: PartKind) { report(state.configure(at: p) { $0.filterTarget = k }) }
    func setRoute(at p: GridPos, _ c: ContainerKind) { report(state.configure(at: p) { $0.routeTarget = c }) }
    func upgrade(_ k: ModuleKind) { report(state.upgradeModule(k)); if state.level(of: k) > 1 { layoutVersion += 1 } }
    func upgradeBelt() { report(state.upgradeBelt()) }
    func upgradeIntake() { report(state.upgradeIntake()) }

    func unlock(_ l: LocationKind) {
        let r = state.unlockLocation(l)
        report(r)
        if r.isSuccess {
            toast("\(l.spec.displayName) açıldı!", .good, 3)
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
        toast("Hat temizlendi, bedeller iade edildi", .info)
    }

    func resetGame() {
        state = GameState()
        sim = Simulation(seed: state.rngSeed)
        log.removeAll()
        tool = .select
        layoutVersion += 1
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
    struct Payload: Codable {
        var state: GameState
        var sim: Simulation
    }

    private var url: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("disarm-save.json")
    }

    func load() -> Payload? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Payload.self, from: data)
    }

    func save(state: GameState, sim: Simulation) {
        guard let data = try? JSONEncoder().encode(Payload(state: state, sim: sim)) else { return }
        try? data.write(to: url, options: .atomic)
    }
}

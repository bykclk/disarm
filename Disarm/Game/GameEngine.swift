import Foundation
import Observation
import UIKit
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
                recentOutcomes.append((id, !o.breach && o.usability >= 0.9, Date()))
                if !state.tutorialSeen && !o.breach {
                    state.tutorialSeen = true
                    toast(String(localized: "First delivery! The line is yours now."), .good, 3)
                }
                if o.breach {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    toast(String(localized: "BREACH! \(o.issues.first?.text ?? "") \(money(o.pay))"), .bad, 3)
                    addLog(o.issues.first?.text ?? String(localized: "Breach"), .bad)
                } else if o.usability < 0.9 {
                    addLog("Complaint: \(o.issues.first?.text ?? String(localized: "low quality")) (+\(money(o.pay)))", .warn)
                }
            case .contractCompleted(let c):
                toast(String(localized: "Contract complete: \(c.title) +\(money(c.completionBonus))"), .good, 4)
                addLog(String(localized: "Contract complete: \(c.title). Bonus \(money(c.completionBonus)), reputation +\(c.reputationReward)"), .good)
            case .contractFailed(let c):
                toast(String(localized: "Contract cancelled: \(c.title). Too many breaches."), .bad, 4)
                addLog(String(localized: "Contract cancelled: \(c.title). Reputation -5"), .bad)
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

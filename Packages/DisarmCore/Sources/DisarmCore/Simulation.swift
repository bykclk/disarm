import Foundation

public struct MovingItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID { file.id }
    public var file: FileItem
    public var pos: GridPos
    /// Hücre içindeki ilerleme (0 giriş kenarı, 1 çıkış kenarı).
    public var progress: Double
    /// Hücredeki hareket yönü (bant yönü ya da modülden çıkış yönü).
    public var heading: Direction
    public var inModule: Bool
    public var remaining: Double
    /// Dosyanın geçtiği son modül notu (görselleştirme için).
    public var lastNote: String?
}

public enum GameEvent: Equatable, Sendable {
    case spawned(UUID)
    case processed(UUID, ModuleKind, [ProcessNote])
    case delivered(UUID, DeliveryOutcome)
    case quarantined(UUID)
    case contractCompleted(ContractSpec)
    case contractFailed(ContractSpec)
    case dropped(UUID)
}

public struct Simulation: Codable, Hashable, Sendable {
    public static let minGap = 0.4
    public static let maxOfflineSeconds: Double = 4 * 3600

    public var items: [MovingItem] = []
    public var spawnAccumulator: Double = 0
    public var rng: SplitMix64
    public var elapsed: Double = 0

    public init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
    }

    public mutating func clear() {
        items.removeAll()
        spawnAccumulator = 0
    }

    public mutating func tick(dt: Double, state: inout GameState, events: inout [GameEvent]) {
        elapsed += dt
        let grid = state.grid
        let spec = state.location

        // Haritadan kaldırılmış hücrelerdeki dosyaları düşür.
        items.removeAll { item in
            if grid[item.pos] == nil { events.append(.dropped(item.id)); return true }
            if item.inModule, grid[item.pos]?.module == nil { events.append(.dropped(item.id)); return true }
            return false
        }

        spawn(dt: dt, grid: grid, state: &state, events: &events)

        // Öndeki önce hareket eder: hücre içi ilerlemeye göre azalan sıra.
        let order = items.indices.sorted { items[$0].progress > items[$1].progress }
        var delivered: [Int] = []
        for i in order {
            if items[i].inModule {
                stepModule(i, dt: dt, grid: grid, spec: spec, state: &state, events: &events, delivered: &delivered)
            } else {
                stepBelt(i, dt: dt, grid: grid, state: &state)
            }
        }
        for i in delivered.sorted(by: >) { items.remove(at: i) }

        // Kazanç hızı: üssel ortalama (offline hesap için).
        let earnedNow = events.reduce(0) { acc, e in
            if case .delivered(_, let o) = e { return acc + max(0, o.pay) }
            return acc
        }
        let alpha = min(1, dt / 120.0)
        let instant = Double(earnedNow) / max(dt, 0.0001)
        state.incomeRatePerSec += (instant - state.incomeRatePerSec) * alpha
    }

    // MARK: - Spawn

    private mutating func spawn(dt: Double, grid: Grid, state: inout GameState, events: inout [GameEvent]) {
        let contract = state.activeContract
        spawnAccumulator = min(3, spawnAccumulator + dt * contract.filesPerMinute / 60.0 * state.intakeMultiplier)
        guard spawnAccumulator >= 1 else { return }
        let src = state.location.sourcePos
        guard case .module(let m) = grid[src], m.kind == .source else { return }
        let next = src.moved(m.facing)
        guard canEnter(next, heading: m.facing, grid: grid) else { return }
        spawnAccumulator -= 1
        let file = FileGenerator.make(for: contract, rng: &rng)
        var item = MovingItem(file: file, pos: next, progress: 0, heading: m.facing, inModule: false, remaining: 0, lastNote: nil)
        if case .module(let target) = grid[next]! {
            item.inModule = true
            item.remaining = target.kind.processTime(level: state.level(of: target.kind))
        } else if case .belt(let d) = grid[next]! {
            item.heading = d
        }
        items.append(item)
        events.append(.spawned(file.id))
    }

    // MARK: - Belt

    private mutating func stepBelt(_ i: Int, dt: Double, grid: Grid, state: inout GameState) {
        var item = items[i]
        guard case .belt(let dir) = grid[item.pos] else { return }
        item.heading = dir
        var p = item.progress + state.beltSpeed * dt

        // Aynı hücrede öndeki dosya ile aralık koru.
        if let aheadProgress = items.enumerated()
            .filter({ $0.offset != i && !$0.element.inModule && $0.element.pos == item.pos && $0.element.progress > item.progress })
            .map({ $0.element.progress }).min() {
            p = min(p, max(item.progress, aheadProgress - Self.minGap))
        }

        if p >= 1 {
            let next = item.pos.moved(dir)
            if canEnter(next, heading: dir, grid: grid) {
                let carry = min(p - 1, 0.5)
                item.pos = next
                item.progress = carry
                switch grid[next]! {
                case .belt(let nd): item.heading = nd
                case .module(let m):
                    item.inModule = true
                    item.progress = 0
                    item.remaining = m.kind.processTime(level: state.level(of: m.kind))
                }
            } else {
                item.progress = 1
            }
        } else {
            item.progress = p
        }
        items[i] = item
    }

    // MARK: - Module

    private mutating func stepModule(_ i: Int, dt: Double, grid: Grid, spec: LocationSpec, state: inout GameState,
                                     events: inout [GameEvent], delivered: inout [Int]) {
        var item = items[i]
        guard case .module(let m) = grid[item.pos] else { return }
        item.remaining -= dt
        item.progress = 1 - max(0, item.remaining) / max(0.01, m.kind.processTime(level: state.level(of: m.kind)))
        guard item.remaining <= 0 else { items[i] = item; return }

        switch m.kind {
        case .sink:
            deliver(item.file, state: &state, events: &events)
            delivered.append(i)
            return
        case .quarantine:
            state.stats.totalQuarantined += 1
            events.append(.quarantined(item.id))
            delivered.append(i)
            return
        default:
            break
        }

        // İşlem bir kez uygulanır; sonra çıkış bekler.
        if item.lastNote == nil {
            let notes = ModuleProcessor.apply(m, level: state.level(of: m.kind), airGapped: spec.airGapped, to: &item.file)
            if !notes.isEmpty { events.append(.processed(item.id, m.kind, notes)) }
            item.lastNote = Self.describe(notes) ?? ""
        }

        let out = outputDirection(m, for: item.file)
        let next = item.pos.moved(out)
        if canEnter(next, heading: out, grid: grid) {
            item.pos = next
            item.progress = 0
            item.heading = out
            item.lastNote = nil
            switch grid[next]! {
            case .belt(let nd):
                item.inModule = false
                item.heading = nd
            case .module(let nm):
                item.inModule = true
                item.remaining = nm.kind.processTime(level: state.level(of: nm.kind))
            }
        } else {
            item.remaining = 0
            item.progress = 1
        }
        items[i] = item
    }

    static func describe(_ notes: [ProcessNote]) -> String? {
        notes.first.map { n in
            switch n {
            case .removed(let k, let c): "-\(c) \(k.displayName)"
            case .opened(let d): "açıldı (katman \(d))"
            case .polyglotUnhandled: "polyglot!"
            case .closed: "paketlendi"
            case .imageDegraded(let f): "görsel ×\(String(format: "%.2f", f))"
            case .formulasFlattened(let n): "\(n) formül düzleşti"
            case .noEffect(let s): s
            }
        }
    }

    private func outputDirection(_ m: Module, for file: FileItem) -> Direction {
        if m.kind == .router && file.container == m.config.routeTarget {
            return m.facing.clockwise
        }
        return m.facing
    }

    /// Hedef hücreye `heading` yönünde ilerleyen bir dosya girebilir mi?
    private func canEnter(_ pos: GridPos, heading: Direction, grid: Grid) -> Bool {
        guard let cell = grid[pos] else { return false }
        switch cell {
        case .belt(let d):
            if d == heading.opposite { return false }
            let minProgress = items.filter { !$0.inModule && $0.pos == pos }.map(\.progress).min() ?? 1
            return minProgress >= Self.minGap
        case .module(let m):
            if m.kind == .source { return false }
            if m.kind != .sink && m.kind != .quarantine {
                // Çıkış tarafından giriş olmaz.
                if heading == m.facing.opposite { return false }
                if m.kind == .router && heading == m.facing.clockwise.opposite { return false }
            }
            return !items.contains { $0.inModule && $0.pos == pos }
        }
    }

    // MARK: - Delivery

    private mutating func deliver(_ file: FileItem, state: inout GameState, events: inout [GameEvent]) {
        let contract = state.activeContract
        let outcome = DeliveryEvaluator.evaluate(file, policy: contract.policy, payPerFile: contract.payPerFile)
        state.money += outcome.pay
        state.reputation = max(0, state.reputation + outcome.reputationDelta)
        state.stats.totalDelivered += 1
        state.stats.totalEarned += max(0, outcome.pay)
        var progress = state.progress
        progress.delivered += 1
        if outcome.breach {
            progress.breaches += 1
            state.stats.totalBreaches += 1
        } else if outcome.accepted {
            progress.accepted += 1
            state.stats.totalAccepted += 1
        } else {
            progress.complaints += 1
        }
        events.append(.delivered(file.id, outcome))

        if progress.breaches > contract.maxBreaches {
            progress.resetCounters()
            state.reputation = max(0, state.reputation - 5)
            events.append(.contractFailed(contract))
        } else if progress.delivered >= contract.targetFiles {
            state.money += contract.completionBonus
            state.reputation += contract.reputationReward
            progress.completions += 1
            progress.resetCounters()
            if progress.index < state.location.contracts.count - 1 { progress.index += 1 }
            events.append(.contractCompleted(contract))
        }
        state.progress = progress
    }
}

// MARK: - Offline

public struct OfflineReport: Equatable, Sendable {
    public var seconds: Double
    public var earned: Int
}

public enum OfflineCalculator {
    /// Offline kazanç: son kazanç hızı × süre × %50 verim, 4 saatle sınırlı.
    public static func settle(state: inout GameState, now: Date = Date()) -> OfflineReport? {
        let seconds = min(Simulation.maxOfflineSeconds, now.timeIntervalSince(state.lastSaved))
        guard seconds >= 60, state.incomeRatePerSec > 0 else { return nil }
        let earned = Int(state.incomeRatePerSec * seconds * 0.5)
        guard earned > 0 else { return nil }
        state.money += earned
        state.stats.totalEarned += earned
        return OfflineReport(seconds: seconds, earned: earned)
    }
}

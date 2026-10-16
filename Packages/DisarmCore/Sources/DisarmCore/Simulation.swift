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
    case processed(UUID, GridPos, ModuleKind, [ProcessNote])
    /// Teslim edilen dosyanın son hali ve sonucu; dosya bu anda banttan silinir, inceleme için kopyası olaydadır.
    case delivered(FileItem, DeliveryOutcome)
    case quarantined(UUID)
    case contractCompleted(ContractSpec)
    case contractFailed(ContractSpec)
    /// Mekândaki tüm sözleşmeler ilk kez bitti; sıradaki mekâna geçme zamanı.
    case locationFinished(LocationKind)
    /// Operatör seviyesi atladı (yeni seviye).
    case levelUp(Int)
    case achievementUnlocked(Achievement)
    case incidentStarted(IncidentKind)
    case incidentEnded(IncidentKind)
    /// Tüm mekânlardaki tüm sözleşmeler ilk kez bitti.
    case campaignCompleted
    case dropped(UUID)
}

public struct Simulation: Codable, Hashable, Sendable {
    public static let minGap = 0.4
    public static let maxOfflineSeconds: Double = 4 * 3600

    public var items: [MovingItem] = []
    public var spawnAccumulator: Double = 0
    public var rng: SplitMix64
    public var elapsed: Double = 0
    /// Kazanç hızı penceresi: durum saniyede bir güncellenir, her karede değil (UI gereksiz yere çizilmesin).
    public var incomeAccumulator: Double = 0
    public var incomeTimer: Double = 0
    public static let incomeFlushInterval = 1.0
    /// Ayırıcı başına sayaç: çift düz, tek sağa.
    public var splitCounters: [GridPos: Int] = [:]
    /// Girişte bekleyen dosya sayısı (bu kadar talep karşılanamadı). Bunun üstünde doğan dosyalar "geç" sayılır.
    public static let lateThreshold = 3
    public static let maxBacklog = 20.0
    public var backlog: Int { max(0, Int(spawnAccumulator) - 1) }
    /// Süreli kriz (Incidents.swift). Testler kapatabilir.
    public var activeIncident: Incident?
    public var incidentTimer: Double = 0
    public var incidentsEnabled = true

    public init(seed: UInt64) {
        rng = SplitMix64(seed: seed)
        incidentTimer = nextIncidentDelay()
    }

    public mutating func clear() {
        items.removeAll()
        spawnAccumulator = 0
    }

    public mutating func tick(dt: Double, state: inout GameState, events: inout [GameEvent]) {
        elapsed += dt
        let eventsBefore = events.count
        let grid = state.grid
        let spec = state.location

        // Haritadan kaldırılmış hücrelerdeki dosyaları düşür.
        items.removeAll { item in
            if grid[item.pos] == nil { events.append(.dropped(item.id)); return true }
            if item.inModule, grid[item.pos]?.module == nil { events.append(.dropped(item.id)); return true }
            return false
        }

        // Akarken üstüne modül konan dosya: hücre artık bant değil, bant adımı onu ilerletemez.
        // Modül boşsa işleme girmiş say; doluysa sırasını bekler (bir sonraki tick yeniden dener).
        for i in items.indices where !items[i].inModule {
            guard case .module(let m) = grid[items[i].pos] else { continue }
            let pos = items[i].pos
            let occupied = items.indices.contains { $0 != i && items[$0].inModule && items[$0].pos == pos }
            if occupied { continue }
            items[i].inModule = true
            items[i].progress = 0
            items[i].lastNote = nil
            items[i].remaining = m.kind.processTime(level: state.level(of: m.kind))
        }

        tickIncidents(dt: dt, state: state, events: &events)
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

        // Kazanç hızı: üssel ortalama (offline hesap için). Yalnızca bu çağrıda eklenen olaylar sayılır,
        // ve durum saniyede bir yazılır.
        let earnedNow = events[eventsBefore...].reduce(0) { acc, e in
            if case .delivered(_, let o) = e { return acc + max(0, o.pay) }
            return acc
        }
        incomeAccumulator += Double(earnedNow)
        incomeTimer += dt
        if incomeTimer >= Self.incomeFlushInterval {
            let alpha = min(1, incomeTimer / 120.0)
            let instant = incomeAccumulator / incomeTimer
            state.incomeRatePerSec += (instant - state.incomeRatePerSec) * alpha
            incomeAccumulator = 0
            incomeTimer = 0
        }
    }

    // MARK: - Spawn

    private mutating func spawn(dt: Double, grid: Grid, state: inout GameState, events: inout [GameEvent]) {
        let contract = state.activeContract
        // Talep birikir (sınırlı): hat yetişemezse kuyruk büyür, kuyruk eşiği aşınca doğan dosyalar geç sayılır.
        let rush = rushOrderActive ? 1.5 : 1.0
        spawnAccumulator = min(Self.maxBacklog, spawnAccumulator + dt * contract.filesPerMinute / 60.0 * state.intakeMultiplier * state.prestigeFlowMultiplier * rush)
        guard spawnAccumulator >= 1 else { return }
        let src = state.location.sourcePos
        guard case .module(let m) = grid[src], m.kind == .source else { return }
        let next = src.moved(m.facing)
        guard canEnter(next, heading: m.facing, grid: grid) else { return }
        let waiting = Int(spawnAccumulator)
        spawnAccumulator -= 1
        var file = FileGenerator.make(for: contract, rng: &rng, zeroDay: zeroDayActive)
        if waiting > Self.lateThreshold { file.late = true }
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
            Self.applyProgression(xp: 0, state: &state, events: &events)
            return
        default:
            break
        }

        // İşlem bir kez uygulanır; sonra çıkış bekler.
        if item.lastNote == nil {
            let notes = ModuleProcessor.apply(m, level: state.level(of: m.kind), airGapped: spec.airGapped || signatureOutageActive, to: &item.file)
            if !notes.isEmpty { events.append(.processed(item.id, item.pos, m.kind, notes)) }
            item.lastNote = Self.describe(notes) ?? ""
        }

        // Ayırıcı: sırayla düz/sağ; tercih edilen çıkış doluysa diğerini dener (yük dengeleme).
        let candidates: [Direction]
        if m.kind == .splitter {
            let preferred = splitCounters[item.pos, default: 0] % 2 == 0 ? m.facing : m.facing.clockwise
            let other = preferred == m.facing ? m.facing.clockwise : m.facing
            candidates = [preferred, other]
        } else {
            candidates = [outputDirection(m, for: item.file)]
        }
        let out = candidates.first { canEnter(item.pos.moved($0), heading: $0, grid: grid) } ?? candidates[0]
        let next = item.pos.moved(out)
        if canEnter(next, heading: out, grid: grid) {
            if m.kind == .splitter { splitCounters[item.pos, default: 0] += 1 }
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

    public static func describe(_ notes: [ProcessNote]) -> String? {
        notes.first.map { n in
            switch n {
            case .removed(let k, let c): "-\(c) \(k.displayName)"
            case .opened(let d): L("opened (layer \(d))")
            case .polyglotUnhandled: "polyglot!"
            case .closed: L("packaged")
            case .imageDegraded(let f): L("image ×\(String(format: "%.2f", f))")
            case .formulasFlattened(let n): L("\(n) formulas flattened")
            case .noEffect(let s): s
            }
        }
    }

    private func outputDirection(_ m: Module, for file: FileItem) -> Direction {
        if m.kind == .router && m.config.diverts(file) {
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
                if (m.kind == .router || m.kind == .splitter) && heading == m.facing.clockwise.opposite { return false }
            }
            return !items.contains { $0.inModule && $0.pos == pos }
        }
    }

    // MARK: - Delivery

    private mutating func deliver(_ file: FileItem, state: inout GameState, events: inout [GameEvent]) {
        let contract = state.activeContract
        let payPerFile = Int((Double(contract.payPerFile) * state.prestigePayMultiplier * (rushOrderActive ? 2 : 1)).rounded())
        let outcome = DeliveryEvaluator.evaluate(file, policy: contract.policy, payPerFile: payPerFile)
        state.money += outcome.pay
        state.reputation = max(0, state.reputation + outcome.reputationDelta)
        state.stats.totalDelivered += 1
        state.stats.totalEarned += max(0, outcome.pay)
        var progress = state.progress
        progress.delivered += 1
        var xpGain = 0
        if outcome.breach {
            progress.breaches += 1
            state.stats.totalBreaches += 1
            state.stats.acceptedStreak = 0
            for issue in outcome.issues {
                if case .breach(let kinds) = issue {
                    for k in Set(kinds) { progress.breachReasons[k, default: 0] += 1 }
                }
            }
        } else if outcome.accepted {
            progress.accepted += 1
            state.stats.totalAccepted += 1
            state.stats.acceptedStreak += 1
            state.stats.bestAcceptedStreak = max(state.stats.bestAcceptedStreak, state.stats.acceptedStreak)
            xpGain += Progression.xp(forAcceptedDeliveryTier: contract.tier)
        } else {
            progress.complaints += 1
            state.stats.acceptedStreak = 0
            for reason in outcome.issues.compactMap(\.reason) {
                progress.complaintReasons[reason, default: 0] += 1
            }
        }
        events.append(.delivered(file, outcome))

        if progress.breaches > (auditActive ? 0 : contract.maxBreaches) {
            progress.resetCounters()
            state.reputation = max(0, state.reputation - 5)
            events.append(.contractFailed(contract))
        } else if progress.delivered >= contract.targetFiles {
            state.money += Int((Double(contract.completionBonus) * state.prestigePayMultiplier).rounded())
            state.reputation += contract.reputationReward
            state.stats.contractsCompleted += 1
            if progress.complaints == 0 && progress.breaches == 0 { state.stats.cleanContracts += 1 }
            xpGain += Progression.xp(forContractReputation: contract.reputationReward)
            progress.completions += 1
            progress.resetCounters()
            if progress.index < state.location.contracts.count - 1 { progress.index += 1 }
            events.append(.contractCompleted(contract))
            state.progress = progress
            if progress.completions == state.location.contracts.count {
                events.append(.locationFinished(state.currentLocation))
            }
            if !state.campaignCompleted && state.campaignFinished {
                state.campaignCompleted = true
                state.stats.campaignsCompleted += 1
                if state.stats.bestCampaignSeconds == 0 || elapsed < state.stats.bestCampaignSeconds {
                    state.stats.bestCampaignSeconds = elapsed
                }
                events.append(.campaignCompleted)
            }
            Self.applyProgression(xp: xpGain, state: &state, events: &events)
            return
        }
        state.progress = progress
        Self.applyProgression(xp: xpGain, state: &state, events: &events)
    }

    /// XP ekler, seviye atlamayı ve yeni başarımları olay olarak bildirir (başarımların XP'si de seviye atlatabilir).
    static func applyProgression(xp: Int, state: inout GameState, events: inout [GameEvent]) {
        let before = state.level
        state.xp += xp
        for a in state.claimAchievements() { events.append(.achievementUnlocked(a)) }
        if state.level > before { events.append(.levelUp(state.level)) }
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

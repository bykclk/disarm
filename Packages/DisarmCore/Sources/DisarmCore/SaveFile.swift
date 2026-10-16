import Foundation

/// Diske yazılan kayıt. `version` ileride şekil değişikliklerinde göç için kullanılır.
/// Sürüm 0: `version` alanı olmayan ilk kayıtlar (yalnızca `state` + `sim`).
public struct SaveFile: Codable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var state: GameState
    /// Banttaki dosyalar geçici veridir; çözülemezse kayıt yine de yüklenir.
    public var sim: Simulation?

    public init(state: GameState, sim: Simulation?) {
        version = Self.currentVersion
        self.state = state
        self.sim = sim
    }

    enum CodingKeys: String, CodingKey { case version, state, sim }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 0
        state = try c.decode(GameState.self, forKey: .state)
        sim = try? c.decodeIfPresent(Simulation.self, forKey: .sim)
    }
}

/// Yüklemede yapılan onarımlar; günlükte gösterilir, testlerde doğrulanır.
public enum SaveRepair: Equatable, Sendable {
    case migrated(from: Int)
    case simulationReset
    case layoutResized(LocationKind)
    case layoutAdded(LocationKind)
    case locationUnlocked(LocationKind)
    case contractProgressAdded(LocationKind)
    case levelsClamped
    case contractIndexClamped(LocationKind)
    case anchorsRestored(LocationKind)
}

public struct LoadedSave: Sendable {
    public var state: GameState
    public var sim: Simulation
    public var repairs: [SaveRepair]
}

/// Kayıt dosyasını üretir ve eski/bozuk kayıtları olabildiğince kurtararak okur.
public enum SaveCodec {
    public static func encode(state: GameState, sim: Simulation) throws -> Data {
        try JSONEncoder().encode(SaveFile(state: state, sim: sim))
    }

    /// `state` çözülemiyorsa nil: kayıt kurtarılamaz. Diğer her eksiklik onarılır.
    public static func decode(_ data: Data) -> LoadedSave? {
        guard let file = try? JSONDecoder().decode(SaveFile.self, from: data) else { return nil }
        return load(file)
    }

    public static func load(_ file: SaveFile) -> LoadedSave {
        var repairs: [SaveRepair] = []
        var state = file.state
        if file.version < SaveFile.currentVersion {
            migrate(&state, from: file.version)
            repairs.append(.migrated(from: file.version))
        }
        repairs += SaveMigrator.repair(&state)

        let sim: Simulation
        if let saved = file.sim {
            sim = saved
        } else {
            sim = Simulation(seed: state.rngSeed)
            repairs.append(.simulationReset)
        }
        return LoadedSave(state: state, sim: sim, repairs: repairs)
    }

    /// Sürüm zinciri: her adım bir sonraki sürüme taşır. Yeni sürümde buraya `case` ekle.
    static func migrate(_ state: inout GameState, from version: Int) {
        var v = version
        while v < SaveFile.currentVersion {
            switch v {
            case 0:
                // 0 -> 1: alanlar aynı, yalnızca sürüm damgası eklendi.
                break
            default:
                break
            }
            v += 1
        }
    }
}

/// Kayıt ile güncel mekân/modül tanımları arasındaki tutarsızlıkları giderir.
public enum SaveMigrator {
    @discardableResult
    public static func repair(_ s: inout GameState) -> [SaveRepair] {
        var repairs: [SaveRepair] = []

        // Mekânlar: başlangıç mekânı ve içinde bulunulan mekân her zaman açık olmalı.
        for kind in [LocationKind.smallOffice, s.currentLocation] where !s.unlockedLocations.contains(kind) {
            s.unlockedLocations.insert(kind)
            repairs.append(.locationUnlocked(kind))
        }

        // Her açık mekânın tanıma uyan bir yerleşimi ve sözleşme ilerlemesi olmalı.
        for kind in LocationKind.allCases where s.unlockedLocations.contains(kind) {
            let spec = kind.spec
            if let grid = s.layouts[kind] {
                if grid.width != spec.width || grid.height != spec.height {
                    s.layouts[kind] = refit(grid, to: spec)
                    repairs.append(.layoutResized(kind))
                } else if restoreAnchors(&s.layouts[kind]!, spec: spec) {
                    repairs.append(.anchorsRestored(kind))
                }
            } else {
                s.layouts[kind] = spec.emptyGrid()
                repairs.append(.layoutAdded(kind))
            }

            if s.contracts[kind] == nil {
                s.contracts[kind] = ContractProgress()
                repairs.append(.contractProgressAdded(kind))
            }
            let maxIndex = max(0, spec.contracts.count - 1)
            if let p = s.contracts[kind], p.index > maxIndex || p.index < 0 {
                s.contracts[kind]!.index = min(max(0, p.index), maxIndex)
                repairs.append(.contractIndexClamped(kind))
            }
        }

        // Seviyeler tanımlı aralıkta kalsın.
        var clamped = false
        for (kind, level) in s.moduleLevels {
            let fixed = min(max(1, level), kind.maxLevel)
            if fixed != level { s.moduleLevels[kind] = fixed; clamped = true }
        }
        let belt = min(max(1, s.beltLevel), GameState.maxBeltLevel)
        if belt != s.beltLevel { s.beltLevel = belt; clamped = true }
        let intake = min(max(1, s.intakeLevel), GameState.maxIntakeLevel)
        if intake != s.intakeLevel { s.intakeLevel = intake; clamped = true }
        if clamped { repairs.append(.levelsClamped) }

        return repairs
    }

    /// Eski boyuttaki yerleşimi yeni boyuta taşır: sığan hücreler korunur, giriş/çıkış yeni yerine konur.
    static func refit(_ old: Grid, to spec: LocationSpec) -> Grid {
        var g = spec.emptyGrid()
        for p in old.allPositions where g.contains(p) {
            guard let cell = old[p] else { continue }
            if p == spec.sourcePos || p == spec.sinkPos { continue }
            if let m = cell.module, !m.kind.isPlaceable { continue } // eski giriş/çıkış
            g[p] = cell
        }
        return g
    }

    /// Giriş ve çıkış modülleri tanımdaki yerlerinde değilse yerine koyar. Değişiklik olduysa true.
    static func restoreAnchors(_ g: inout Grid, spec: LocationSpec) -> Bool {
        var changed = false
        // Yanlış yerdeki giriş/çıkışları kaldır.
        for p in g.allPositions {
            guard let m = g[p]?.module, !m.kind.isPlaceable else { continue }
            let expected = m.kind == .source ? spec.sourcePos : spec.sinkPos
            if p != expected { g[p] = nil; changed = true }
        }
        if g[spec.sourcePos]?.module?.kind != .source {
            g[spec.sourcePos] = .module(Module(kind: .source, facing: spec.sourceFacing))
            changed = true
        }
        if g[spec.sinkPos]?.module?.kind != .sink {
            g[spec.sinkPos] = .module(Module(kind: .sink, facing: .down))
            changed = true
        }
        return changed
    }
}

// MARK: - Toleranslı çözümleme yardımcıları

/// Çözülemeyen değeri nil yapar (dizi elemanı, sözlük değeri ya da isteğe bağlı alan).
struct Lossy<T: Decodable>: Decodable {
    var value: T?
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        value = c.decodeNil() ? nil : try? c.decode(T.self)
    }
}

extension KeyedDecodingContainer {
    /// Alan yoksa ya da çözülemiyorsa varsayılanı döner.
    func decodeOr<T: Decodable>(_ type: T.Type, _ key: Key, _ fallback: T) -> T {
        (try? decodeIfPresent(Lossy<T>.self, forKey: key))??.value ?? fallback
    }

    /// Ham değeri `String` olan enum anahtarlı sözlük; tanınmayan anahtar ve çözülemeyen değerler atılır.
    /// Yeni kayıtlar JSON nesnesi, sürüm 0 kayıtları ise `[anahtar, değer, ...]` düz dizisi kullanır.
    func decodeEnumDict<E: RawRepresentable & Hashable, V: Decodable>(_ key: Key, as: E.Type = E.self) -> [E: V]
    where E.RawValue == String {
        var out: [E: V] = [:]
        if let raw = try? decodeIfPresent([String: Lossy<V>].self, forKey: key) {
            for (k, v) in raw {
                if let kind = E(rawValue: k), let value = v.value { out[kind] = value }
            }
            return out
        }
        guard var u = try? nestedUnkeyedContainer(forKey: key) else { return out }
        while !u.isAtEnd {
            guard let k = try? u.decode(String.self) else { break }
            guard !u.isAtEnd, let v = try? u.decode(Lossy<V>.self) else { break }
            if let kind = E(rawValue: k), let value = v.value { out[kind] = value }
        }
        return out
    }

    /// Ham değeri `String` olan enum kümesi; tanınmayanlar atılır.
    func decodeEnumSet<E: RawRepresentable & Hashable>(_ key: Key, as: E.Type = E.self) -> Set<E>
    where E.RawValue == String {
        let raw = (try? decodeIfPresent([Lossy<String>].self, forKey: key)) ?? []
        return Set(raw.compactMap { $0.value.flatMap(E.init(rawValue:)) })
    }
}

/// Enum anahtarlı sözlükler JSON nesnesi olarak yazılsın (bildirilmezse düz dizi olur).
extension LocationKind: CodingKeyRepresentable {}
extension ModuleKind: CodingKeyRepresentable {}
extension PartKind: CodingKeyRepresentable {}

// MARK: - Toleranslı init(from:) uygulamaları
// Kodlama sentezlenir; yalnızca çözümleme elle yazılır ki eksik/bozuk alan kaydı düşürmesin.

extension Stats {
    enum CodingKeys: String, CodingKey {
        case totalDelivered, totalAccepted, totalBreaches, totalEarned, totalQuarantined
        case contractsCompleted, campaignsCompleted, bestCampaignSeconds
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        totalDelivered = c.decodeOr(Int.self, .totalDelivered, 0)
        totalAccepted = c.decodeOr(Int.self, .totalAccepted, 0)
        totalBreaches = c.decodeOr(Int.self, .totalBreaches, 0)
        totalEarned = c.decodeOr(Int.self, .totalEarned, 0)
        totalQuarantined = c.decodeOr(Int.self, .totalQuarantined, 0)
        contractsCompleted = c.decodeOr(Int.self, .contractsCompleted, 0)
        campaignsCompleted = c.decodeOr(Int.self, .campaignsCompleted, 0)
        bestCampaignSeconds = c.decodeOr(Double.self, .bestCampaignSeconds, 0)
    }
}

extension ContractProgress {
    enum CodingKeys: String, CodingKey {
        case index, delivered, accepted, breaches, complaints, completions, complaintReasons, breachReasons
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(index: c.decodeOr(Int.self, .index, 0))
        delivered = c.decodeOr(Int.self, .delivered, 0)
        accepted = c.decodeOr(Int.self, .accepted, 0)
        breaches = c.decodeOr(Int.self, .breaches, 0)
        complaints = c.decodeOr(Int.self, .complaints, 0)
        completions = c.decodeOr(Int.self, .completions, 0)
        complaintReasons = c.decodeOr([ComplaintReason: Int].self, .complaintReasons, [:])
        breachReasons = c.decodeEnumDict(.breachReasons)
    }
}

extension ModuleConfig {
    enum CodingKeys: String, CodingKey { case filterTarget, routeTarget, routeEncrypted }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ModuleConfig()
        self.init(
            filterTarget: c.decodeOr(PartKind.self, .filterTarget, d.filterTarget),
            routeTarget: c.decodeOr(ContainerKind.self, .routeTarget, d.routeTarget),
            routeEncrypted: c.decodeOr(Bool.self, .routeEncrypted, false)
        )
    }
}

extension FileItem {
    enum CodingKeys: String, CodingKey {
        case id, container, parts, isOpen, exposedDepth, polyglot, imageQuality, originalKinds, tier, encrypted
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Kap ve parçalar olmadan dosya anlamsız; bunlar zorunlu (Lossy üstte düşürür).
        let container = try c.decode(ContainerKind.self, forKey: .container)
        let parts = try c.decode([Part].self, forKey: .parts)
        self.init(container: container, parts: parts,
                  polyglot: c.decodeOr(Bool.self, .polyglot, false),
                  tier: c.decodeOr(Int.self, .tier, 0),
                  encrypted: c.decodeOr(Bool.self, .encrypted, false),
                  id: c.decodeOr(UUID.self, .id, UUID()))
        isOpen = c.decodeOr(Bool.self, .isOpen, false)
        exposedDepth = c.decodeOr(Int.self, .exposedDepth, -1)
        imageQuality = c.decodeOr(Double.self, .imageQuality, 1.0)
        originalKinds = c.decodeEnumSet(.originalKinds)
    }
}

extension Module {
    enum CodingKeys: String, CodingKey { case kind, facing, config }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Tanınmayan modül türü kurtarılamaz: hücre boş kalır (Lossy üstte yakalar).
        let kind = try c.decode(ModuleKind.self, forKey: .kind)
        self.init(
            kind: kind,
            facing: c.decodeOr(Direction.self, .facing, .right),
            config: c.decodeOr(ModuleConfig.self, .config, ModuleConfig())
        )
    }
}

extension Grid {
    enum CodingKeys: String, CodingKey { case width, height, cells }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let w = try c.decode(Int.self, forKey: .width)
        let h = try c.decode(Int.self, forKey: .height)
        guard w > 0, h > 0 else {
            throw DecodingError.dataCorruptedError(forKey: .width, in: c, debugDescription: "invalid grid size")
        }
        self.init(width: w, height: h)
        let raw = (try? c.decodeIfPresent([Lossy<Cell>].self, forKey: .cells)) ?? []
        for (i, cell) in raw.prefix(w * h).enumerated() {
            self[GridPos(i % w, i / w)] = cell.value
        }
    }
}

extension GameState {
    enum CodingKeys: String, CodingKey {
        case money, reputation, currentLocation, unlockedLocations, layouts, contracts
        case moduleLevels, beltLevel, intakeLevel, stats, lastSaved, incomeRatePerSec, rngSeed, tutorialSeen
        case prestige, campaignCompleted, seenHints
    }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fresh = GameState()
        self.init(seed: c.decodeOr(UInt64.self, .rngSeed, fresh.rngSeed))
        money = c.decodeOr(Int.self, .money, fresh.money)
        reputation = c.decodeOr(Int.self, .reputation, 0)
        currentLocation = c.decodeOr(LocationKind.self, .currentLocation, .smallOffice)
        unlockedLocations = c.decodeEnumSet(.unlockedLocations)
        layouts = c.decodeEnumDict(.layouts)
        contracts = c.decodeEnumDict(.contracts)
        moduleLevels = c.decodeEnumDict(.moduleLevels)
        beltLevel = c.decodeOr(Int.self, .beltLevel, 1)
        intakeLevel = c.decodeOr(Int.self, .intakeLevel, 1)
        stats = c.decodeOr(Stats.self, .stats, Stats())
        lastSaved = c.decodeOr(Date.self, .lastSaved, Date())
        incomeRatePerSec = c.decodeOr(Double.self, .incomeRatePerSec, 0)
        tutorialSeen = c.decodeOr(Bool.self, .tutorialSeen, false)
        prestige = max(0, c.decodeOr(Int.self, .prestige, 0))
        campaignCompleted = c.decodeOr(Bool.self, .campaignCompleted, false)
        seenHints = c.decodeEnumSet(.seenHints)
        // Yerleşim/sözleşme eksikleri SaveMigrator.repair ile tamamlanır.
    }
}

extension Simulation {
    enum CodingKeys: String, CodingKey { case items, spawnAccumulator, rng, elapsed }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Üreteç durumu olmadan simülasyon tutarsız olur; o zaman tümü sıfırlanır.
        let rng = try c.decode(SplitMix64.self, forKey: .rng)
        self.init(seed: 0)
        self.rng = rng
        items = ((try? c.decodeIfPresent([Lossy<MovingItem>].self, forKey: .items)) ?? []).compactMap(\.value)
        spawnAccumulator = c.decodeOr(Double.self, .spawnAccumulator, 0)
        elapsed = c.decodeOr(Double.self, .elapsed, 0)
    }
}

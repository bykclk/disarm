import Foundation

public struct Stats: Codable, Hashable, Sendable {
    public var totalDelivered = 0
    public var totalAccepted = 0
    public var totalBreaches = 0
    public var totalEarned = 0
    public var totalQuarantined = 0
    public var contractsCompleted = 0
    public var campaignsCompleted = 0
    /// En hızlı kampanya süresi (simülasyon saniyesi); 0 = henüz yok.
    public var bestCampaignSeconds: Double = 0
    public init() {}
}

public struct GameState: Codable, Hashable, Sendable {
    public static let startingMoney = 600
    public static let beltCost = 5
    public static let maxBeltLevel = 5
    public static let maxIntakeLevel = 5

    public var money: Int
    public var reputation: Int
    public var currentLocation: LocationKind
    public var unlockedLocations: Set<LocationKind>
    public var layouts: [LocationKind: Grid]
    public var contracts: [LocationKind: ContractProgress]
    public var moduleLevels: [ModuleKind: Int]
    public var beltLevel: Int
    public var intakeLevel: Int
    public var stats: Stats
    public var lastSaved: Date
    /// Son dakikalardaki kazanç hızının üssel ortalaması (para/sn). Offline hesap için.
    public var incomeRatePerSec: Double
    public var rngSeed: UInt64
    public var tutorialSeen: Bool
    /// Tamamlanan kampanya sayısı; her seviye ödemeyi ve akışı artırır.
    public var prestige: Int
    /// Bu kampanyada tüm sözleşmeler bir kez bitti mi? (Sonsuz oyun sürer, prestij açılır.)
    public var campaignCompleted: Bool
    /// Kapatılmış ipucu kartları; prestijde korunur.
    public var seenHints: Set<Hint>

    public init(seed: UInt64 = UInt64(Date().timeIntervalSince1970)) {
        money = Self.startingMoney
        reputation = 0
        currentLocation = .smallOffice
        unlockedLocations = [.smallOffice]
        layouts = [.smallOffice: LocationKind.smallOffice.spec.emptyGrid()]
        contracts = [.smallOffice: ContractProgress()]
        moduleLevels = [:]
        beltLevel = 1
        intakeLevel = 1
        stats = Stats()
        lastSaved = Date()
        incomeRatePerSec = 0
        rngSeed = seed
        tutorialSeen = false
        prestige = 0
        campaignCompleted = false
        seenHints = []
    }

    // MARK: - Kampanya ve prestij

    public static let prestigePayBonus = 0.15
    public static let prestigeFlowBonus = 0.10
    public static let prestigeStartingBonus = 300

    public static var totalContractCount: Int { LocationKind.allCases.reduce(0) { $0 + $1.spec.contracts.count } }

    /// Mekândaki her sözleşme en az bir kez tamamlandı mı?
    public func isFinished(_ kind: LocationKind) -> Bool {
        completedContracts(in: kind) >= kind.spec.contracts.count
    }

    /// Mekânda en az bir kez tamamlanmış sözleşme sayısı.
    public func completedContracts(in kind: LocationKind) -> Int {
        guard let p = contracts[kind] else { return 0 }
        return min(p.completions, kind.spec.contracts.count)
    }

    public var completedContractCount: Int { LocationKind.allCases.reduce(0) { $0 + completedContracts(in: $1) } }

    public var campaignFinished: Bool { LocationKind.allCases.allSatisfy(isFinished) }

    public var prestigePayMultiplier: Double { 1.0 + Self.prestigePayBonus * Double(prestige) }
    public var prestigeFlowMultiplier: Double { 1.0 + Self.prestigeFlowBonus * Double(prestige) }

    /// Yeni kampanya: ilerleme sıfırlanır, istatistikler ve öğretici kalır, prestij bir artar.
    public mutating func startNewCampaign() {
        let keptStats = stats
        let seenTutorial = tutorialSeen
        let keptHints = seenHints
        let nextPrestige = prestige + 1
        self = GameState(seed: rngSeed &+ 1)
        stats = keptStats
        tutorialSeen = seenTutorial
        seenHints = keptHints
        prestige = nextPrestige
        money += Self.prestigeStartingBonus * nextPrestige
    }

    public var location: LocationSpec { currentLocation.spec }

    public var grid: Grid {
        get { layouts[currentLocation] ?? location.emptyGrid() }
        set { layouts[currentLocation] = newValue }
    }

    public var progress: ContractProgress {
        get { contracts[currentLocation] ?? ContractProgress() }
        set { contracts[currentLocation] = newValue }
    }

    public var activeContract: ContractSpec {
        let list = location.contracts
        return list[min(progress.index, list.count - 1)]
    }

    public func level(of kind: ModuleKind) -> Int { moduleLevels[kind] ?? 1 }

    public var beltSpeed: Double { 1.2 * (1.0 + 0.25 * Double(beltLevel - 1)) }
    public var intakeMultiplier: Double { 1.0 + 0.3 * Double(intakeLevel - 1) }

    public func beltUpgradeCost() -> Int { 150 * beltLevel * beltLevel }
    public func intakeUpgradeCost() -> Int { 200 * intakeLevel * intakeLevel }

    // MARK: - Satın alma / yerleştirme

    public enum ActionError: Error, Equatable, Sendable {
        case insufficientFunds(needed: Int)
        case cellOccupied
        case outOfBounds
        case notPlaceable
        case notAvailableHere
        case protected
        case maxLevel
        case locked
        case reputationTooLow(needed: Int)
    }

    @discardableResult
    public mutating func placeBelt(at p: GridPos, facing: Direction) -> Result<Void, ActionError> {
        guard grid.contains(p) else { return .failure(.outOfBounds) }
        if let existing = grid[p] {
            if existing.module != nil { return .failure(.cellOccupied) }
            grid[p] = .belt(facing) // yön değiştirme bedava
            return .success(())
        }
        guard money >= Self.beltCost else { return .failure(.insufficientFunds(needed: Self.beltCost)) }
        money -= Self.beltCost
        grid[p] = .belt(facing)
        return .success(())
    }

    @discardableResult
    public mutating func placeModule(_ kind: ModuleKind, at p: GridPos, facing: Direction) -> Result<Void, ActionError> {
        guard kind.isPlaceable else { return .failure(.notPlaceable) }
        guard location.availableModules.contains(kind) else { return .failure(.notAvailableHere) }
        guard grid.contains(p) else { return .failure(.outOfBounds) }
        if grid[p]?.module != nil { return .failure(.cellOccupied) }
        let refund = grid[p]?.beltDirection != nil ? Self.beltCost : 0
        guard money + refund >= kind.baseCost else { return .failure(.insufficientFunds(needed: kind.baseCost)) }
        money += refund - kind.baseCost
        grid[p] = .module(Module(kind: kind, facing: facing))
        return .success(())
    }

    /// Modülü başka hücreye taşır (ayarı ve yönü korunur). Hedefteki bant iade edilir; hedefte modül varsa olmaz.
    @discardableResult
    public mutating func moveModule(from a: GridPos, to b: GridPos) -> Result<Void, ActionError> {
        guard grid.contains(a), grid.contains(b) else { return .failure(.outOfBounds) }
        guard case .module(let m) = grid[a] else { return .failure(.outOfBounds) }
        guard m.kind.isPlaceable else { return .failure(.protected) }
        if a == b { return .success(()) }
        if grid[b]?.module != nil { return .failure(.cellOccupied) }
        if grid[b]?.beltDirection != nil { money += Self.beltCost }
        grid[b] = .module(m)
        grid[a] = nil
        return .success(())
    }

    @discardableResult
    public mutating func rotate(at p: GridPos) -> Result<Void, ActionError> {
        switch grid[p] {
        case .belt(let d): grid[p] = .belt(d.clockwise)
        case .module(var m):
            guard m.kind.isPlaceable else { return .failure(.protected) }
            m.facing = m.facing.clockwise
            grid[p] = .module(m)
        case nil: return .failure(.outOfBounds)
        }
        return .success(())
    }

    @discardableResult
    public mutating func configure(at p: GridPos, _ change: (inout ModuleConfig) -> Void) -> Result<Void, ActionError> {
        guard case .module(var m) = grid[p] else { return .failure(.outOfBounds) }
        change(&m.config)
        grid[p] = .module(m)
        return .success(())
    }

    /// Kaldırır; modüller %50, bantlar tam iade.
    @discardableResult
    public mutating func remove(at p: GridPos) -> Result<Void, ActionError> {
        switch grid[p] {
        case .belt: money += Self.beltCost
        case .module(let m):
            guard m.kind.isPlaceable else { return .failure(.protected) }
            money += m.kind.baseCost / 2
        case nil: return .failure(.outOfBounds)
        }
        grid[p] = nil
        return .success(())
    }

    @discardableResult
    public mutating func upgradeModule(_ kind: ModuleKind) -> Result<Void, ActionError> {
        let current = level(of: kind)
        guard current < kind.maxLevel else { return .failure(.maxLevel) }
        let cost = kind.upgradeCost(toLevel: current + 1)
        guard money >= cost else { return .failure(.insufficientFunds(needed: cost)) }
        money -= cost
        moduleLevels[kind] = current + 1
        return .success(())
    }

    @discardableResult
    public mutating func upgradeBelt() -> Result<Void, ActionError> {
        guard beltLevel < Self.maxBeltLevel else { return .failure(.maxLevel) }
        let cost = beltUpgradeCost()
        guard money >= cost else { return .failure(.insufficientFunds(needed: cost)) }
        money -= cost
        beltLevel += 1
        return .success(())
    }

    @discardableResult
    public mutating func upgradeIntake() -> Result<Void, ActionError> {
        guard intakeLevel < Self.maxIntakeLevel else { return .failure(.maxLevel) }
        let cost = intakeUpgradeCost()
        guard money >= cost else { return .failure(.insufficientFunds(needed: cost)) }
        money -= cost
        intakeLevel += 1
        return .success(())
    }

    @discardableResult
    public mutating func unlockLocation(_ kind: LocationKind) -> Result<Void, ActionError> {
        guard !unlockedLocations.contains(kind) else { return .success(()) }
        let spec = kind.spec
        guard reputation >= spec.unlockReputation else { return .failure(.reputationTooLow(needed: spec.unlockReputation)) }
        guard money >= spec.unlockCost else { return .failure(.insufficientFunds(needed: spec.unlockCost)) }
        money -= spec.unlockCost
        unlockedLocations.insert(kind)
        layouts[kind] = spec.emptyGrid()
        contracts[kind] = ContractProgress()
        return .success(())
    }

    @discardableResult
    public mutating func switchLocation(_ kind: LocationKind) -> Result<Void, ActionError> {
        guard unlockedLocations.contains(kind) else { return .failure(.locked) }
        currentLocation = kind
        return .success(())
    }
}

public extension Result where Success == Void {
    var error: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
    var isSuccess: Bool { error == nil }
}

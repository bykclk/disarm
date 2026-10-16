import Foundation

// MARK: - Operatör seviyesi

/// Deneyim puanı ve seviye: kabul edilen teslimat, biten sözleşme ve başarımlar XP verir; seviye yeni modül ve
/// yükseltme kademeleri açar. XP hiç azalmaz (itibar azalabilir; o mekân kilidi için).
public enum Progression {
    public static let maxLevel = 30

    /// `level` seviyesine ulaşmak için gereken toplam XP. 1. seviye 0; sonra kabaca 10·n² büyür.
    public static func xp(forLevel level: Int) -> Int {
        guard level > 1 else { return 0 }
        return 10 * (level - 1) * (level + 1)
    }

    public static func level(forXP points: Int) -> Int {
        var level = 1
        while level < maxLevel && points >= xp(forLevel: level + 1) { level += 1 }
        return level
    }

    /// Kabul edilen teslimat başına XP: zor sözleşmeler daha çok verir.
    public static func xp(forAcceptedDeliveryTier tier: Int) -> Int { 1 + tier / 3 }

    /// Sözleşme tamamlanınca XP: itibar ödülünün iki katı.
    public static func xp(forContractReputation reward: Int) -> Int { reward * 2 }

    /// Yükseltme kademesi için gereken oyuncu seviyesi (modülün 2. seviyesi için 3, 3. seviyesi için 6).
    public static func requiredLevel(forUpgradeTo level: Int) -> Int {
        switch level {
        case ...1: 1
        case 2: 3
        default: 6
        }
    }
}

public extension ModuleKind {
    /// Modülün palette açılması için gereken oyuncu seviyesi.
    var requiredLevel: Int {
        switch self {
        case .source, .sink, .parser, .filter, .packager: 1
        case .scanner: 2
        case .quarantine, .splitter: 3
        case .router: 4
        case .transformer: 5
        case .sandbox: 7
        }
    }
}

public extension GameState {
    var level: Int { Progression.level(forXP: xp) }
    /// Bu seviyede biriken XP ve bir sonraki seviyeye gereken toplam (son seviyede ikisi eşit).
    var xpProgress: (current: Int, needed: Int) {
        let base = Progression.xp(forLevel: level)
        guard level < Progression.maxLevel else { return (1, 1) }
        return (xp - base, Progression.xp(forLevel: level + 1) - base)
    }

    func isUnlocked(_ kind: ModuleKind) -> Bool { level >= kind.requiredLevel }

    /// Bu seviyede yeni açılan modüller (seviye atlama kartı için).
    static func modulesUnlocked(atLevel level: Int) -> [ModuleKind] {
        ModuleKind.allCases.filter { $0.isPlaceable && $0.requiredLevel == level }
    }

    /// XP ekler; seviye arttıysa yeni seviyeyi döner.
    @discardableResult
    mutating func gainXP(_ amount: Int) -> Int? {
        let before = level
        xp += max(0, amount)
        let after = level
        return after > before ? after : nil
    }
}

// MARK: - Başarımlar

public enum Achievement: String, Codable, CaseIterable, Sendable {
    case firstDelivery, hundredFiles, thousandFiles
    case streak25, streak100
    case cleanContract, fiveCleanContracts
    case firstQuarantine, firstUpgrade
    case secondSite, allSites, campaign

    public var displayName: String {
        switch self {
        case .firstDelivery: L("First Delivery")
        case .hundredFiles: L("Hundred Files")
        case .thousandFiles: L("Thousand Files")
        case .streak25: L("Hot Streak")
        case .streak100: L("Flawless Hundred")
        case .cleanContract: L("Spotless Contract")
        case .fiveCleanContracts: L("Trusted Vendor")
        case .firstQuarantine: L("Better Safe")
        case .firstUpgrade: L("Tuned Up")
        case .secondSite: L("Expanding")
        case .allSites: L("Everywhere at Once")
        case .campaign: L("Campaign Veteran")
        }
    }

    public var detail: String {
        switch self {
        case .firstDelivery: L("Deliver a file the customer accepts.")
        case .hundredFiles: L("Deliver 100 files.")
        case .thousandFiles: L("Deliver 1,000 files.")
        case .streak25: L("25 accepted deliveries in a row.")
        case .streak100: L("100 accepted deliveries in a row.")
        case .cleanContract: L("Complete a contract with no complaints and no breaches.")
        case .fiveCleanContracts: L("Complete five spotless contracts.")
        case .firstQuarantine: L("Send a file to quarantine.")
        case .firstUpgrade: L("Buy your first module upgrade.")
        case .secondSite: L("Unlock a second site.")
        case .allSites: L("Unlock every site.")
        case .campaign: L("Finish the campaign.")
        }
    }

    public var icon: String {
        switch self {
        case .firstDelivery: "paperplane.fill"
        case .hundredFiles, .thousandFiles: "shippingbox.fill"
        case .streak25, .streak100: "flame.fill"
        case .cleanContract, .fiveCleanContracts: "checkmark.seal.fill"
        case .firstQuarantine: "trash.fill"
        case .firstUpgrade: "arrow.up.circle.fill"
        case .secondSite, .allSites: "map.fill"
        case .campaign: "trophy.fill"
        }
    }

    public var rewardMoney: Int {
        switch self {
        case .firstDelivery: 50
        case .hundredFiles: 300
        case .thousandFiles: 2000
        case .streak25: 400
        case .streak100: 2500
        case .cleanContract: 300
        case .fiveCleanContracts: 1500
        case .firstQuarantine: 100
        case .firstUpgrade: 150
        case .secondSite: 500
        case .allSites: 5000
        case .campaign: 10000
        }
    }

    public var rewardXP: Int {
        switch self {
        case .firstDelivery: 10
        case .hundredFiles: 40
        case .thousandFiles: 150
        case .streak25: 60
        case .streak100: 200
        case .cleanContract: 50
        case .fiveCleanContracts: 150
        case .firstQuarantine: 20
        case .firstUpgrade: 30
        case .secondSite: 80
        case .allSites: 300
        case .campaign: 500
        }
    }

    public func isMet(by s: GameState) -> Bool {
        let st = s.stats
        switch self {
        case .firstDelivery: return st.totalAccepted >= 1
        case .hundredFiles: return st.totalDelivered >= 100
        case .thousandFiles: return st.totalDelivered >= 1000
        case .streak25: return st.bestAcceptedStreak >= 25
        case .streak100: return st.bestAcceptedStreak >= 100
        case .cleanContract: return st.cleanContracts >= 1
        case .fiveCleanContracts: return st.cleanContracts >= 5
        case .firstQuarantine: return st.totalQuarantined >= 1
        case .firstUpgrade: return st.upgradesBought >= 1
        case .secondSite: return s.unlockedLocations.count >= 2
        case .allSites: return s.unlockedLocations.count >= LocationKind.allCases.count
        case .campaign: return st.campaignsCompleted >= 1
        }
    }
}

public extension GameState {
    /// Koşulu sağlanmış, henüz alınmamış başarımları alır, ödüllerini uygular ve döner.
    mutating func claimAchievements() -> [Achievement] {
        var claimed: [Achievement] = []
        for a in Achievement.allCases where !achievements.contains(a) && a.isMet(by: self) {
            achievements.insert(a)
            money += a.rewardMoney
            stats.totalEarned += a.rewardMoney
            xp += a.rewardXP
            claimed.append(a)
        }
        return claimed
    }
}

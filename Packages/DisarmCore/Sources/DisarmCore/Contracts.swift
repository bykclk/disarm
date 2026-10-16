import Foundation

public enum CustomerKind: String, Codable, CaseIterable, Sendable {
    case accounting, lawFirm, designAgency, softwareHouse, hospital, bank, government, forensicsLab

    public var displayName: String {
        switch self {
        case .accounting: L("Accounting")
        case .lawFirm: L("Law Firm")
        case .designAgency: L("Design Agency")
        case .softwareHouse: L("Software House")
        case .hospital: L("Hospital")
        case .bank: L("Bank")
        case .government: L("Government Agency")
        case .forensicsLab: L("Forensics Lab")
        }
    }
}

public enum PolicyRule: String, Codable, Sendable {
    case mustRemove, mustKeep, dontCare

    public var displayName: String {
        switch self {
        case .mustRemove: L("must be removed")
        case .mustKeep: L("must be kept")
        case .dontCare: L("doesn't matter")
        }
    }
}

public struct Policy: Codable, Hashable, Sendable {
    public var rules: [PartKind: PolicyRule]
    public var minImageQuality: Double
    /// Müşteri şifreli (açılamayan) dosyayı kabul etmez: doğrulanamayan içerik teslim edilemez.
    public var rejectsEncrypted: Bool

    public init(rules: [PartKind: PolicyRule], minImageQuality: Double, rejectsEncrypted: Bool = false) {
        self.rules = rules
        self.minImageQuality = minImageQuality
        self.rejectsEncrypted = rejectsEncrypted
    }

    public func rule(for kind: PartKind) -> PolicyRule { rules[kind] ?? .dontCare }

    public static func forCustomer(_ c: CustomerKind) -> Policy {
        switch c {
        case .accounting:
            Policy(rules: [.formula: .mustKeep, .text: .mustKeep, .macro: .mustRemove, .script: .mustRemove], minImageQuality: 0.3)
        case .lawFirm:
            Policy(rules: [.text: .mustKeep, .macro: .mustRemove, .script: .mustRemove, .embeddedFile: .dontCare], minImageQuality: 0.4)
        case .designAgency:
            Policy(rules: [.image: .mustKeep, .script: .mustRemove, .macro: .mustRemove], minImageQuality: 0.85)
        case .softwareHouse:
            // Betikler kaynak koddur: silinirse müşteri ödemez. Yalnızca zararlı olanlar gitmeli (tarayıcı işi).
            Policy(rules: [.script: .mustKeep, .text: .mustKeep, .macro: .mustRemove], minImageQuality: 0.0)
        case .hospital:
            // Tıbbi görüntü bozulamaz; görüntülere saklanan hasta verisi ve ekler gitmeli.
            Policy(rules: [.image: .mustKeep, .text: .mustKeep, .hiddenData: .mustRemove, .embeddedFile: .mustRemove, .macro: .mustRemove, .script: .mustRemove], minImageQuality: 0.9)
        case .bank:
            Policy(rules: [.macro: .mustRemove, .script: .mustRemove, .embeddedFile: .mustRemove, .hiddenData: .mustRemove, .unknown: .mustRemove], minImageQuality: 0.0, rejectsEncrypted: true)
        case .government:
            Policy(rules: [.macro: .mustRemove, .script: .mustRemove, .embeddedFile: .mustRemove, .hiddenData: .mustRemove, .unknown: .mustRemove, .text: .mustKeep], minImageQuality: 0.0, rejectsEncrypted: true)
        case .forensicsLab:
            // Delil bozulamaz: dönüştürücünün her geçişi (en iyi %95) kaliteyi düşürür; yalnızca kum havuzu işe yarar.
            Policy(rules: [.image: .mustKeep, .formula: .mustKeep, .text: .mustKeep, .macro: .mustRemove, .script: .mustRemove, .unknown: .mustRemove], minImageQuality: 0.97)
        }
    }
}

public struct ContractSpec: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var customer: CustomerKind
    public var title: String
    public var brief: String
    public var policy: Policy
    /// Tehdit seviyesi: 0 temiz, 1 makro, 2 betik, 3 iç içe ZIP, 4 polyglot+gizli veri, 5 bilinmeyen (ve üç kat iç içe), 6 şifreli arşiv.
    public var tier: Int
    public var targetFiles: Int
    public var maxBreaches: Int
    public var payPerFile: Int
    public var completionBonus: Int
    public var reputationReward: Int
    public var containerWeights: [ContainerKind: Double]
    public var filesPerMinute: Double

    public static let maxTier = 6

    public init(id: String, customer: CustomerKind, title: String, brief: String, tier: Int, targetFiles: Int, maxBreaches: Int, payPerFile: Int, completionBonus: Int, reputationReward: Int, containerWeights: [ContainerKind: Double], filesPerMinute: Double, policy: Policy? = nil) {
        self.id = id
        self.customer = customer
        self.title = title
        self.brief = brief
        self.policy = policy ?? Policy.forCustomer(customer)
        self.tier = tier
        self.targetFiles = targetFiles
        self.maxBreaches = maxBreaches
        self.payPerFile = payPerFile
        self.completionBonus = completionBonus
        self.reputationReward = reputationReward
        self.containerWeights = containerWeights
        self.filesPerMinute = filesPerMinute
    }
}

public struct ContractProgress: Codable, Hashable, Sendable {
    public var index: Int
    public var delivered: Int
    public var accepted: Int
    public var breaches: Int
    public var complaints: Int
    public var completions: Int
    /// Bu sözleşme turundaki şikayet nedenleri ve sayıları; oyuncunun "neden ödemiyorlar" sorusuna cevap.
    public var complaintReasons: [ComplaintReason: Int]
    /// İhlallerde teslim edilen zararlı parça türleri ve sayıları; "ne kaçtı" sorusuna cevap.
    public var breachReasons: [PartKind: Int]

    public init(index: Int = 0) {
        self.index = index
        delivered = 0
        accepted = 0
        breaches = 0
        complaints = 0
        completions = 0
        complaintReasons = [:]
        breachReasons = [:]
    }

    public mutating func resetCounters() {
        delivered = 0
        accepted = 0
        breaches = 0
        complaints = 0
        complaintReasons = [:]
        breachReasons = [:]
    }

    /// Nedenler, en sık olandan başlayarak.
    public var sortedComplaintReasons: [(reason: ComplaintReason, count: Int)] {
        complaintReasons.map { (reason: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.reason.displayName < $1.reason.displayName }
    }

    public var sortedBreachReasons: [(kind: PartKind, count: Int)] {
        breachReasons.map { (kind: $0.key, count: $0.value) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.kind.displayName < $1.kind.displayName }
    }
}

/// Şikayetin normalleştirilmiş nedeni (sayım ve kısa etiket için).
public enum ComplaintReason: Hashable, Codable, Sendable {
    case deliveredOpen
    case encrypted
    case left(PartKind)
    case lost(PartKind)
    case lowImageQuality

    public var displayName: String {
        switch self {
        case .deliveredOpen: L("Delivered open")
        case .encrypted: L("Encrypted file")
        case .left(let k): L("\(k.displayName) left in file")
        case .lost(let k): L("\(k.displayName) lost")
        case .lowImageQuality: L("Image quality too low")
        }
    }
}

public enum DeliveryIssue: Equatable, Hashable, Sendable {
    case breach([PartKind])
    case deliveredOpen
    case encryptedRejected
    case mustRemoveLeft(PartKind)
    case mustKeepLost(PartKind)
    case lowImageQuality(actual: Int, minimum: Int)

    public var text: String {
        switch self {
        case .breach(let kinds):
            let names = kinds.map(\.displayName).joined(separator: ", ")
            return L("BREACH: malicious content delivered (\(names))")
        case .deliveredOpen:
            return L("Delivered unpackaged (open); the customer couldn't open it")
        case .encryptedRejected:
            return L("Encrypted file delivered; the customer refuses anything that couldn't be inspected")
        case .mustRemoveLeft(let k):
            return L("\(k.displayName) should have been removed but stayed in the file")
        case .mustKeepLost(let k):
            return L("\(k.displayName) should have been kept but was lost")
        case .lowImageQuality(let a, let m):
            return L("Image quality too low (\("\(a)%"), customer requires at least \("\(m)%"))")
        }
    }

    /// Şikayet nedeni; ihlal için nil (ihlal ayrı sayılır).
    public var reason: ComplaintReason? {
        switch self {
        case .breach: nil
        case .deliveredOpen: .deliveredOpen
        case .encryptedRejected: .encrypted
        case .mustRemoveLeft(let k): .left(k)
        case .mustKeepLost(let k): .lost(k)
        case .lowImageQuality: .lowImageQuality
        }
    }

    /// Sahnede uçan kısa etiket.
    public var shortText: String {
        switch self {
        case .breach(let kinds): L("BREACH: \(Set(kinds).map(\.displayName).sorted().joined(separator: ", "))")
        case .lowImageQuality(let a, let m): L("Image \("\(a)%") < \("\(m)%")")
        default: reason?.displayName ?? ""
        }
    }
}

public struct DeliveryOutcome: Equatable, Sendable {
    public var pay: Int
    public var breach: Bool
    public var usability: Double
    public var issues: [DeliveryIssue]
    public var reputationDelta: Int

    public var accepted: Bool { !breach && usability >= 0.9 }
}

public enum DeliveryEvaluator {
    public static func evaluate(_ file: FileItem, policy: Policy, payPerFile: Int) -> DeliveryOutcome {
        if file.hasMalicious {
            let kinds = file.parts.filter(\.malicious).map(\.kind)
            return DeliveryOutcome(pay: -payPerFile * 3, breach: true, usability: 0,
                                   issues: [.breach(kinds)], reputationDelta: -4)
        }
        var usability = 1.0
        var issues: [DeliveryIssue] = []

        if file.isOpen {
            usability = 0
            issues.append(.deliveredOpen)
        }
        if file.encrypted && policy.rejectsEncrypted {
            usability = 0
            issues.append(.encryptedRejected)
        }
        for kind in PartKind.allCases {
            switch policy.rule(for: kind) {
            case .mustRemove:
                if file.kinds.contains(kind) {
                    usability -= 0.35
                    issues.append(.mustRemoveLeft(kind))
                }
            case .mustKeep:
                if file.originalKinds.contains(kind) && !file.kinds.contains(kind) {
                    usability -= 0.4
                    issues.append(.mustKeepLost(kind))
                }
            case .dontCare:
                break
            }
        }
        if file.hasImage && file.imageQuality < policy.minImageQuality {
            // Şartın altı her zaman şikayettir (en az %15); açık büyüdükçe ceza artar.
            let gap = policy.minImageQuality - file.imageQuality
            usability -= max(0.15, min(0.5, gap * 1.2))
            issues.append(.lowImageQuality(actual: Int(file.imageQuality * 100), minimum: Int(policy.minImageQuality * 100)))
        }
        usability = max(0, min(1, usability))
        let pay = Int((Double(payPerFile) * usability).rounded())
        let rep = usability >= 0.9 ? 1 : (usability < 0.5 ? -1 : 0)
        return DeliveryOutcome(pay: pay, breach: false, usability: usability, issues: issues, reputationDelta: rep)
    }
}

/// Sözleşme ve tehdit seviyesine göre dosya üretir.
public enum FileGenerator {
    /// Seviye 6'da dosyaların şifreli gelme olasılığı; şifrelilerin yarısı zararlı yük taşır.
    public static let encryptedChance = 0.3
    public static let encryptedMaliciousChance = 0.5

    public static func make(for spec: ContractSpec, rng: inout SplitMix64) -> FileItem {
        let container = pick(spec.containerWeights, rng: &rng)
        var parts: [Part] = []
        let tier = spec.tier

        // Zararsız temel içerik.
        switch container {
        case .pdf:
            parts.append(Part(kind: .text))
            if rng.chance(0.6) { parts.append(Part(kind: .image)) }
        case .docx:
            parts.append(Part(kind: .text))
            if rng.chance(0.4) { parts.append(Part(kind: .image)) }
            if rng.chance(0.25) { parts.append(Part(kind: .macro)) } // zararsız makro
        case .xlsx:
            parts.append(Part(kind: .formula))
            if rng.chance(0.5) { parts.append(Part(kind: .text)) }
            if rng.chance(0.35) { parts.append(Part(kind: .macro)) }
        case .png:
            parts.append(Part(kind: .image))
        case .zip:
            parts.append(Part(kind: .embeddedFile))
            if rng.chance(0.5) { parts.append(Part(kind: .text, depth: 1)) }
            if rng.chance(0.4) { parts.append(Part(kind: .image, depth: 1)) }
        }

        // Yazılım evi: zararsız betikler (kaynak kod) sık gelir; filtreyle silmek müşteriyi kızdırır.
        if spec.customer == .softwareHouse && container != .png && rng.chance(0.6) {
            parts.append(Part(kind: .script))
        }

        // Seviye 6: şifreli arşiv. Parola olmadan açılamaz, tarayıcı içini göremez.
        // Yarısı zararlı yük taşır; diğer yarısı zararsızdır, karantinaya atmak para kaybettirir.
        if tier >= 6 && container != .png && rng.chance(encryptedChance) {
            if rng.chance(encryptedMaliciousChance) {
                parts.append(Part(kind: rng.chance(0.5) ? .script : .macro, malicious: true))
            }
            var file = FileItem(container: container, parts: parts, tier: tier)
            file.encrypted = true
            return file
        }

        var polyglot = false
        let threatChance = tier == 0 ? 0.0 : 0.35 + 0.05 * Double(tier)
        if rng.chance(threatChance) {
            // Mevcut seviyeye kadar olan tehditlerden biri; en yeni tehdit daha olası.
            let maxT = min(tier, 5)
            let weights = (1...maxT).map { t in t == maxT ? 2.0 : 1.0 }
            let chosen = weightedIndex(weights, rng: &rng) + 1
            switch chosen {
            case 1:
                parts.append(Part(kind: .macro, malicious: true))
            case 2:
                parts.append(Part(kind: .script, malicious: true))
            case 3:
                // İç içe: üst seviyede gömülü dosya, bir kat içeride zararlı yük.
                // Seviye 5+: bazen üç kat (derinlik 2); ancak seviye 3 ayrıştırıcı görür.
                if !parts.contains(where: { $0.kind == .embeddedFile }) { parts.append(Part(kind: .embeddedFile)) }
                let depth = tier >= 5 && rng.chance(0.4) ? 2 : 1
                if depth == 2 { parts.append(Part(kind: .embeddedFile, depth: 1)) }
                parts.append(Part(kind: rng.chance(0.5) ? .macro : .script, depth: depth, malicious: true))
            case 4:
                if container == .pdf || container == .png {
                    polyglot = true
                    parts.append(Part(kind: .script, depth: 1, malicious: true))
                } else {
                    if !parts.contains(where: { $0.kind == .image }) { parts.append(Part(kind: .image)) }
                    parts.append(Part(kind: .hiddenData, malicious: true))
                }
            default:
                parts.append(Part(kind: .unknown, depth: 0, malicious: true, signatureKnown: false))
            }
        }
        // Zararsız gömülü dosyalar: bankanın yine de istemediği içerik.
        if tier >= 2 && container != .zip && rng.chance(0.2) {
            parts.append(Part(kind: .embeddedFile))
        }
        // Hastane: görüntülerde zararsız ama silinmesi gereken hasta verisi (meta veri).
        if spec.customer == .hospital && parts.contains(where: { $0.kind == .image }) && rng.chance(0.5) {
            parts.append(Part(kind: .hiddenData))
        }
        return FileItem(container: container, parts: parts, polyglot: polyglot, tier: tier)
    }

    static func pick(_ weights: [ContainerKind: Double], rng: inout SplitMix64) -> ContainerKind {
        let entries = ContainerKind.allCases.compactMap { k -> (ContainerKind, Double)? in
            guard let w = weights[k], w > 0 else { return nil }
            return (k, w)
        }
        guard !entries.isEmpty else { return .pdf }
        let i = weightedIndex(entries.map(\.1), rng: &rng)
        return entries[i].0
    }

    static func weightedIndex(_ weights: [Double], rng: inout SplitMix64) -> Int {
        let total = weights.reduce(0, +)
        var r = Double.random(in: 0..<total, using: &rng)
        for (i, w) in weights.enumerated() {
            r -= w
            if r < 0 { return i }
        }
        return weights.count - 1
    }
}

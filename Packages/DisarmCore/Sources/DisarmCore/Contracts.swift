import Foundation

public enum CustomerKind: String, Codable, CaseIterable, Sendable {
    case accounting, lawFirm, designAgency, bank, government

    public var displayName: String {
        switch self {
        case .accounting: "Muhasebe"
        case .lawFirm: "Hukuk Bürosu"
        case .designAgency: "Tasarım Ajansı"
        case .bank: "Banka"
        case .government: "Kamu Kurumu"
        }
    }
}

public enum PolicyRule: String, Codable, Sendable {
    case mustRemove, mustKeep, dontCare

    public var displayName: String {
        switch self {
        case .mustRemove: "silinsin"
        case .mustKeep: "korunsun"
        case .dontCare: "fark etmez"
        }
    }
}

public struct Policy: Codable, Hashable, Sendable {
    public var rules: [PartKind: PolicyRule]
    public var minImageQuality: Double

    public init(rules: [PartKind: PolicyRule], minImageQuality: Double) {
        self.rules = rules
        self.minImageQuality = minImageQuality
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
        case .bank:
            Policy(rules: [.macro: .mustRemove, .script: .mustRemove, .embeddedFile: .mustRemove, .hiddenData: .mustRemove, .unknown: .mustRemove], minImageQuality: 0.0)
        case .government:
            Policy(rules: [.macro: .mustRemove, .script: .mustRemove, .embeddedFile: .mustRemove, .hiddenData: .mustRemove, .unknown: .mustRemove, .text: .mustKeep], minImageQuality: 0.0)
        }
    }
}

public struct ContractSpec: Codable, Hashable, Sendable, Identifiable {
    public var id: String
    public var customer: CustomerKind
    public var title: String
    public var brief: String
    public var policy: Policy
    /// Tehdit seviyesi: 0 temiz, 1 makro, 2 betik, 3 iç içe ZIP, 4 polyglot+gizli veri, 5 bilinmeyen.
    public var tier: Int
    public var targetFiles: Int
    public var maxBreaches: Int
    public var payPerFile: Int
    public var completionBonus: Int
    public var reputationReward: Int
    public var containerWeights: [ContainerKind: Double]
    public var filesPerMinute: Double

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

    public init(index: Int = 0) {
        self.index = index
        delivered = 0
        accepted = 0
        breaches = 0
        complaints = 0
        completions = 0
    }

    public mutating func resetCounters() {
        delivered = 0
        accepted = 0
        breaches = 0
        complaints = 0
    }
}

public struct DeliveryOutcome: Equatable, Sendable {
    public var pay: Int
    public var breach: Bool
    public var usability: Double
    public var issues: [String]
    public var reputationDelta: Int

    public var accepted: Bool { !breach && usability >= 0.9 }
}

public enum DeliveryEvaluator {
    public static func evaluate(_ file: FileItem, policy: Policy, payPerFile: Int) -> DeliveryOutcome {
        if file.hasMalicious {
            let names = file.parts.filter(\.malicious).map { $0.kind.displayName }
            return DeliveryOutcome(pay: -payPerFile * 3, breach: true, usability: 0,
                                   issues: ["İHLAL: zararlı içerik teslim edildi (\(names.joined(separator: ", ")))"],
                                   reputationDelta: -4)
        }
        var usability = 1.0
        var issues: [String] = []

        if file.isOpen {
            usability = 0
            issues.append("Dosya paketlenmeden (açık) teslim edildi; müşteri açamadı")
        }
        for kind in PartKind.allCases {
            switch policy.rule(for: kind) {
            case .mustRemove:
                if file.kinds.contains(kind) {
                    usability -= 0.35
                    issues.append("\(kind.displayName) silinmeliydi, dosyada kaldı")
                }
            case .mustKeep:
                if file.originalKinds.contains(kind) && !file.kinds.contains(kind) {
                    usability -= 0.4
                    issues.append("\(kind.displayName) korunmalıydı, kayboldu")
                }
            case .dontCare:
                break
            }
        }
        if file.hasImage && file.imageQuality < policy.minImageQuality {
            let gap = policy.minImageQuality - file.imageQuality
            usability -= min(0.5, gap * 1.2)
            issues.append("Görsel kalitesi düşük (%\(Int(file.imageQuality * 100)), istenen en az %\(Int(policy.minImageQuality * 100)))")
        }
        usability = max(0, min(1, usability))
        let pay = Int((Double(payPerFile) * usability).rounded())
        let rep = usability >= 0.9 ? 1 : (usability < 0.5 ? -1 : 0)
        return DeliveryOutcome(pay: pay, breach: false, usability: usability, issues: issues, reputationDelta: rep)
    }
}

/// Sözleşme ve tehdit seviyesine göre dosya üretir.
public enum FileGenerator {
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
                if !parts.contains(where: { $0.kind == .embeddedFile }) { parts.append(Part(kind: .embeddedFile)) }
                parts.append(Part(kind: rng.chance(0.5) ? .macro : .script, depth: 1, malicious: true))
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

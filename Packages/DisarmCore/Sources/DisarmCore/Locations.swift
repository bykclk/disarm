import Foundation

public enum LocationKind: String, Codable, CaseIterable, Sendable {
    case smallOffice, company, bank, government, dataCenter

    public var spec: LocationSpec { LocationCatalog.spec(for: self) }

    /// Kampanya sırasında bir sonraki mekân; son mekânda nil.
    public var next: LocationKind? {
        let all = Self.allCases
        guard let i = all.firstIndex(of: self), i + 1 < all.count else { return nil }
        return all[i + 1]
    }
}

public struct LocationSpec: Sendable {
    public var kind: LocationKind
    public var displayName: String
    public var description: String
    public var width: Int
    public var height: Int
    public var sourcePos: GridPos
    public var sourceFacing: Direction
    public var sinkPos: GridPos
    public var unlockCost: Int
    public var unlockReputation: Int
    public var airGapped: Bool
    public var availableModules: [ModuleKind]
    public var contracts: [ContractSpec]

    public func emptyGrid() -> Grid {
        var g = Grid(width: width, height: height)
        g[sourcePos] = .module(Module(kind: .source, facing: sourceFacing))
        g[sinkPos] = .module(Module(kind: .sink, facing: .down))
        return g
    }
}

public enum LocationCatalog {
    public static func spec(for kind: LocationKind) -> LocationSpec {
        switch kind {
        case .smallOffice:
            LocationSpec(
                kind: kind,
                displayName: L("Small Office"),
                description: L("A three-person team, one server, one belt. You start with neighborhood customers."),
                width: 7, height: 10,
                sourcePos: GridPos(0, 1), sourceFacing: .right,
                sinkPos: GridPos(6, 8),
                unlockCost: 0, unlockReputation: 0, airGapped: false,
                availableModules: [.scanner, .parser, .filter, .packager, .quarantine],
                contracts: officeContracts)
        case .company:
            LocationSpec(
                kind: kind,
                displayName: L("Company"),
                description: L("Bigger volume, more varied files. Router and transformer are now at your disposal."),
                width: 8, height: 12,
                sourcePos: GridPos(3, 0), sourceFacing: .down,
                sinkPos: GridPos(4, 11),
                unlockCost: 2500, unlockReputation: 20, airGapped: false,
                availableModules: [.scanner, .parser, .filter, .transformer, .packager, .router, .splitter, .quarantine],
                contracts: companyContracts)
        case .bank:
            LocationSpec(
                kind: kind,
                displayName: L("Bank"),
                description: L("No active content gets through. Threats without signatures show up here."),
                width: 9, height: 13,
                sourcePos: GridPos(0, 6), sourceFacing: .right,
                sinkPos: GridPos(8, 6),
                unlockCost: 9000, unlockReputation: 60, airGapped: false,
                availableModules: ModuleKind.allCases.filter { $0.isPlaceable && $0 != .sandbox },
                contracts: bankContracts)
        case .government:
            LocationSpec(
                kind: kind,
                displayName: L("Government Agency"),
                description: L("Air-gapped network: no signature updates. The scanner is blind; only disarming works."),
                width: 10, height: 14,
                sourcePos: GridPos(0, 0), sourceFacing: .down,
                sinkPos: GridPos(9, 13),
                unlockCost: 25000, unlockReputation: 120, airGapped: true,
                availableModules: ModuleKind.allCases.filter { $0.isPlaceable && $0 != .sandbox },
                contracts: governmentContracts)
        case .dataCenter:
            LocationSpec(
                kind: kind,
                displayName: L("Data Center"),
                description: L("Racks, redundant belts, the fastest flow in the game. The Sandbox detonates files in isolation: no signatures, no quality loss, but slow and pricey."),
                width: 11, height: 15,
                sourcePos: GridPos(5, 0), sourceFacing: .down,
                sinkPos: GridPos(5, 14),
                unlockCost: 60000, unlockReputation: 220, airGapped: false,
                availableModules: ModuleKind.allCases.filter(\.isPlaceable),
                contracts: dataCenterContracts)
        }
    }

    static let officeContracts: [ContractSpec] = [
        ContractSpec(id: "office-1", customer: .accounting, title: L("Neighborhood Accountant"),
                     brief: L("Excel sheets arrive. Keep the formulas, remove the macros. Some macros are malicious, some aren't; the customer wants none of them."),
                     tier: 1, targetFiles: 20, maxBreaches: 3, payPerFile: 12, completionBonus: 200, reputationReward: 5,
                     containerWeights: [.xlsx: 5, .docx: 2, .pdf: 1], filesPerMinute: 10),
        ContractSpec(id: "office-2", customer: .lawFirm, title: L("Attorney's Office"),
                     brief: L("PDF contracts. Embedded scripts have started showing up inside them. Keep the text, drop the active content."),
                     tier: 2, targetFiles: 30, maxBreaches: 3, payPerFile: 16, completionBonus: 400, reputationReward: 8,
                     containerWeights: [.pdf: 5, .docx: 3], filesPerMinute: 12),
        ContractSpec(id: "office-3", customer: .designAgency, title: L("Ad Agency"),
                     brief: L("Image-heavy files. If quality drops they stop paying. Scripts still have to go."),
                     tier: 2, targetFiles: 40, maxBreaches: 3, payPerFile: 20, completionBonus: 600, reputationReward: 10,
                     containerWeights: [.png: 4, .pdf: 3, .docx: 1], filesPerMinute: 14),
        ContractSpec(id: "office-4", customer: .softwareHouse, title: L("Software House"),
                     brief: L("Their scripts are source code: delete them and they won't pay. Only the malicious ones must go, and those carry known signatures. Macros are still unwelcome."),
                     tier: 2, targetFiles: 40, maxBreaches: 3, payPerFile: 22, completionBonus: 700, reputationReward: 12,
                     containerWeights: [.docx: 4, .pdf: 3, .zip: 2], filesPerMinute: 14),
    ]

    static let companyContracts: [ContractSpec] = [
        ContractSpec(id: "company-1", customer: .accounting, title: L("Holding Accounting"),
                     brief: L("ZIPs inside ZIP archives. The payload hides one layer down; a level 1 parser can't see it."),
                     tier: 3, targetFiles: 30, maxBreaches: 3, payPerFile: 24, completionBonus: 800, reputationReward: 12,
                     containerWeights: [.zip: 4, .xlsx: 4, .docx: 2], filesPerMinute: 16),
        ContractSpec(id: "company-2", customer: .designAgency, title: L("Publishing House"),
                     brief: L("Image quality must stay above 85%, yet hidden data is being stashed inside the images. You'll need to upgrade the transformer."),
                     tier: 4, targetFiles: 35, maxBreaches: 3, payPerFile: 30, completionBonus: 1200, reputationReward: 15,
                     containerWeights: [.png: 5, .pdf: 4, .zip: 1], filesPerMinute: 18),
        ContractSpec(id: "company-3", customer: .lawFirm, title: L("International Law"),
                     brief: L("Polyglot files: both PDF and ZIP. Without a level 3 parser the second identity stays invisible."),
                     tier: 4, targetFiles: 40, maxBreaches: 2, payPerFile: 34, completionBonus: 1500, reputationReward: 18,
                     containerWeights: [.pdf: 5, .zip: 3, .docx: 2], filesPerMinute: 20),
        ContractSpec(id: "company-4", customer: .hospital, title: L("University Hospital"),
                     brief: L("Medical images must stay above 90% quality, yet patient data is tucked into the image metadata and must be stripped. Only a level 3 transformer is gentle enough."),
                     tier: 4, targetFiles: 40, maxBreaches: 2, payPerFile: 38, completionBonus: 1800, reputationReward: 20,
                     containerWeights: [.png: 5, .pdf: 4, .docx: 2], filesPerMinute: 20),
    ]

    static let bankContracts: [ContractSpec] = [
        ContractSpec(id: "bank-1", customer: .bank, title: L("Regional Bank"),
                     brief: L("Zero active content. Even harmless macros, scripts and embedded files must not be delivered. Looks may suffer; that's fine."),
                     tier: 4, targetFiles: 40, maxBreaches: 2, payPerFile: 45, completionBonus: 2500, reputationReward: 20,
                     containerWeights: [.pdf: 4, .xlsx: 3, .docx: 3, .zip: 2], filesPerMinute: 22),
        ContractSpec(id: "bank-2", customer: .bank, title: L("Investment Bank"),
                     brief: L("Threats with no signature have arrived, and some archives now nest three layers deep. The scanner can't see them; only a level 3 parser and the transformer get through."),
                     tier: 5, targetFiles: 50, maxBreaches: 2, payPerFile: 60, completionBonus: 4000, reputationReward: 30,
                     containerWeights: [.pdf: 4, .xlsx: 3, .docx: 3, .zip: 2, .png: 2], filesPerMinute: 24),
        ContractSpec(id: "bank-3", customer: .bank, title: L("Private Banking"),
                     brief: L("Password-protected archives. Nothing can open or inspect them, and the bank refuses anything unverified. Set a router to divert encrypted files into quarantine; the harmless ones are lost income, the others would be a breach."),
                     tier: 6, targetFiles: 60, maxBreaches: 1, payPerFile: 75, completionBonus: 6000, reputationReward: 35,
                     containerWeights: [.pdf: 4, .xlsx: 3, .docx: 3, .zip: 4, .png: 1], filesPerMinute: 26),
    ]

    static let governmentContracts: [ContractSpec] = [
        ContractSpec(id: "gov-1", customer: .government, title: L("Ministry Document Flow"),
                     brief: L("Air-gapped network. No signature updates; the scanner only recognizes ancient macros. Everything has to be solved by disarming."),
                     tier: 5, targetFiles: 60, maxBreaches: 1, payPerFile: 80, completionBonus: 8000, reputationReward: 40,
                     containerWeights: [.pdf: 5, .docx: 4, .xlsx: 3, .zip: 3, .png: 2], filesPerMinute: 26),
        ContractSpec(id: "gov-2", customer: .government, title: L("National Archive"),
                     brief: L("Heavy flow, deep archives, no signatures. Hold the line until the next client calls."),
                     tier: 5, targetFiles: 100, maxBreaches: 1, payPerFile: 100, completionBonus: 15000, reputationReward: 60,
                     containerWeights: [.pdf: 5, .docx: 4, .xlsx: 3, .zip: 4, .png: 3], filesPerMinute: 30),
        ContractSpec(id: "gov-3", customer: .government, title: L("Intelligence Service"),
                     brief: L("Encrypted dispatches on an air-gapped network. The scanner is blind, the parser is locked out; route encrypted files to quarantine and disarm the rest. Endless flow. How long can you hold out?"),
                     tier: 6, targetFiles: 120, maxBreaches: 1, payPerFile: 120, completionBonus: 25000, reputationReward: 80,
                     containerWeights: [.pdf: 5, .docx: 4, .xlsx: 3, .zip: 5, .png: 2], filesPerMinute: 32),
    ]

    static let dataCenterContracts: [ContractSpec] = [
        ContractSpec(id: "dc-1", customer: .designAgency, title: L("Streaming Studio"),
                     brief: L("Frame-perfect images and unsigned threats at thirty files a minute. A level 3 transformer keeps 95%; the Sandbox keeps 100% but takes its time. Build wide."),
                     tier: 5, targetFiles: 60, maxBreaches: 2, payPerFile: 90, completionBonus: 10000, reputationReward: 45,
                     containerWeights: [.png: 5, .pdf: 3, .zip: 2, .docx: 1], filesPerMinute: 36),
        ContractSpec(id: "dc-2", customer: .forensicsLab, title: L("Forensics Lab"),
                     brief: L("Evidence must stay untouched: images above 97%, formulas intact. The transformer is out of the question; only the Sandbox detonates unsigned payloads without altering the file. Harmless macros still need the filter."),
                     tier: 5, targetFiles: 70, maxBreaches: 1, payPerFile: 110, completionBonus: 15000, reputationReward: 55,
                     containerWeights: [.pdf: 4, .docx: 3, .xlsx: 3, .png: 3, .zip: 2], filesPerMinute: 40),
        ContractSpec(id: "dc-3", customer: .bank, title: L("Hyperscale Exchange"),
                     brief: L("The whole stack at once: encrypted archives, unsigned payloads, three-deep nesting, more files than any single line can swallow. Split the flow. The campaign ends here; the flow doesn't."),
                     tier: 6, targetFiles: 150, maxBreaches: 1, payPerFile: 140, completionBonus: 40000, reputationReward: 100,
                     containerWeights: [.pdf: 4, .docx: 3, .xlsx: 3, .zip: 5, .png: 2], filesPerMinute: 60),
    ]
}

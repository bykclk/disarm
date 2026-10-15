import Foundation

public enum LocationKind: String, Codable, CaseIterable, Sendable {
    case smallOffice, company, bank, government

    public var spec: LocationSpec { LocationCatalog.spec(for: self) }
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
                displayName: "Küçük Ofis",
                description: "Üç kişilik bir ekip, bir sunucu, bir bant. Mahalle müşterileriyle başlıyorsun.",
                width: 7, height: 10,
                sourcePos: GridPos(0, 1), sourceFacing: .right,
                sinkPos: GridPos(6, 8),
                unlockCost: 0, unlockReputation: 0, airGapped: false,
                availableModules: [.scanner, .parser, .filter, .packager, .quarantine],
                contracts: officeContracts)
        case .company:
            LocationSpec(
                kind: kind,
                displayName: "Şirket",
                description: "Daha büyük hacim, daha çeşitli dosyalar. Yönlendirici ve dönüştürücü artık emrinde.",
                width: 8, height: 12,
                sourcePos: GridPos(3, 0), sourceFacing: .down,
                sinkPos: GridPos(4, 11),
                unlockCost: 2500, unlockReputation: 20, airGapped: false,
                availableModules: [.scanner, .parser, .filter, .transformer, .packager, .router, .quarantine],
                contracts: companyContracts)
        case .bank:
            LocationSpec(
                kind: kind,
                displayName: "Banka",
                description: "Hiçbir aktif içerik geçmeyecek. İmzası olmayan tehditler burada ortaya çıkar.",
                width: 9, height: 13,
                sourcePos: GridPos(0, 6), sourceFacing: .right,
                sinkPos: GridPos(8, 6),
                unlockCost: 9000, unlockReputation: 60, airGapped: false,
                availableModules: ModuleKind.allCases.filter(\.isPlaceable),
                contracts: bankContracts)
        case .government:
            LocationSpec(
                kind: kind,
                displayName: "Kamu Kurumu",
                description: "Air-gapped ağ: imza güncellemesi yok. Tarayıcı kör, sadece disarm işe yarar.",
                width: 10, height: 14,
                sourcePos: GridPos(0, 0), sourceFacing: .down,
                sinkPos: GridPos(9, 13),
                unlockCost: 25000, unlockReputation: 120, airGapped: true,
                availableModules: ModuleKind.allCases.filter(\.isPlaceable),
                contracts: governmentContracts)
        }
    }

    static let officeContracts: [ContractSpec] = [
        ContractSpec(id: "office-1", customer: .accounting, title: "Mahalle Muhasebecisi",
                     brief: "Excel tabloları gelir. Formüller korunsun, makrolar silinsin. Bazı makrolar zararlı, bazıları değil; ama müşteri hiçbirini istemiyor.",
                     tier: 1, targetFiles: 15, maxBreaches: 3, payPerFile: 12, completionBonus: 150, reputationReward: 5,
                     containerWeights: [.xlsx: 5, .docx: 2, .pdf: 1], filesPerMinute: 10),
        ContractSpec(id: "office-2", customer: .lawFirm, title: "Avukatlık Bürosu",
                     brief: "PDF sözleşmeler. İçlerine gömülü betikler görülmeye başladı. Metin korunsun, aktif içerik gitsin.",
                     tier: 2, targetFiles: 25, maxBreaches: 3, payPerFile: 16, completionBonus: 300, reputationReward: 8,
                     containerWeights: [.pdf: 5, .docx: 3], filesPerMinute: 12),
        ContractSpec(id: "office-3", customer: .designAgency, title: "Reklam Ajansı",
                     brief: "Görsel ağırlıklı dosyalar. Kalite düşerse ödemeyi keserler. Betikler yine de temizlenmeli.",
                     tier: 2, targetFiles: 30, maxBreaches: 3, payPerFile: 20, completionBonus: 500, reputationReward: 10,
                     containerWeights: [.png: 4, .pdf: 3, .docx: 1], filesPerMinute: 14),
    ]

    static let companyContracts: [ContractSpec] = [
        ContractSpec(id: "company-1", customer: .accounting, title: "Holding Muhasebesi",
                     brief: "ZIP arşivleri içinde ZIP'ler. Yük bir kat içeride saklanıyor; seviye 1 ayrıştırıcı göremez.",
                     tier: 3, targetFiles: 30, maxBreaches: 3, payPerFile: 24, completionBonus: 800, reputationReward: 12,
                     containerWeights: [.zip: 4, .xlsx: 4, .docx: 2], filesPerMinute: 16),
        ContractSpec(id: "company-2", customer: .designAgency, title: "Yayınevi",
                     brief: "Görsel kalitesi %85'in altına düşmemeli ama görsellerin içine gizli veri saklanıyor. Dönüştürücüyü yükseltmen gerekecek.",
                     tier: 4, targetFiles: 35, maxBreaches: 3, payPerFile: 30, completionBonus: 1200, reputationReward: 15,
                     containerWeights: [.png: 5, .pdf: 4, .zip: 1], filesPerMinute: 18),
        ContractSpec(id: "company-3", customer: .lawFirm, title: "Uluslararası Hukuk",
                     brief: "Polyglot dosyalar: hem PDF hem ZIP. Ayrıştırıcı seviye 3 olmadan ikinci kimlik görünmez.",
                     tier: 4, targetFiles: 40, maxBreaches: 2, payPerFile: 34, completionBonus: 1500, reputationReward: 18,
                     containerWeights: [.pdf: 5, .zip: 3, .docx: 2], filesPerMinute: 20),
    ]

    static let bankContracts: [ContractSpec] = [
        ContractSpec(id: "bank-1", customer: .bank, title: "Bölge Bankası",
                     brief: "Sıfır aktif içerik. Zararsız bile olsa makro, betik, gömülü dosya teslim edilmeyecek. Görünüm bozulsa da olur.",
                     tier: 4, targetFiles: 40, maxBreaches: 2, payPerFile: 45, completionBonus: 2500, reputationReward: 20,
                     containerWeights: [.pdf: 4, .xlsx: 3, .docx: 3, .zip: 2], filesPerMinute: 22),
        ContractSpec(id: "bank-2", customer: .bank, title: "Yatırım Bankası",
                     brief: "İmzası olmayan tehditler geldi. Tarayıcı bunları göremez; yalnızca dönüştürücü yok eder.",
                     tier: 5, targetFiles: 50, maxBreaches: 2, payPerFile: 60, completionBonus: 4000, reputationReward: 30,
                     containerWeights: [.pdf: 4, .xlsx: 3, .docx: 3, .zip: 2, .png: 2], filesPerMinute: 24),
    ]

    static let governmentContracts: [ContractSpec] = [
        ContractSpec(id: "gov-1", customer: .government, title: "Bakanlık Evrak Akışı",
                     brief: "Air-gapped ağ. İmza güncellemesi yok, tarayıcı yalnızca yıllanmış makroları tanır. Her şey disarm ile çözülecek.",
                     tier: 5, targetFiles: 60, maxBreaches: 1, payPerFile: 80, completionBonus: 8000, reputationReward: 40,
                     containerWeights: [.pdf: 5, .docx: 4, .xlsx: 3, .zip: 3, .png: 2], filesPerMinute: 26),
        ContractSpec(id: "gov-2", customer: .government, title: "Ulusal Arşiv",
                     brief: "Sonsuz akış. Ne kadar dayanabilirsin?",
                     tier: 5, targetFiles: 100, maxBreaches: 1, payPerFile: 100, completionBonus: 15000, reputationReward: 60,
                     containerWeights: [.pdf: 5, .docx: 4, .xlsx: 3, .zip: 4, .png: 3], filesPerMinute: 30),
    ]
}

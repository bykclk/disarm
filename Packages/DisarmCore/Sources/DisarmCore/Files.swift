import Foundation

/// Dosya kabı: dışarıdan görünen format.
public enum ContainerKind: String, Codable, CaseIterable, Sendable {
    case pdf, docx, xlsx, png, zip

    public var displayName: String { rawValue.uppercased() }
}

/// Kabın içinde taşınan parça türleri.
public enum PartKind: String, Codable, CaseIterable, Sendable {
    case text, image, formula, macro, script, embeddedFile, hiddenData, unknown

    public var displayName: String {
        switch self {
        case .text: L("Text")
        case .image: L("Image")
        case .formula: L("Formula")
        case .macro: L("Macro")
        case .script: L("Script")
        case .embeddedFile: L("Embedded File")
        case .hiddenData: L("Hidden Data")
        case .unknown: L("Unknown")
        }
    }

    /// Aktif içerik: çalıştırılabilir ya da yük taşıyabilen parçalar.
    public var isActiveContent: Bool {
        switch self {
        case .macro, .script, .embeddedFile, .hiddenData, .unknown: true
        case .text, .image, .formula: false
        }
    }

    /// Filtre modülünün hedefleyebildiği türler.
    public static let filterable: [PartKind] = [.macro, .script, .embeddedFile]
}

public struct Part: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var kind: PartKind
    /// 0 = üst seviye, 1 = bir kat içeride (ZIP içinde ZIP), ...
    public var depth: Int
    public var malicious: Bool
    /// İmza tarayıcısının tanıdığı bir tehdit mi?
    public var signatureKnown: Bool

    public init(kind: PartKind, depth: Int = 0, malicious: Bool = false, signatureKnown: Bool = true, id: UUID = UUID()) {
        self.id = id
        self.kind = kind
        self.depth = depth
        self.malicious = malicious
        self.signatureKnown = signatureKnown
    }
}

public struct FileItem: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var container: ContainerKind
    public var parts: [Part]
    /// Ayrıştırıcıdan geçip açılmış mı? Açık dosya teslim edilirse kullanılamaz sayılır.
    public var isOpen: Bool
    /// Ayrıştırıcının görünür kıldığı en derin katman. Kapalıyken -1.
    public var exposedDepth: Int
    /// Hem PDF hem ZIP gibi iki kimlikli dosya. Derin katmanı ancak gelişmiş ayrıştırıcı görür.
    public var polyglot: Bool
    public var imageQuality: Double
    /// Üretildiği anda içerdiği parça türleri; L("must be kept") kuralı buna göre denetlenir.
    public var originalKinds: Set<PartKind>
    public var tier: Int

    public init(container: ContainerKind, parts: [Part], polyglot: Bool = false, tier: Int = 0, id: UUID = UUID()) {
        self.id = id
        self.container = container
        self.parts = parts
        self.isOpen = false
        self.exposedDepth = -1
        self.polyglot = polyglot
        self.imageQuality = 1.0
        self.originalKinds = Set(parts.map(\.kind))
        self.tier = tier
    }

    public func isExposed(_ part: Part) -> Bool {
        isOpen && part.depth <= exposedDepth
    }

    public var exposedParts: [Part] { parts.filter { isExposed($0) } }
    public var hasMalicious: Bool { parts.contains { $0.malicious } }
    public var maliciousCount: Int { parts.filter(\.malicious).count }
    public var hasImage: Bool { parts.contains { $0.kind == .image } }
    public var kinds: Set<PartKind> { Set(parts.map(\.kind)) }
}

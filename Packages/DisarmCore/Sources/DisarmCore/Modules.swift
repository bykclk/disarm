import Foundation

public enum ModuleKind: String, Codable, CaseIterable, Sendable {
    case source, sink, scanner, parser, filter, transformer, packager, router, quarantine

    public var displayName: String {
        switch self {
        case .source: "Giriş"
        case .sink: "Teslimat"
        case .scanner: "İmza Tarayıcı"
        case .parser: "Ayrıştırıcı"
        case .filter: "Filtre"
        case .transformer: "Dönüştürücü"
        case .packager: "Paketleyici"
        case .router: "Yönlendirici"
        case .quarantine: "Karantina"
        }
    }

    public var shortName: String {
        switch self {
        case .source: "GİR"
        case .sink: "TSL"
        case .scanner: "TAR"
        case .parser: "AYR"
        case .filter: "FLT"
        case .transformer: "DNŞ"
        case .packager: "PKT"
        case .router: "YÖN"
        case .quarantine: "KRN"
        }
    }

    public var blurb: String {
        switch self {
        case .source: "Müşteri dosyaları buradan bantta akmaya başlar."
        case .sink: "Dosyalar buradan müşteriye teslim edilir. Kapalı, temiz ve sözleşmeye uygun dosya para kazandırır."
        case .scanner: "Ucuz ve hızlı. Dosyayı açmadan bilinen imzalı tehditleri siler. Bilinmeyen tehditleri göremez; imzasız ağlarda işe yaramaz."
        case .parser: "Dosyayı parçalarına ayırır. Filtre ve dönüştürücü ancak açılmış dosyada çalışır. Seviye arttıkça iç içe katmanları ve polyglot dosyaları da açar."
        case .filter: "Seçilen parça türünü (makro, betik, gömülü dosya) atar. Zararlı olsun olmasın, hepsi gider."
        case .transformer: "Görselleri yeniden kodlar; gizli veriyi ve bilinmeyen yükleri yok eder. Düşük seviyede görsel kalitesini düşürür ve formülleri değere çevirir."
        case .packager: "Açık dosyayı yeniden paketler. Teslimat için şart."
        case .router: "Seçilen kap türündeki dosyaları sağ tarafa ayırır, diğerleri düz devam eder."
        case .quarantine: "Dosyayı yok eder. Para yok, ama ihlal de yok."
        }
    }

    public var isPlaceable: Bool { self != .source && self != .sink }

    public var baseCost: Int {
        switch self {
        case .source, .sink: 0
        case .scanner: 60
        case .parser: 120
        case .filter: 90
        case .transformer: 220
        case .packager: 100
        case .router: 150
        case .quarantine: 40
        }
    }

    /// Saniye cinsinden temel işlem süresi (seviye 1).
    public var baseProcessTime: Double {
        switch self {
        case .source: 0
        case .sink: 0.3
        case .scanner: 0.6
        case .parser: 1.6
        case .filter: 1.0
        case .transformer: 2.2
        case .packager: 1.2
        case .router: 0.3
        case .quarantine: 0.2
        }
    }

    public var maxLevel: Int {
        switch self {
        case .source, .sink, .quarantine, .router: 1
        case .parser, .transformer: 3
        case .scanner, .filter, .packager: 3
        }
    }

    public func upgradeCost(toLevel level: Int) -> Int {
        baseCost * 3 * (level - 1)
    }

    public func processTime(level: Int) -> Double {
        baseProcessTime / (1.0 + 0.5 * Double(max(0, level - 1)))
    }

    public var isConfigurable: Bool { self == .filter || self == .router }
}

public struct ModuleConfig: Codable, Hashable, Sendable {
    public var filterTarget: PartKind
    public var routeTarget: ContainerKind

    public init(filterTarget: PartKind = .macro, routeTarget: ContainerKind = .zip) {
        self.filterTarget = filterTarget
        self.routeTarget = routeTarget
    }
}

public struct Module: Codable, Hashable, Sendable {
    public var kind: ModuleKind
    public var facing: Direction
    public var config: ModuleConfig

    public init(kind: ModuleKind, facing: Direction, config: ModuleConfig = ModuleConfig()) {
        self.kind = kind
        self.facing = facing
        self.config = config
    }

    public var summary: String {
        switch kind {
        case .filter: "\(kind.displayName): \(config.filterTarget.displayName)"
        case .router: "\(kind.displayName): \(config.routeTarget.displayName)"
        default: kind.displayName
        }
    }
}

public enum ProcessNote: Equatable, Sendable {
    case removed(PartKind, count: Int)
    case opened(depth: Int)
    case polyglotUnhandled
    case closed
    case imageDegraded(Double)
    case formulasFlattened(Int)
    case noEffect(String)
}

/// Modüllerin bir dosyaya uyguladığı dönüşümler. Saf fonksiyon: test edilebilir.
public enum ModuleProcessor {
    public static func apply(_ module: Module, level: Int, airGapped: Bool, to file: inout FileItem) -> [ProcessNote] {
        switch module.kind {
        case .scanner:
            return scan(level: level, airGapped: airGapped, file: &file)
        case .parser:
            return parse(level: level, file: &file)
        case .filter:
            return filter(module.config.filterTarget, file: &file)
        case .transformer:
            return transform(level: level, file: &file)
        case .packager:
            let wasOpen = file.isOpen
            file.isOpen = false
            file.exposedDepth = -1
            return wasOpen ? [.closed] : [.noEffect("Dosya zaten kapalıydı")]
        case .source, .sink, .router, .quarantine:
            return []
        }
    }

    static func scan(level: Int, airGapped: Bool, file: inout FileItem) -> [ProcessNote] {
        // Tarayıcı kabı açmadan bakar: polyglot'un ikinci kimliğini görmez,
        // seviye 2+ bir kat içeri (ZIP içi) bakabilir.
        let visibleDepth = file.polyglot ? 0 : (level >= 2 ? 1 : 0)
        var removed: [PartKind: Int] = [:]
        file.parts.removeAll { p in
            guard p.malicious, p.signatureKnown, p.depth <= visibleDepth else { return false }
            // Air-gapped ortamda imzalar güncellenmez: sadece en eski tehdit (makro) tanınır.
            if airGapped && p.kind != .macro { return false }
            removed[p.kind, default: 0] += 1
            return true
        }
        if removed.isEmpty { return [.noEffect("İmza eşleşmedi")] }
        return removed.map { .removed($0.key, count: $0.value) }
    }

    static func parse(level: Int, file: inout FileItem) -> [ProcessNote] {
        file.isOpen = true
        if file.polyglot && level < 3 {
            file.exposedDepth = 0
            return [.opened(depth: 0), .polyglotUnhandled]
        }
        file.exposedDepth = level - 1
        return [.opened(depth: level - 1)]
    }

    static func filter(_ target: PartKind, file: inout FileItem) -> [ProcessNote] {
        guard file.isOpen else { return [.noEffect("Dosya kapalı; önce ayrıştır")] }
        let before = file.parts.count
        let depth = file.exposedDepth
        file.parts.removeAll { $0.kind == target && $0.depth <= depth }
        let n = before - file.parts.count
        return n > 0 ? [.removed(target, count: n)] : [.noEffect("\(target.displayName) bulunamadı")]
    }

    static func transform(level: Int, file: inout FileItem) -> [ProcessNote] {
        guard file.isOpen else { return [.noEffect("Dosya kapalı; önce ayrıştır")] }
        var notes: [ProcessNote] = []
        let depth = file.exposedDepth
        var removed: [PartKind: Int] = [:]
        file.parts.removeAll { p in
            guard p.depth <= depth, p.kind == .hiddenData || p.kind == .unknown else { return false }
            removed[p.kind, default: 0] += 1
            return true
        }
        notes += removed.map { .removed($0.key, count: $0.value) }

        if file.hasImage {
            let factor: Double = level >= 3 ? 0.95 : (level == 2 ? 0.8 : 0.6)
            file.imageQuality *= factor
            notes.append(.imageDegraded(factor))
        }
        if level == 1 {
            let before = file.parts.count
            file.parts.removeAll { $0.kind == .formula && $0.depth <= depth }
            let n = before - file.parts.count
            if n > 0 { notes.append(.formulasFlattened(n)) }
        }
        return notes.isEmpty ? [.noEffect("Dönüştürülecek bir şey yok")] : notes
    }
}

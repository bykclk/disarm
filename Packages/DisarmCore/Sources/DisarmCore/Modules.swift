import Foundation

public enum ModuleKind: String, Codable, CaseIterable, Sendable {
    case source, sink, scanner, parser, filter, transformer, packager, router, quarantine

    public var displayName: String {
        switch self {
        case .source: L("Intake")
        case .sink: L("Delivery")
        case .scanner: L("Signature Scanner")
        case .parser: L("Parser")
        case .filter: L("Filter")
        case .transformer: L("Transformer")
        case .packager: L("Packager")
        case .router: L("Router")
        case .quarantine: L("Quarantine")
        }
    }

    public var shortName: String {
        switch self {
        case .source: L("IN")
        case .sink: L("OUT")
        case .scanner: L("SCN")
        case .parser: L("PRS")
        case .filter: L("FLT")
        case .transformer: L("TRN")
        case .packager: L("PKG")
        case .router: L("RTR")
        case .quarantine: L("QRT")
        }
    }

    public var blurb: String {
        switch self {
        case .source: L("Customer files start flowing onto the belt here.")
        case .sink: L("Files are delivered to the customer here. A closed, clean file that meets the contract earns money.")
        case .scanner: L("Cheap and fast. Removes known, signed threats without opening the file. Blind to unknown threats; useless on networks without signature updates.")
        case .parser: L("Splits the file into its parts. Filter and transformer only work on an opened file. Higher levels open nested layers and polyglot files.")
        case .filter: L("Drops the selected part type (macro, script, embedded file). Malicious or not, all of them go.")
        case .transformer: L("Re-encodes images; destroys hidden data and unknown payloads. At low levels it degrades image quality and flattens formulas into values.")
        case .packager: L("Repackages an opened file. Required for delivery.")
        case .router: L("Diverts files of the selected container type to the right; everything else goes straight.")
        case .quarantine: L("Destroys the file. No money, but no breach either.")
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
            return wasOpen ? [.closed] : [.noEffect(L("File was already closed"))]
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
        if removed.isEmpty { return [.noEffect(L("No signature matched"))] }
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
        guard file.isOpen else { return [.noEffect(L("File is closed; parse it first"))] }
        let before = file.parts.count
        let depth = file.exposedDepth
        file.parts.removeAll { $0.kind == target && $0.depth <= depth }
        let n = before - file.parts.count
        return n > 0 ? [.removed(target, count: n)] : [.noEffect(L("No \(target.displayName) found"))]
    }

    static func transform(level: Int, file: inout FileItem) -> [ProcessNote] {
        guard file.isOpen else { return [.noEffect(L("File is closed; parse it first"))] }
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
        return notes.isEmpty ? [.noEffect(L("Nothing to transform"))] : notes
    }
}

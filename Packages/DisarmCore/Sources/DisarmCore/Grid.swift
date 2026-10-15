import Foundation

public enum Cell: Codable, Hashable, Sendable {
    case belt(Direction)
    case module(Module)

    public var module: Module? {
        if case .module(let m) = self { return m }
        return nil
    }

    public var beltDirection: Direction? {
        if case .belt(let d) = self { return d }
        return nil
    }
}

public struct Grid: Codable, Hashable, Sendable {
    public let width: Int
    public let height: Int
    public private(set) var cells: [Cell?]

    public init(width: Int, height: Int) {
        self.width = width
        self.height = height
        self.cells = Array(repeating: nil, count: width * height)
    }

    public func contains(_ p: GridPos) -> Bool {
        p.x >= 0 && p.y >= 0 && p.x < width && p.y < height
    }

    public subscript(_ p: GridPos) -> Cell? {
        get { contains(p) ? cells[p.y * width + p.x] : nil }
        set { if contains(p) { cells[p.y * width + p.x] = newValue } }
    }

    public var allPositions: [GridPos] {
        (0..<height).flatMap { y in (0..<width).map { x in GridPos(x, y) } }
    }

    public func positions(of kind: ModuleKind) -> [GridPos] {
        allPositions.filter { self[$0]?.module?.kind == kind }
    }

    public var moduleCount: Int { cells.compactMap { $0?.module }.count }
    public var beltCount: Int { cells.filter { $0?.beltDirection != nil }.count }
}

public extension Grid {
    /// Girişten çıkış yönlerini izleyerek teslimata ulaşılabiliyor mu? (Yönlendiricinin iki çıkışı da izlenir.)
    func sinkReachable(from source: GridPos) -> Bool {
        guard case .module(let src) = self[source] else { return false }
        var stack = [source.moved(src.facing)]
        var seen: Set<GridPos> = [source]
        while let p = stack.popLast() {
            guard contains(p), !seen.contains(p), let cell = self[p] else { continue }
            seen.insert(p)
            switch cell {
            case .belt(let d):
                stack.append(p.moved(d))
            case .module(let m):
                if m.kind == .sink { return true }
                if m.kind == .quarantine || m.kind == .source { continue }
                stack.append(p.moved(m.facing))
                if m.kind == .router { stack.append(p.moved(m.facing.clockwise)) }
            }
        }
        return false
    }
}

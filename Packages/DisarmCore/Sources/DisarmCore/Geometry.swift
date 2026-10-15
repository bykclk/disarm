import Foundation

/// Grid koordinatı. x sağa, y aşağı doğru büyür (satır indeksi).
public struct GridPos: Hashable, Codable, Sendable {
    public var x: Int
    public var y: Int

    public init(_ x: Int, _ y: Int) {
        self.x = x
        self.y = y
    }

    public func moved(_ d: Direction) -> GridPos {
        GridPos(x + d.dx, y + d.dy)
    }
}

public enum Direction: Int, Codable, CaseIterable, Sendable {
    case up = 0, right, down, left

    public var dx: Int { [0, 1, 0, -1][rawValue] }
    public var dy: Int { [-1, 0, 1, 0][rawValue] }

    public var opposite: Direction { Direction(rawValue: (rawValue + 2) % 4)! }
    public var clockwise: Direction { Direction(rawValue: (rawValue + 1) % 4)! }
    public var counterClockwise: Direction { Direction(rawValue: (rawValue + 3) % 4)! }

    /// Ekran yönü: yukarı = 0, saat yönünde artar. (SpriteKit'te zRotation = -angle)
    public var angle: Double { Double(rawValue) * .pi / 2 }

    public static func from(dx: Int, dy: Int) -> Direction? {
        switch (dx.signum(), dy.signum()) {
        case (0, -1): return .up
        case (1, 0): return .right
        case (0, 1): return .down
        case (-1, 0): return .left
        default: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .up: "Yukarı"
        case .right: "Sağ"
        case .down: "Aşağı"
        case .left: "Sol"
        }
    }
}

/// Deterministik, Codable rastgele sayı üreteci (SplitMix64).
public struct SplitMix64: RandomNumberGenerator, Codable, Hashable, Sendable {
    public var state: UInt64

    public init(seed: UInt64) { state = seed }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    public mutating func chance(_ p: Double) -> Bool {
        Double.random(in: 0..<1, using: &self) < p
    }
}

import Foundation
import Testing
@testable import DisarmCore

@Suite struct MoveModuleTests {
    func state() -> GameState {
        var s = GameState(seed: 1)
        s.money = 10_000
        s.placeModule(.filter, at: GridPos(2, 2), facing: .down)
        s.configure(at: GridPos(2, 2)) { $0.filterTarget = .script }
        s.placeBelt(at: GridPos(4, 4), facing: .left)
        s.placeModule(.parser, at: GridPos(5, 5), facing: .up)
        return s
    }

    @Test func moveKeepsConfigAndFacing() {
        var s = state()
        let money = s.money
        #expect(s.moveModule(from: GridPos(2, 2), to: GridPos(3, 3)).isSuccess)
        #expect(s.grid[GridPos(2, 2)] == nil)
        let m = s.grid[GridPos(3, 3)]?.module
        #expect(m?.kind == .filter && m?.facing == .down && m?.config.filterTarget == .script)
        #expect(s.money == money, "moving is free")
    }

    @Test func movingOntoBeltRefundsIt() {
        var s = state()
        let money = s.money
        #expect(s.moveModule(from: GridPos(2, 2), to: GridPos(4, 4)).isSuccess)
        #expect(s.grid[GridPos(4, 4)]?.module?.kind == .filter)
        #expect(s.money == money + GameState.beltCost)
    }

    @Test func refusesOccupiedProtectedAndOutOfBounds() {
        var s = state()
        #expect(s.moveModule(from: GridPos(2, 2), to: GridPos(5, 5)).error == .cellOccupied)
        #expect(s.moveModule(from: s.location.sourcePos, to: GridPos(1, 1)).error == .protected)
        #expect(s.moveModule(from: GridPos(2, 2), to: s.location.sinkPos).error == .cellOccupied)
        #expect(s.moveModule(from: GridPos(2, 2), to: GridPos(99, 0)).error == .outOfBounds)
        #expect(s.moveModule(from: GridPos(0, 0), to: GridPos(1, 1)).error == .outOfBounds, "empty source cell")
        #expect(s.moveModule(from: GridPos(2, 2), to: GridPos(2, 2)).isSuccess)
        #expect(s.grid[GridPos(2, 2)]?.module?.kind == .filter)
    }
}

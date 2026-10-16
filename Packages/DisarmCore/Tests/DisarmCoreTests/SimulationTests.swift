import Foundation
import Testing
@testable import DisarmCore

@Suite struct SimulationTests {
    /// Giriş (0,1) sağa bakar. Düz bir bant + ayrıştırıcı + filtre + paketleyici + teslimat.
    func buildPipeline() -> GameState {
        var s = GameState(seed: 3)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 100_000
        // Satır 1: (1..3) bant, (4) ayrıştırıcı, (5) filtre, (6) paketleyici -> aşağı -> bant -> teslimat (6,8)
        for x in 1...3 { s.placeBelt(at: GridPos(x, 1), facing: .right) }
        s.placeModule(.parser, at: GridPos(4, 1), facing: .right)
        s.placeModule(.filter, at: GridPos(5, 1), facing: .right)
        s.placeModule(.packager, at: GridPos(6, 1), facing: .down)
        for y in 2...7 { s.placeBelt(at: GridPos(6, y), facing: .down) }
        return s
    }

    func run(_ state: inout GameState, sim: inout Simulation, seconds: Double) -> [GameEvent] {
        var events: [GameEvent] = []
        var t = 0.0
        while t < seconds {
            sim.tick(dt: 1.0 / 30.0, state: &state, events: &events)
            t += 1.0 / 30.0
        }
        return events
    }

    /// Akarken bant hücresinin üstüne modül konursa oradaki dosya donmamalı: modüle girip devam etmeli.
    @Test func placingModuleUnderMovingFileDoesNotStrandIt() {
        var s = buildPipeline()
        var sim = Simulation(seed: 3)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        var events: [GameEvent] = []
        // (2,1) bandının üstünde bir dosya belirene kadar ilerle.
        var guardTicks = 0
        while !sim.items.contains(where: { $0.pos == GridPos(2, 1) && !$0.inModule }) && guardTicks < 3000 {
            sim.tick(dt: 1.0 / 30.0, state: &s, events: &events)
            guardTicks += 1
        }
        let stuckID = try! #require(sim.items.first { $0.pos == GridPos(2, 1) && !$0.inModule }).id
        #expect(s.placeModule(.filter, at: GridPos(2, 1), facing: .right).isSuccess)

        let after = run(&s, sim: &sim, seconds: 20)
        #expect(!sim.items.contains { $0.id == stuckID && $0.pos == GridPos(2, 1) && !$0.inModule }, "file stayed frozen on the new module")
        #expect(!sim.items.contains { $0.pos == GridPos(2, 1) && !$0.inModule })
        let processedThere = after.contains { if case .processed(let id, let p, .filter, _) = $0 { return id == stuckID && p == GridPos(2, 1) }; return false }
        let gone = !sim.items.contains { $0.id == stuckID }
        #expect(processedThere || gone, "the stranded file should be processed by the new filter or have moved on")
    }

    @Test func filesFlowAndGetDelivered() {
        var s = buildPipeline()
        var sim = Simulation(seed: 3)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        let events = run(&s, sim: &sim, seconds: 90)
        let delivered = events.filter { if case .delivered = $0 { return true }; return false }
        #expect(delivered.count > 5)
        // Makro filtresi + paketleyici: muhasebe sözleşmesinde ihlal olmamalı.
        let breaches = events.filter { if case .delivered(_, let o) = $0 { return o.breach }; return false }
        #expect(breaches.isEmpty)
        #expect(s.stats.totalDelivered == delivered.count)
    }

    @Test func noPipelineMeansNoDelivery() {
        var s = GameState(seed: 1)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        var sim = Simulation(seed: 1)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        let events = run(&s, sim: &sim, seconds: 20)
        #expect(!events.contains { if case .delivered = $0 { return true }; return false })
        #expect(sim.items.isEmpty)
    }

    @Test func unfilteredPipelineBreaches() {
        var s = GameState(seed: 9)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 100_000
        // Doğrudan teslimat: (1..5,1) sağ, (6,1..7) aşağı -> teslimat (6,8)
        for x in 1...5 { s.placeBelt(at: GridPos(x, 1), facing: .right) }
        for y in 1...7 { s.placeBelt(at: GridPos(6, y), facing: .down) }
        var sim = Simulation(seed: 9)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        let events = run(&s, sim: &sim, seconds: 120)
        let breaches = events.filter { if case .delivered(_, let o) = $0 { return o.breach }; return false }
        #expect(!breaches.isEmpty)
    }

    @Test func removingBeltDropsItems() {
        var s = buildPipeline()
        var sim = Simulation(seed: 3)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        _ = run(&s, sim: &sim, seconds: 10)
        #expect(!sim.items.isEmpty)
        for x in 1...3 { s.remove(at: GridPos(x, 1)) }
        s.remove(at: GridPos(4, 1))
        var events: [GameEvent] = []
        sim.tick(dt: 0.03, state: &s, events: &events)
        #expect(events.contains { if case .dropped = $0 { return true }; return false })
    }

    @Test func contractCompletesAndAdvances() {
        var s = buildPipeline()
        var sim = Simulation(seed: 3)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        let events = run(&s, sim: &sim, seconds: 240)
        #expect(events.contains { if case .contractCompleted = $0 { return true }; return false })
        #expect(s.progress.index >= 1)
    }

    @Test func offlineSettlement() {
        var s = GameState(seed: 1)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.incomeRatePerSec = 2
        s.lastSaved = Date(timeIntervalSinceNow: -3600)
        let before = s.money
        let r = OfflineCalculator.settle(state: &s)
        #expect(r != nil)
        #expect(s.money - before == 3600)
    }

    @Test func stateRoundTripsThroughJSON() throws {
        var s = buildPipeline()
        var sim = Simulation(seed: 3)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        _ = run(&s, sim: &sim, seconds: 5)
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(GameState.self, from: data)
        #expect(back == s)
        let simData = try JSONEncoder().encode(sim)
        #expect(try JSONDecoder().decode(Simulation.self, from: simData) == sim)
    }
}

@Suite struct EconomyTests {
    @Test func cannotOverspend() {
        var s = GameState(seed: 1)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 10
        #expect(s.placeModule(.parser, at: GridPos(2, 2), facing: .right) .error == .insufficientFunds(needed: 120))
        #expect(s.placeBelt(at: GridPos(2, 2), facing: .right) .isSuccess)
        #expect(s.money == 5)
    }

    @Test func protectedModulesStay() {
        var s = GameState(seed: 1)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        let src = s.location.sourcePos
        #expect(s.remove(at: src) .error == .protected)
        #expect(s.rotate(at: src) .error == .protected)
    }

    @Test func moduleAvailabilityPerLocation() {
        var s = GameState(seed: 1)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 100_000
        #expect(s.placeModule(.transformer, at: GridPos(2, 2), facing: .right) .error == .notAvailableHere)
        #expect(s.unlockLocation(.company) .error == .reputationTooLow(needed: 20))
        s.reputation = 20
        #expect(s.unlockLocation(.company) .isSuccess)
        #expect(s.switchLocation(.company) .isSuccess)
        #expect(s.placeModule(.transformer, at: GridPos(2, 2), facing: .right) .isSuccess)
    }
}

@Suite struct ReachabilityTests {
    @Test func detectsConnectedAndBrokenLines() {
        var s = GameState(seed: 1)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 10_000
        let src = s.location.sourcePos
        #expect(!s.grid.sinkReachable(from: src))
        for x in 1...5 { s.placeBelt(at: GridPos(x, 1), facing: .right) }
        for y in 1...7 { s.placeBelt(at: GridPos(6, y), facing: .down) }
        #expect(s.grid.sinkReachable(from: src))
        s.remove(at: GridPos(6, 4))
        #expect(!s.grid.sinkReachable(from: src))
        // Yönlendiricinin yan çıkışı da sayılır (ofiste satılmaz; doğrudan grid'e yazılır).
        s.grid[GridPos(6, 4)] = .module(Module(kind: .router, facing: .left))
        #expect(!s.grid.sinkReachable(from: src)) // ileri (5,4) boş, sağ çıkış yukarı: geri döner
        s.grid[GridPos(6, 4)] = .module(Module(kind: .router, facing: .right))
        #expect(s.grid.sinkReachable(from: src)) // ileri harita dışı, sağ çıkış aşağı -> teslimat
    }
}

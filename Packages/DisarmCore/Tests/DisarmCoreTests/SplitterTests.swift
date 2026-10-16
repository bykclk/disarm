import Foundation
import Testing
@testable import DisarmCore

/// Ayırıcı: dosyaları sırayla iki çıkışa dağıtır, biri yoksa/doluysa diğerini kullanır.
@Suite struct SplitterTests {
    /// Şirket: 8×12, giriş (3,0) aşağı, çıkış (4,11). Ayırıcı (3,1) aşağı: düz (3,2), yan = sol (2,1).
    func company() -> GameState {
        var s = GameState(seed: 11)
        s.xp = 100_000; s.money = 1_000_000; s.reputation = 1000
        _ = s.unlockLocation(.company)
        #expect(s.switchLocation(.company).isSuccess)
        #expect(s.placeModule(.splitter, at: GridPos(3, 1), facing: .down).isSuccess)
        for y in 2...9 { #expect(s.placeBelt(at: GridPos(3, y), facing: .down).isSuccess) }
        #expect(s.placeBelt(at: GridPos(3, 10), facing: .right).isSuccess)
        #expect(s.placeBelt(at: GridPos(4, 10), facing: .down).isSuccess)
        return s
    }

    func addSideLane(_ s: inout GameState) {
        for y in 1...9 { #expect(s.placeBelt(at: GridPos(2, y), facing: .down).isSuccess) }
        #expect(s.placeBelt(at: GridPos(2, 10), facing: .right).isSuccess)
    }

    func run(_ s: inout GameState, sim: inout Simulation, seconds: Double) -> [GameEvent] {
        var events: [GameEvent] = []
        var t = 0.0
        while t < seconds { sim.tick(dt: 1.0 / 20.0, state: &s, events: &events); t += 0.05 }
        return events
    }

    @Test func splitterIsAvailableFromTheCompanyOn() {
        #expect(!LocationKind.smallOffice.spec.availableModules.contains(.splitter))
        #expect(LocationKind.company.spec.availableModules.contains(.splitter))
        #expect(LocationKind.dataCenter.spec.availableModules.contains(.splitter))
        #expect(ModuleKind.splitter.requiredLevel == 3)
    }

    @Test func splitterAlternatesBetweenBothOutputs() {
        var s = company()
        addSideLane(&s)
        var sim = Simulation(seed: 11)
        sim.incidentsEnabled = false
        var straight = 0, side = 0
        var seen: Set<UUID> = []
        var events: [GameEvent] = []
        var t = 0.0
        while t < 90 {
            sim.tick(dt: 0.05, state: &s, events: &events); t += 0.05
            for item in sim.items where !seen.contains(item.id) {
                if item.pos == GridPos(3, 2) { straight += 1; seen.insert(item.id) }
                if item.pos == GridPos(2, 1) { side += 1; seen.insert(item.id) }
            }
        }
        #expect(straight > 5 && side > 5)
        #expect(abs(straight - side) <= 2, "round-robin: \(straight) vs \(side)")
        #expect(sim.splitCounters[GridPos(3, 1), default: 0] >= straight + side)
        let dropped = events.filter { if case .dropped = $0 { true } else { false } }.count
        #expect(dropped == 0)
    }

    @Test func splitterFallsBackWhenOneSideIsMissing() {
        var s = company() // yan çıkışta bant yok
        var sim = Simulation(seed: 11)
        sim.incidentsEnabled = false
        let events = run(&s, sim: &sim, seconds: 60)
        let delivered = events.filter { if case .delivered = $0 { true } else { false } }.count
        let dropped = events.filter { if case .dropped = $0 { true } else { false } }.count
        #expect(delivered > 5, "every file goes straight when the side exit has no belt")
        #expect(dropped == 0)
    }

    @Test func splitterCostsAndCountsAsModule() {
        let s = company()
        #expect(s.grid.positions(of: .splitter) == [GridPos(3, 1)])
        #expect(ModuleKind.splitter.baseCost > 0)
        #expect(ModuleKind.splitter.maxLevel == 1)
    }

    @Test func lateFlagAndIncidentSurviveSaveRoundTrip() throws {
        var s = company()
        addSideLane(&s)
        var sim = Simulation(seed: 11)
        sim.incidentsEnabled = false
        _ = run(&s, sim: &sim, seconds: 8)
        try #require(!sim.items.isEmpty)
        sim.items[0].file.late = true
        sim.activeIncident = Incident(kind: .audit, remaining: 12)
        let data = try SaveCodec.encode(state: s, sim: sim)
        let back = try #require(SaveCodec.decode(data))
        #expect(back.sim.items.contains { $0.file.late })
        #expect(back.sim.activeIncident?.kind == .audit)
        #expect(back.sim.splitCounters[GridPos(3, 1)] == sim.splitCounters[GridPos(3, 1)])
    }
}

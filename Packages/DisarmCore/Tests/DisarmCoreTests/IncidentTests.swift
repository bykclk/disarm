import Foundation
import Testing
@testable import DisarmCore

/// Süreli krizler ve geç teslimat.
@Suite struct IncidentTests {
    func office(seed: UInt64 = 3, contracts: Int) -> GameState {
        var s = GameState(seed: seed)
        s.xp = 100_000
        s.money = 10_000
        s.tutorialSeen = true
        s.stats.contractsCompleted = contracts
        for x in 1...3 { s.placeBelt(at: GridPos(x, 1), facing: .right) }
        s.placeModule(.parser, at: GridPos(4, 1), facing: .right)
        s.placeModule(.filter, at: GridPos(5, 1), facing: .right)
        s.placeModule(.packager, at: GridPos(6, 1), facing: .down)
        for y in 2...7 { s.placeBelt(at: GridPos(6, y), facing: .down) }
        return s
    }

    func run(_ s: inout GameState, sim: inout Simulation, seconds: Double) -> [GameEvent] {
        var events: [GameEvent] = []
        var t = 0.0
        while t < seconds { sim.tick(dt: 1.0 / 20.0, state: &s, events: &events); t += 0.05 }
        return events
    }

    @Test func noIncidentsBeforeTwoContracts() {
        var s = office(contracts: 1)
        var sim = Simulation(seed: 3)
        sim.incidentTimer = 0
        let events = run(&s, sim: &sim, seconds: 120)
        #expect(!events.contains { if case .incidentStarted = $0 { true } else { false } })
        #expect(sim.activeIncident == nil)
    }

    @Test func incidentStartsLastsAndEnds() {
        var s = office(contracts: 2)
        var sim = Simulation(seed: 3)
        sim.incidentTimer = 1
        var events = run(&s, sim: &sim, seconds: 2)
        let started = events.compactMap { e -> IncidentKind? in if case .incidentStarted(let k) = e { return k }; return nil }
        #expect(started.count == 1)
        let kind = try! #require(started.first)
        #expect(sim.activeIncident?.kind == kind)
        events = run(&s, sim: &sim, seconds: kind.duration + 1)
        #expect(events.contains(.incidentEnded(kind)))
        #expect(sim.activeIncident == nil)
        #expect(sim.incidentTimer >= Simulation.incidentDelay.lowerBound - 1, "next incident is scheduled minutes away")
    }

    @Test func incidentsCanBeDisabled() {
        var s = office(contracts: 5)
        var sim = Simulation(seed: 3)
        sim.incidentsEnabled = false
        sim.incidentTimer = 0
        let events = run(&s, sim: &sim, seconds: 60)
        #expect(!events.contains { if case .incidentStarted = $0 { true } else { false } })
    }

    @Test func zeroDayAddsUnsignedPayloads() {
        let spec = LocationKind.smallOffice.spec.contracts[0]
        var rng = SplitMix64(seed: 5)
        var plain = 0, boosted = 0
        for _ in 0..<400 {
            if FileGenerator.make(for: spec, rng: &rng).parts.contains(where: { $0.kind == .unknown }) { plain += 1 }
            if FileGenerator.make(for: spec, rng: &rng, zeroDay: true).parts.contains(where: { $0.kind == .unknown }) { boosted += 1 }
        }
        #expect(plain == 0, "tier 1 never carries unknowns normally")
        #expect(boosted > 80)
    }

    @Test func rushOrderDoublesPayAndAuditCancelsOnFirstBreach() {
        var s = office(contracts: 2)
        var sim = Simulation(seed: 3)
        sim.incidentsEnabled = false
        sim.activeIncident = Incident(kind: .rushOrder, remaining: 600)
        // incidentsEnabled kapalıyken aktif olay sayılmaz mı? Etkiler aktif olaya bakar; süre sayacı çalışmaz.
        let events = run(&s, sim: &sim, seconds: 60)
        let accepted = events.compactMap { e -> DeliveryOutcome? in if case .delivered(_, let o) = e, o.accepted { return o }; return nil }
        #expect(!accepted.isEmpty)
        #expect(accepted.allSatisfy { $0.pay == s.activeContract.payPerFile * 2 })

        var a = GameState(seed: 4)
        a.xp = 100_000; a.money = 10_000; a.tutorialSeen = true
        a.stats.contractsCompleted = 2
        for x in 1...5 { a.placeBelt(at: GridPos(x, 1), facing: .right) }
        a.placeBelt(at: GridPos(6, 1), facing: .down)
        for y in 2...7 { a.placeBelt(at: GridPos(6, y), facing: .down) }
        var asim = Simulation(seed: 4)
        asim.incidentsEnabled = false
        asim.activeIncident = Incident(kind: .audit, remaining: 600)
        let aevents = run(&a, sim: &asim, seconds: 120)
        let firstBreach = aevents.firstIndex { if case .delivered(_, let o) = $0 { return o.breach }; return false }
        let firstFail = aevents.firstIndex { if case .contractFailed = $0 { true } else { false } }
        #expect(firstBreach != nil && firstFail != nil)
        if let b = firstBreach, let f = firstFail { #expect(f == b + 1, "audit: the first breach cancels the contract immediately") }
    }

    @Test func signatureOutageBlindsTheScanner() {
        var m = Module(kind: .scanner, facing: .right)
        m.config = ModuleConfig()
        var f = FileItem(container: .pdf, parts: [Part(kind: .text), Part(kind: .script, malicious: true)])
        _ = ModuleProcessor.apply(m, level: 3, airGapped: true, to: &f) // kesinti air-gapped gibi davranır
        #expect(f.hasMalicious)
    }

    @Test func slowLineProducesLateFilesWithComplaints() {
        // Tek, yavaş modül (seviye 1 kum havuzu 3 sn = 20 dosya/dk) 36 dosya/dk talebe yetişemez.
        var s = GameState(seed: 8)
        s.xp = 100_000; s.money = 1_000_000; s.reputation = 1000
        for k in LocationKind.allCases { _ = s.unlockLocation(k) }
        _ = s.switchLocation(.dataCenter)
        s.progress.index = 0 // Yayın Stüdyosu, 36/dk
        s.placeModule(.sandbox, at: GridPos(5, 1), facing: .down)
        s.placeModule(.parser, at: GridPos(5, 2), facing: .down)
        s.placeModule(.filter, at: GridPos(5, 3), facing: .down)
        s.configure(at: GridPos(5, 3)) { $0.filterTarget = .script }
        s.placeModule(.packager, at: GridPos(5, 4), facing: .down)
        for y in 5...13 { s.placeBelt(at: GridPos(5, y), facing: .down) }
        var sim = Simulation(seed: 8)
        sim.incidentsEnabled = false
        let events = run(&s, sim: &sim, seconds: 120)
        let late = events.filter { if case .delivered(_, let o) = $0 { return o.issues.contains(.late) }; return false }
        #expect(late.count > 5)
        #expect(sim.backlog > 0)
        #expect(s.progress.complaintReasons[.late, default: 0] > 5)
    }
}

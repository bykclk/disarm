import Foundation
import Testing
@testable import DisarmCore

/// Mekân bitince sıradaki mekâna yönlendirme.
@Suite struct NextSiteTests {
    @Test func nextLocationOrder() {
        #expect(LocationKind.smallOffice.next == .company)
        #expect(LocationKind.government.next == .dataCenter)
        #expect(LocationKind.dataCenter.next == nil)
    }

    @Test func finishingLastContractEmitsLocationFinishedOnce() {
        var s = GameState(seed: 3)
        s.money = 100_000
        s.tutorialSeen = true
        let n = s.location.contracts.count
        s.progress = ContractProgress(index: n - 1)
        s.progress.completions = n - 1
        s.progress.delivered = s.activeContract.targetFiles - 1
        for x in 1...3 { s.placeBelt(at: GridPos(x, 1), facing: .right) }
        s.placeModule(.parser, at: GridPos(4, 1), facing: .right)
        s.placeModule(.filter, at: GridPos(5, 1), facing: .right)
        s.placeModule(.packager, at: GridPos(6, 1), facing: .down)
        for y in 2...7 { s.placeBelt(at: GridPos(6, y), facing: .down) }

        var sim = Simulation(seed: 3)
        var events: [GameEvent] = []
        var t = 0.0
        while t < 120 && !events.contains(.locationFinished(.smallOffice)) {
            sim.tick(dt: 1.0 / 30.0, state: &s, events: &events)
            t += 1.0 / 30.0
        }
        #expect(events.contains(.locationFinished(.smallOffice)))
        #expect(s.isFinished(.smallOffice))
        #expect(Hint.pending(for: s) == .officeDone, "player should be pointed at the next site")
        #expect(Hint.officeDone.action == .openLocations)
        #expect(Hint.officeDone.text.contains(LocationKind.company.spec.displayName))

        // Son sözleşme tekrar bitse de olay yeniden gelmez.
        events.removeAll()
        s.progress.delivered = s.activeContract.targetFiles - 1
        var t2 = 0.0
        while t2 < 60 && !events.contains(where: { if case .contractCompleted = $0 { true } else { false } }) {
            sim.tick(dt: 1.0 / 30.0, state: &s, events: &events)
            t2 += 1.0 / 30.0
        }
        #expect(!events.contains(.locationFinished(.smallOffice)))

        // Sıradaki mekân açılınca yönlendirme kalkar.
        s.reputation = 1000
        #expect(s.unlockLocation(.company).isSuccess)
        _ = s.switchLocation(.smallOffice)
        #expect(Hint.pending(for: s) != .officeDone)
    }

    @Test func siteDoneHintsCoverEveryNonFinalSite() {
        for site in LocationKind.allCases where site.next != nil {
            let hint = Hint.allCases.first { $0.finishedSite == site }
            #expect(hint != nil, "no site-done hint for \(site)")
            #expect(hint?.text.isEmpty == false)
        }
    }
}

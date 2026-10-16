import Foundation
import Testing
@testable import DisarmCore

/// Şikayet nedenlerinin sayımı ve etiketleri.
@Suite struct ComplaintTests {
    @Test func issuesMapToReasonsAndShortLabels() {
        #expect(DeliveryIssue.breach([.macro]).reason == nil)
        #expect(DeliveryIssue.mustRemoveLeft(.macro).reason == .left(.macro))
        #expect(DeliveryIssue.mustKeepLost(.script).reason == .lost(.script))
        #expect(DeliveryIssue.lowImageQuality(actual: 80, minimum: 85).reason == .lowImageQuality)
        #expect(DeliveryIssue.encryptedRejected.reason == .encrypted)
        #expect(DeliveryIssue.deliveredOpen.reason == .deliveredOpen)
        for issue in [DeliveryIssue.mustRemoveLeft(.macro), .lowImageQuality(actual: 80, minimum: 85), .breach([.script])] {
            #expect(!issue.shortText.isEmpty)
        }
    }

    @Test func scannerOnlyLineCountsMacroComplaints() {
        // Muhasebe: zararsız makrolar kalır → "makro kaldı" şikayeti.
        var s = GameState(seed: 3)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 10_000
        s.tutorialSeen = true
        s.placeModule(.scanner, at: GridPos(1, 1), facing: .right)
        for x in 2...5 { s.placeBelt(at: GridPos(x, 1), facing: .right) }
        s.placeBelt(at: GridPos(6, 1), facing: .down)
        for y in 2...7 { s.placeBelt(at: GridPos(6, y), facing: .down) }
        var sim = Simulation(seed: 3)
        var events: [GameEvent] = []
        var t = 0.0
        while t < 90 && s.progress.index == 0 {
            sim.tick(dt: 1.0 / 20.0, state: &s, events: &events)
            t += 1.0 / 20.0
        }
        let p = s.progress.index == 0 ? s.progress : ContractProgress()
        if s.progress.index == 0 {
            #expect(p.complaints > 0)
            #expect(p.complaintReasons[.left(.macro), default: 0] > 0)
            #expect(p.complaintReasons.values.reduce(0, +) >= p.complaints)
            #expect(p.sortedComplaintReasons.first?.reason == .left(.macro))
        }
        // Tur bitince sayaçlarla birlikte nedenler de sıfırlanır.
        var q = ContractProgress()
        q.complaintReasons = [.lowImageQuality: 3]
        q.complaints = 3
        q.resetCounters()
        #expect(q.complaintReasons.isEmpty && q.complaints == 0)
    }

    @Test func beltOnlyLineCountsBreachKinds() {
        // Hiç modül yok: zararlı makrolar kapalı dosyada teslim edilir → ihlal, neden makro.
        var s = GameState(seed: 5)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 10_000
        s.tutorialSeen = true
        for x in 1...5 { s.placeBelt(at: GridPos(x, 1), facing: .right) }
        s.placeBelt(at: GridPos(6, 1), facing: .down)
        for y in 2...7 { s.placeBelt(at: GridPos(6, y), facing: .down) }
        var sim = Simulation(seed: 5)
        var events: [GameEvent] = []
        var t = 0.0
        var breachLabels: [String] = []
        while t < 120 && s.progress.breaches == 0 {
            events.removeAll()
            sim.tick(dt: 1.0 / 20.0, state: &s, events: &events)
            t += 1.0 / 20.0
            for e in events {
                if case .delivered(_, let o) = e, o.breach { breachLabels.append(o.issues[0].shortText) }
            }
        }
        #expect(s.progress.breaches == 1)
        #expect(s.progress.breachReasons == [.macro: 1])
        #expect(s.progress.sortedBreachReasons.first?.kind == .macro)
        #expect(breachLabels.first?.contains(PartKind.macro.displayName) == true)
        var q = s.progress
        q.resetCounters()
        #expect(q.breachReasons.isEmpty)
    }

    @Test func reasonsSurviveSaveAndDefaultWhenMissing() throws {
        var s = GameState(seed: 4)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.progress.complaintReasons = [.left(.macro): 2, .lowImageQuality: 1, .lost(.formula): 4]
        s.progress.breachReasons = [.macro: 1, .unknown: 2]
        let data = try SaveCodec.encode(state: s, sim: Simulation(seed: 4))
        #expect(try #require(SaveCodec.decode(data)).state == s)

        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var state = obj["state"] as! [String: Any]
        var contracts = state["contracts"] as! [String: Any]
        var office = contracts["smallOffice"] as! [String: Any]
        office.removeValue(forKey: "complaintReasons")
        office.removeValue(forKey: "breachReasons")
        contracts["smallOffice"] = office
        state["contracts"] = contracts
        obj["state"] = state
        let old = try #require(SaveCodec.decode(try JSONSerialization.data(withJSONObject: obj)))
        #expect(old.state.progress.complaintReasons.isEmpty)
        #expect(old.state.progress.breachReasons.isEmpty)
    }
}

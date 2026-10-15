import Foundation
import Testing
@testable import DisarmCore

/// Kampanya bitişi ve prestij.
@Suite struct CampaignTests {
    /// Tüm mekânlar bitmiş gibi işaretler; `except` mekânı son sözleşmesinin bir teslimat öncesinde bırakılır.
    func nearlyFinished(seed: UInt64 = 3, except pending: LocationKind = .smallOffice) -> GameState {
        var s = GameState(seed: seed)
        s.money = 100_000
        s.reputation = 1000
        for kind in LocationKind.allCases {
            let n = kind.spec.contracts.count
            var p = ContractProgress(index: n - 1)
            p.completions = kind == pending ? n - 1 : n
            s.contracts[kind] = p
            if kind != .smallOffice { s.layouts[kind] = kind.spec.emptyGrid() }
            s.unlockedLocations.insert(kind)
        }
        _ = s.switchLocation(pending)
        s.progress.delivered = s.activeContract.targetFiles - 1
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

    func simpleLine(_ s: inout GameState) {
        for x in 1...3 { s.placeBelt(at: GridPos(x, 1), facing: .right) }
        s.placeModule(.parser, at: GridPos(4, 1), facing: .right)
        s.placeModule(.filter, at: GridPos(5, 1), facing: .right)
        s.placeModule(.packager, at: GridPos(6, 1), facing: .down)
        for y in 2...7 { s.placeBelt(at: GridPos(6, y), facing: .down) }
    }

    @Test func finishedMeansEveryContractCompletedOnce() {
        var s = GameState(seed: 1)
        #expect(!s.campaignFinished)
        #expect(s.completedContractCount == 0)
        #expect(GameState.totalContractCount == 17)

        s = nearlyFinished()
        #expect(!s.campaignFinished)
        #expect(s.completedContractCount == GameState.totalContractCount - 1)
        #expect(s.isFinished(.bank) && !s.isFinished(.smallOffice))

        s.contracts[.smallOffice]!.completions += 1
        #expect(s.campaignFinished)
        // Son sözleşme tekrar tekrar bitirilse de sayım taşmaz.
        s.contracts[.government]!.completions = 99
        #expect(s.completedContracts(in: .government) == LocationKind.government.spec.contracts.count)
    }

    @Test func lastDeliveryCompletesTheCampaignOnce() {
        var s = nearlyFinished()
        simpleLine(&s)
        var sim = Simulation(seed: 3)
        let events = run(&s, sim: &sim, seconds: 120)
        #expect(events.contains(.campaignCompleted))
        #expect(events.filter { $0 == .campaignCompleted }.count == 1)
        #expect(s.campaignCompleted)
        #expect(s.stats.campaignsCompleted == 1)
        #expect(s.stats.contractsCompleted >= 1)
        #expect(s.stats.bestCampaignSeconds > 0 && s.stats.bestCampaignSeconds <= 120)
        #expect(s.progress.index == s.location.contracts.count - 1, "last contract keeps repeating")

        // Sonraki tamamlamalar kampanyayı yeniden bitirmez.
        s.progress.delivered = s.activeContract.targetFiles - 1
        let more = run(&s, sim: &sim, seconds: 60)
        #expect(!more.contains(.campaignCompleted))
        #expect(s.stats.campaignsCompleted == 1)
    }

    @Test func newCampaignResetsProgressKeepsHistoryAndBoosts() {
        var s = nearlyFinished()
        s.tutorialSeen = true
        s.moduleLevels[.parser] = 3
        s.beltLevel = 4
        s.stats.totalDelivered = 500
        s.campaignCompleted = true
        let seed = s.rngSeed
        s.startNewCampaign()

        #expect(s.prestige == 1)
        #expect(!s.campaignCompleted)
        #expect(s.money == GameState.startingMoney + GameState.prestigeStartingBonus)
        #expect(s.reputation == 0)
        #expect(s.unlockedLocations == [.smallOffice])
        #expect(s.layouts.keys.count == 1 && s.layouts[.smallOffice] == LocationKind.smallOffice.spec.emptyGrid())
        #expect(s.contracts == [.smallOffice: ContractProgress()])
        #expect(s.moduleLevels.isEmpty && s.beltLevel == 1 && s.intakeLevel == 1)
        #expect(s.stats.totalDelivered == 500, "lifetime stats survive")
        #expect(s.tutorialSeen, "no tutorial on the second run")
        #expect(s.rngSeed != seed)
        #expect(s.prestigePayMultiplier == 1.15)
        #expect(s.prestigeFlowMultiplier == 1.1)

        s.startNewCampaign()
        #expect(s.prestige == 2)
        #expect(s.money == GameState.startingMoney + 2 * GameState.prestigeStartingBonus)
    }

    @Test func prestigeScalesPayFlowAndBonus() {
        func play(prestige: Int) -> (spawned: Int, acceptedPay: Int?, money: Int) {
            var s = GameState(seed: 5)
            s.money = 100_000
            s.prestige = prestige
            s.progress.delivered = s.activeContract.targetFiles - 1
            simpleLine(&s)
            let before = s.money
            var sim = Simulation(seed: 5)
            let events = run(&s, sim: &sim, seconds: 90)
            let spawned = events.filter { if case .spawned = $0 { true } else { false } }.count
            let pay = events.compactMap { e -> Int? in
                if case .delivered(_, let o) = e, o.accepted { return o.pay }
                return nil
            }.first
            return (spawned, pay, s.money - before)
        }
        let base = play(prestige: 0)
        let boosted = play(prestige: 2)
        let contract = GameState(seed: 5).activeContract
        #expect(base.acceptedPay == contract.payPerFile)
        #expect(boosted.acceptedPay == Int((Double(contract.payPerFile) * 1.3).rounded()))
        #expect(boosted.spawned > base.spawned, "flow is faster with prestige")
        // Para karşılaştırılmaz: ceza da ölçeklenir, sonraki sözleşmede ihlaller olabilir.
    }

    @Test func campaignFieldsSurviveSaveAndDefaultWhenMissing() throws {
        var s = GameState(seed: 9)
        s.prestige = 2
        s.campaignCompleted = true
        s.stats.campaignsCompleted = 2
        s.stats.bestCampaignSeconds = 1234.5
        let data = try SaveCodec.encode(state: s, sim: Simulation(seed: 9))
        let loaded = try #require(SaveCodec.decode(data))
        #expect(loaded.state == s)

        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var state = obj["state"] as! [String: Any]
        state.removeValue(forKey: "prestige")
        state.removeValue(forKey: "campaignCompleted")
        state["stats"] = ["totalDelivered": 1]
        obj["state"] = state
        let old = try #require(SaveCodec.decode(try JSONSerialization.data(withJSONObject: obj)))
        #expect(old.state.prestige == 0)
        #expect(!old.state.campaignCompleted)
        #expect(old.state.stats.campaignsCompleted == 0)
    }
}

import Foundation
import Testing
@testable import DisarmCore

@Suite struct HintTests {
    func state(_ loc: LocationKind = .smallOffice, index: Int = 0, money: Int = 100) -> GameState {
        var s = GameState(seed: 1)
        s.tutorialSeen = true
        s.money = money
        s.reputation = 1000
        s.xp = 100_000 // seviye kilitleri ipucu testlerinin konusu değil
        if loc != .smallOffice {
            s.money = 100_000
            _ = s.unlockLocation(loc)
            _ = s.switchLocation(loc)
            s.money = money
        }
        s.progress.index = index
        return s
    }

    @Test func nothingDuringTheStepTutorial() {
        var s = GameState(seed: 1)
        s.progress.index = 1
        s.money = 10_000
        #expect(Hint.pending(for: s) == nil, "step tutorial owns the banner until the first delivery")
        s.tutorialSeen = true
        #expect(Hint.pending(for: s) == .scripts)
    }

    @Test func firstContractOfficeShowsNothingUntilMoneyForUpgrades() {
        #expect(Hint.pending(for: state()) == nil)
        var rich = state(index: 1, money: 10_000)
        rich.seenHints.insert(.scripts)
        #expect(Hint.pending(for: rich) == .upgrades)
        rich.moduleLevels[.parser] = 2
        #expect(Hint.pending(for: rich) == nil, "no upgrade nag once upgraded")
    }

    @Test func dismissedHintsAdvanceToTheNextOne() {
        var s = state(.company, index: 0)
        #expect(Hint.pending(for: s) == .company)
        s.seenHints.insert(.company)
        #expect(Hint.pending(for: s) == .nestedZip)
        s.moduleLevels[.parser] = 2
        #expect(Hint.pending(for: s) == nil, "hint resolves itself when the player upgrades")
        s.progress.index = 2
        #expect(Hint.pending(for: s) == .polyglot)
        s.seenHints.insert(.polyglot)
        #expect(Hint.pending(for: s) == .splitter, "parallel lines come up once the company is underway")
        s.seenHints.insert(.splitter)
        #expect(Hint.pending(for: s) == nil)
    }

    @Test func siteEntryHintsAndEncryptedContract() {
        var bank = state(.bank, index: 2)
        #expect(Hint.pending(for: bank) == .bank)
        bank.seenHints.insert(.bank)
        #expect(Hint.pending(for: bank) == .encrypted)
        #expect(Hint.encrypted.action == nil)
        #expect(Hint.pending(for: state(.government)) == .airGapped)
    }

    @Test func campaignHintComesFirstAndSurvivesPrestige() {
        var s = state(.government, index: 2)
        s.campaignCompleted = true
        #expect(Hint.pending(for: s) == .campaignDone)
        #expect(Hint.campaignDone.action == .openCampaign)
        s.seenHints = [.campaignDone, .airGapped, .bank]
        s.startNewCampaign()
        #expect(s.seenHints.contains(.bank), "hints aren't repeated after prestige")
        #expect(Hint.pending(for: s) == nil)
    }

    @Test func everyHintHasTextAndIsReachable() {
        for h in Hint.allCases {
            #expect(!h.text.isEmpty && !h.icon.isEmpty)
        }
        // Her ipucu en az bir durumda geçerli olmalı.
        var reachable = Set<Hint>()
        for loc in LocationKind.allCases {
            for i in 0..<loc.spec.contracts.count {
                let s = state(loc, index: i, money: 10_000)
                for h in Hint.allCases where h.applies(to: s) { reachable.insert(h) }
            }
        }
        var done = state(); done.campaignCompleted = true
        for h in Hint.allCases where h.applies(to: done) { reachable.insert(h) }
        // Mekân bitmiş, sıradaki kilitli.
        for loc in LocationKind.allCases where loc.next != nil {
            var s = state(loc)
            s.contracts[loc]!.completions = loc.spec.contracts.count
            for h in Hint.allCases where h.applies(to: s) { reachable.insert(h) }
        }
        #expect(reachable == Set(Hint.allCases), "unreachable: \(Set(Hint.allCases).subtracting(reachable))")
    }

    @Test func seenHintsSurviveSaveAndUnknownNamesAreDropped() throws {
        var s = GameState(seed: 2)
        s.seenHints = [.bank, .scripts]
        let data = try SaveCodec.encode(state: s, sim: Simulation(seed: 2))
        #expect(try #require(SaveCodec.decode(data)).state == s)

        var text = String(decoding: data, as: UTF8.self)
        text = text.replacingOccurrences(of: "\"bank\"", with: "\"retiredHint\"")
        let loaded = try #require(SaveCodec.decode(Data(text.utf8)))
        #expect(loaded.state.seenHints == [.scripts])

        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var st = obj["state"] as! [String: Any]
        st.removeValue(forKey: "seenHints")
        obj["state"] = st
        let old = try #require(SaveCodec.decode(try JSONSerialization.data(withJSONObject: obj)))
        #expect(old.state.seenHints.isEmpty)
    }
}

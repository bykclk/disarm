import Foundation
import Testing
@testable import DisarmCore

/// Operatör seviyesi, modül kilitleri ve başarımlar.
@Suite struct LevelTests {
    @Test func xpThresholdsAndLevels() {
        #expect(Progression.xp(forLevel: 1) == 0)
        #expect(Progression.xp(forLevel: 2) == 30)
        #expect(Progression.xp(forLevel: 3) == 80)
        #expect(Progression.xp(forLevel: 5) == 240)
        #expect(Progression.level(forXP: 0) == 1)
        #expect(Progression.level(forXP: 29) == 1)
        #expect(Progression.level(forXP: 30) == 2)
        #expect(Progression.level(forXP: 240) == 5)
        #expect(Progression.level(forXP: 10_000_000) == Progression.maxLevel)
        var s = GameState(seed: 1)
        s.xp = 100
        #expect(s.level == 3)
        #expect(s.xpProgress.current == 20 && s.xpProgress.needed == 70)
    }

    @Test func modulesUnlockByLevel() {
        var s = GameState(seed: 1)
        s.money = 10_000
        #expect(s.placeModule(.parser, at: GridPos(1, 1), facing: .right).isSuccess)
        #expect(s.placeModule(.scanner, at: GridPos(2, 1), facing: .right).error == .levelTooLow(needed: 2))
        #expect(s.placeModule(.quarantine, at: GridPos(2, 1), facing: .right).error == .levelTooLow(needed: 3))
        s.xp = Progression.xp(forLevel: 2)
        #expect(s.placeModule(.scanner, at: GridPos(2, 1), facing: .right).isSuccess)
        #expect(GameState.modulesUnlocked(atLevel: 2) == [.scanner])
        #expect(GameState.modulesUnlocked(atLevel: 5) == [.transformer])
        // Her yerleştirilebilir modül bir seviyede açılır ve en geç 7'de hepsi açık.
        let all = Set(ModuleKind.allCases.filter(\.isPlaceable))
        let unlocked = Set((1...7).flatMap { GameState.modulesUnlocked(atLevel: $0) })
        #expect(unlocked == all)
    }

    @Test func upgradesUnlockByLevel() {
        var s = GameState(seed: 1)
        s.money = 100_000
        #expect(s.upgradeModule(.parser).error == .levelTooLow(needed: 3))
        s.xp = Progression.xp(forLevel: 3)
        #expect(s.upgradeModule(.parser).isSuccess)
        #expect(s.upgradeModule(.parser).error == .levelTooLow(needed: 6))
        s.xp = Progression.xp(forLevel: 6)
        #expect(s.upgradeModule(.parser).isSuccess)
        #expect(s.level(of: .parser) == 3)
        #expect(s.stats.upgradesBought == 2)
    }

    @Test func deliveriesGrantXPAndLevelUpIsAnnouncedOnce() {
        var s = GameState(seed: 3)
        s.money = 10_000
        for x in 1...3 { s.placeBelt(at: GridPos(x, 1), facing: .right) }
        s.placeModule(.parser, at: GridPos(4, 1), facing: .right)
        s.placeModule(.filter, at: GridPos(5, 1), facing: .right)
        s.placeModule(.packager, at: GridPos(6, 1), facing: .down)
        for y in 2...7 { s.placeBelt(at: GridPos(6, y), facing: .down) }
        var sim = Simulation(seed: 3)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        var events: [GameEvent] = []
        var t = 0.0
        while t < 240 && s.level < 2 {
            sim.tick(dt: 1.0 / 30.0, state: &s, events: &events)
            t += 1.0 / 30.0
        }
        #expect(s.level >= 2)
        #expect(s.xp >= 30)
        let levelUps = events.filter { if case .levelUp = $0 { true } else { false } }
        #expect(levelUps.count == 1)
        #expect(events.contains(.achievementUnlocked(.firstDelivery)))
        #expect(s.achievements.contains(.firstDelivery))
        #expect(events.filter { $0 == .achievementUnlocked(.firstDelivery) }.count == 1, "claimed once")
    }

    /// Doğal oyun hızı: sıfırdan, yalnızca 1. seviye modüllerle ofis oynanınca Tarayıcı (seviye 2) Yazılım Evi'nden
    /// önce, 1. yükseltme kademesi (seviye 3) ofis bitmeden açılmalı.
    @Test func officePacingUnlocksScannerBeforeSoftwareHouse() {
        var s = GameState(seed: 21)
        s.tutorialSeen = true
        let path = (1...5).map { GridPos($0, 1) } + (1...7).map { GridPos(6, $0) }
        for (i, p) in path.enumerated() {
            let next = i + 1 < path.count ? path[i + 1] : s.location.sinkPos
            let dir = Direction.from(dx: next.x - p.x, dy: next.y - p.y) ?? .right
            switch p {
            case GridPos(2, 1): #expect(s.placeModule(.parser, at: p, facing: dir).isSuccess)
            case GridPos(3, 1): #expect(s.placeModule(.filter, at: p, facing: dir).isSuccess)
            case GridPos(4, 1):
                #expect(s.placeModule(.filter, at: p, facing: dir).isSuccess)
                s.configure(at: p) { $0.filterTarget = .script }
            case GridPos(5, 1): #expect(s.placeModule(.packager, at: p, facing: dir).isSuccess)
            default: #expect(s.placeBelt(at: p, facing: dir).isSuccess)
            }
        }
        #expect(s.money >= 0, "starting money must afford the basic line")
        var sim = Simulation(seed: 21)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        var events: [GameEvent] = []
        var t = 0.0
        var levelAtSoftwareHouse: Int?
        while t < 3600 && !s.isFinished(.smallOffice) {
            sim.tick(dt: 1.0 / 20.0, state: &s, events: &events)
            t += 1.0 / 20.0
            if levelAtSoftwareHouse == nil && s.progress.index == 3 { levelAtSoftwareHouse = s.level }
        }
        print("OFİS HIZ: \(Int(t))sn, Yazılım Evi başlarken seviye \(levelAtSoftwareHouse ?? 0), ofis bitince seviye \(s.level) (xp \(s.xp))")
        #expect(s.isFinished(.smallOffice))
        #expect((levelAtSoftwareHouse ?? 0) >= ModuleKind.scanner.requiredLevel)
        #expect(s.level >= Progression.requiredLevel(forUpgradeTo: 2))
        #expect(s.level >= 3)
    }

    @Test func streaksAndCleanContracts() {
        var s = GameState(seed: 1)
        s.stats.acceptedStreak = 24
        s.stats.totalAccepted = 30
        #expect(!Achievement.streak25.isMet(by: s))
        s.stats.bestAcceptedStreak = 25
        #expect(Achievement.streak25.isMet(by: s))
        let before = s.money
        let claimed = s.claimAchievements()
        #expect(claimed.contains(.streak25) && claimed.contains(.firstDelivery))
        #expect(s.money == before + Achievement.streak25.rewardMoney + Achievement.firstDelivery.rewardMoney)
        #expect(s.xp == Achievement.streak25.rewardXP + Achievement.firstDelivery.rewardXP)
        #expect(s.claimAchievements().isEmpty, "no double claim")
    }

    @Test func prestigeKeepsLevelAndAchievements() {
        var s = GameState(seed: 1)
        s.xp = 500
        s.achievements = [.firstDelivery, .hundredFiles]
        s.stats.acceptedStreak = 12
        s.campaignCompleted = true
        s.startNewCampaign()
        #expect(s.xp == 500)
        #expect(s.achievements == [.firstDelivery, .hundredFiles])
        #expect(s.stats.acceptedStreak == 0)
    }

    @Test func oldSavesDeriveXPSoPlacedModulesStayUnlocked() throws {
        // İlerleme öncesi kayıt: dönüştürücü yerleşik, parser seviye 3, xp alanı yok.
        var s = GameState(seed: 9)
        s.xp = 100_000
        s.money = 100_000; s.reputation = 500
        _ = s.unlockLocation(.company); _ = s.switchLocation(.company)
        s.placeModule(.transformer, at: GridPos(3, 2), facing: .down)
        s.moduleLevels[.parser] = 3
        s.stats.totalAccepted = 40
        s.stats.contractsCompleted = 2
        let data = try SaveCodec.encode(state: s, sim: Simulation(seed: 9))
        var obj = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        var state = obj["state"] as! [String: Any]
        state.removeValue(forKey: "xp")
        state.removeValue(forKey: "achievements")
        obj["state"] = state
        let loaded = try #require(SaveCodec.decode(try JSONSerialization.data(withJSONObject: obj)))
        #expect(loaded.repairs.contains(.xpDerived))
        #expect(loaded.state.level >= 6, "parser level 3 needs operator level 6")
        #expect(loaded.state.isUnlocked(.transformer))
        #expect(loaded.state.achievements.isEmpty)
    }
}

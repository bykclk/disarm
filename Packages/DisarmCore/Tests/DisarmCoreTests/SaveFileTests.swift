import Foundation
import Testing
@testable import DisarmCore

@Suite struct SaveFileTests {
    func sample() -> (GameState, Simulation) {
        var s = GameState(seed: 42)
        s.money = 1234
        s.reputation = 7
        s.placeBelt(at: GridPos(1, 1), facing: .right)
        s.placeModule(.parser, at: GridPos(2, 1), facing: .right)
        s.placeModule(.filter, at: GridPos(3, 1), facing: .right)
        s.configure(at: GridPos(3, 1)) { $0.filterTarget = .script }
        s.moduleLevels[.parser] = 2
        s.stats.totalDelivered = 9
        var sim = Simulation(seed: 42)
        var events: [GameEvent] = []
        for _ in 0..<120 { sim.tick(dt: 1.0 / 30.0, state: &s, events: &events) }
        return (s, sim)
    }

    func json(_ data: Data) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    func data(_ obj: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: obj)
    }

    @Test func roundTripIsLossless() throws {
        let (s, sim) = sample()
        let d = try SaveCodec.encode(state: s, sim: sim)
        let loaded = try #require(SaveCodec.decode(d))
        #expect(loaded.state == s)
        #expect(loaded.sim == sim)
        #expect(loaded.repairs.isEmpty)
        #expect(json(d)["version"] as? Int == SaveFile.currentVersion)
    }

    /// Sürüm damgasız ilk kayıtlar (v0) okunur ve göç olarak işaretlenir.
    /// v0'da enum anahtarlı sözlükler `[anahtar, değer, ...]` düz dizisiydi.
    @Test func legacyPayloadWithoutVersionLoads() throws {
        let (s, sim) = sample()
        var obj = json(try SaveCodec.encode(state: s, sim: sim))
        obj.removeValue(forKey: "version")
        var state = obj["state"] as! [String: Any]
        for key in ["layouts", "contracts", "moduleLevels"] {
            let dict = state[key] as! [String: Any]
            state[key] = dict.flatMap { [$0.key, $0.value] }
        }
        obj["state"] = state
        let loaded = try #require(SaveCodec.decode(data(obj)))
        #expect(loaded.state == s)
        #expect(loaded.sim == sim)
        #expect(loaded.repairs == [.migrated(from: 0)])
    }

    /// Yeni eklenen alanlar eski kayıtta yoksa varsayılan alınır, kayıt düşmez.
    @Test func missingFieldsGetDefaults() throws {
        let (s, sim) = sample()
        var obj = json(try SaveCodec.encode(state: s, sim: sim))
        var state = obj["state"] as! [String: Any]
        for key in ["stats", "incomeRatePerSec", "tutorialSeen", "beltLevel", "moduleLevels", "lastSaved"] {
            state.removeValue(forKey: key)
        }
        let stats = ["totalDelivered": 3] as [String: Any]
        state["stats"] = stats
        obj["state"] = state
        let loaded = try #require(SaveCodec.decode(data(obj)))
        #expect(loaded.state.money == s.money)
        #expect(loaded.state.beltLevel == 1)
        #expect(loaded.state.moduleLevels.isEmpty)
        #expect(loaded.state.stats.totalDelivered == 3)
        #expect(loaded.state.stats.totalBreaches == 0)
        #expect(loaded.state.grid[GridPos(2, 1)]?.module?.kind == .parser)
    }

    /// Kaldırılmış bir modül türü hücreyi boşaltır, kalan yerleşim korunur.
    @Test func unknownModuleKindDropsOnlyThatCell() throws {
        let (s, sim) = sample()
        var text = String(decoding: try SaveCodec.encode(state: s, sim: sim), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"kind\":\"parser\"", with: "\"kind\":\"teleporter\"")
        let loaded = try #require(SaveCodec.decode(Data(text.utf8)))
        #expect(loaded.state.grid[GridPos(2, 1)] == nil)
        #expect(loaded.state.grid[GridPos(1, 1)]?.beltDirection == .right)
        #expect(loaded.state.grid[GridPos(3, 1)]?.module?.kind == .filter)
        #expect(loaded.state.grid[s.location.sourcePos]?.module?.kind == .source)
    }

    /// Tanınmayan enum anahtarları (yeni/kaldırılmış mekân ya da modül) atılır.
    @Test func unknownEnumKeysAreSkipped() throws {
        let (s, sim) = sample()
        var obj = json(try SaveCodec.encode(state: s, sim: sim))
        var state = obj["state"] as! [String: Any]
        var levels = state["moduleLevels"] as! [String: Any]
        levels["teleporter"] = 3
        state["moduleLevels"] = levels
        state["unlockedLocations"] = ["smallOffice", "moonBase"]
        var filter = (state["layouts"] as! [String: Any])
        filter["moonBase"] = ["width": 2, "height": 2, "cells": [NSNull(), NSNull(), NSNull(), NSNull()]]
        state["layouts"] = filter
        obj["state"] = state
        let loaded = try #require(SaveCodec.decode(data(obj)))
        #expect(loaded.state.moduleLevels == [.parser: 2])
        #expect(loaded.state.unlockedLocations == [.smallOffice])
        #expect(loaded.state.layouts.keys.sorted { $0.rawValue < $1.rawValue } == [.smallOffice])
    }

    /// Filtre hedefi tanınmıyorsa modül kalır, hedef varsayılana döner.
    @Test func unknownConfigValueFallsBackToDefault() throws {
        let (s, sim) = sample()
        var text = String(decoding: try SaveCodec.encode(state: s, sim: sim), as: UTF8.self)
        text = text.replacingOccurrences(of: "\"filterTarget\":\"script\"", with: "\"filterTarget\":\"gremlin\"")
        let loaded = try #require(SaveCodec.decode(Data(text.utf8)))
        let m = try #require(loaded.state.grid[GridPos(3, 1)]?.module)
        #expect(m.kind == .filter)
        #expect(m.config.filterTarget == ModuleConfig().filterTarget)
    }

    /// Simülasyon bozuksa durum korunur, bant sıfırlanır.
    @Test func corruptSimulationResetsOnlySimulation() throws {
        let (s, sim) = sample()
        var obj = json(try SaveCodec.encode(state: s, sim: sim))
        obj["sim"] = ["items": "nope"]
        let loaded = try #require(SaveCodec.decode(data(obj)))
        #expect(loaded.state == s)
        #expect(loaded.sim.items.isEmpty)
        #expect(loaded.repairs.contains(.simulationReset))

        obj.removeValue(forKey: "sim")
        let loaded2 = try #require(SaveCodec.decode(data(obj)))
        #expect(loaded2.state == s)
        #expect(loaded2.repairs.contains(.simulationReset))
    }

    /// Banttaki tek bir dosya bozuksa yalnızca o düşer.
    @Test func corruptMovingItemIsDropped() throws {
        let (s, fresh) = sample()
        var sim = fresh
        for x in 1...2 {
            let file = FileItem(container: .pdf, parts: [Part(kind: .text)])
            sim.items.append(MovingItem(file: file, pos: GridPos(x, 1), progress: 0.5, heading: .right, inModule: false, remaining: 0, lastNote: nil))
        }
        var obj = json(try SaveCodec.encode(state: s, sim: sim))
        var simObj = obj["sim"] as! [String: Any]
        var items = simObj["items"] as! [[String: Any]]
        items[0]["file"] = "broken"
        simObj["items"] = items
        obj["sim"] = simObj
        let loaded = try #require(SaveCodec.decode(data(obj)))
        #expect(loaded.sim.items.count == sim.items.count - 1)
        #expect(loaded.repairs.isEmpty)
    }

    /// Mekân boyutu değişmişse yerleşim yeni boyuta taşınır, giriş/çıkış tanımdaki yerine konur.
    @Test func resizedLocationIsRefitted() throws {
        var s = GameState(seed: 1)
        s.money = 10_000
        s.placeBelt(at: GridPos(1, 1), facing: .right)
        s.placeModule(.packager, at: GridPos(2, 1), facing: .right)
        // Eski, daha küçük bir yerleşim: 5×5, giriş sağ üstte.
        var old = Grid(width: 5, height: 5)
        old[GridPos(4, 0)] = .module(Module(kind: .source, facing: .down))
        old[GridPos(4, 4)] = .module(Module(kind: .sink, facing: .down))
        old[GridPos(1, 1)] = .belt(.right)
        old[GridPos(2, 1)] = .module(Module(kind: .packager, facing: .right))
        s.layouts[.smallOffice] = old

        let repairs = SaveMigrator.repair(&s)
        #expect(repairs == [.layoutResized(.smallOffice)])
        let spec = LocationKind.smallOffice.spec
        let g = s.grid
        #expect(g.width == spec.width && g.height == spec.height)
        #expect(g[spec.sourcePos]?.module?.kind == .source)
        #expect(g[spec.sinkPos]?.module?.kind == .sink)
        #expect(g[GridPos(4, 0)] == nil)
        #expect(g[GridPos(4, 4)] == nil)
        #expect(g[GridPos(1, 1)]?.beltDirection == .right)
        #expect(g[GridPos(2, 1)]?.module?.kind == .packager)
    }

    @Test func missingAnchorsAreRestored() throws {
        var s = GameState(seed: 1)
        let spec = s.location
        var g = s.grid
        g[spec.sinkPos] = nil
        g[GridPos(3, 3)] = .module(Module(kind: .source, facing: .right))
        s.grid = g
        let repairs = SaveMigrator.repair(&s)
        #expect(repairs == [.anchorsRestored(.smallOffice)])
        #expect(s.grid[spec.sourcePos]?.module?.kind == .source)
        #expect(s.grid[spec.sinkPos]?.module?.kind == .sink)
        #expect(s.grid[GridPos(3, 3)] == nil)
    }

    @Test func levelsAndIndicesAreClamped() throws {
        var s = GameState(seed: 1)
        s.beltLevel = 99
        s.intakeLevel = 0
        s.moduleLevels[.parser] = 50
        s.contracts[.smallOffice]!.index = 999
        let repairs = SaveMigrator.repair(&s)
        #expect(repairs.contains(.levelsClamped))
        #expect(repairs.contains(.contractIndexClamped(.smallOffice)))
        #expect(s.beltLevel == GameState.maxBeltLevel)
        #expect(s.intakeLevel == 1)
        #expect(s.level(of: .parser) == ModuleKind.parser.maxLevel)
        #expect(s.progress.index == s.location.contracts.count - 1)
    }

    @Test func currentLocationWithoutLayoutIsRebuilt() throws {
        var s = GameState(seed: 1)
        s.currentLocation = .bank
        s.unlockedLocations = []
        s.layouts = [:]
        s.contracts = [:]
        let repairs = SaveMigrator.repair(&s)
        #expect(repairs.contains(.locationUnlocked(.smallOffice)))
        #expect(repairs.contains(.locationUnlocked(.bank)))
        #expect(repairs.contains(.layoutAdded(.bank)))
        #expect(repairs.contains(.contractProgressAdded(.bank)))
        #expect(s.grid.width == LocationKind.bank.spec.width)
        #expect(s.layouts[.smallOffice] != nil)
    }

    @Test func garbageIsRejected() {
        #expect(SaveCodec.decode(Data("not json".utf8)) == nil)
        #expect(SaveCodec.decode(Data("{\"version\":1}".utf8)) == nil)
        #expect(SaveCodec.decode(Data("{\"version\":1,\"state\":{\"layouts\":{\"smallOffice\":{\"width\":0,\"height\":0}}}}".utf8)) != nil)
    }
}

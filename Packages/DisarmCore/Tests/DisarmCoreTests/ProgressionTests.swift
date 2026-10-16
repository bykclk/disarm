import Foundation
import Testing
@testable import DisarmCore

/// Her mekân için "ders kitabı" hattını kurar, sözleşmeleri sonuna kadar oynatır ve denge raporu basar.
@Suite struct ProgressionTests {
    struct Report {
        var seconds: Double
        var delivered: Int
        var breaches: Int
        var complaints: Int
        var money: Int
    }

    /// Yol: ardışık hücreler; `modules` o hücreye modül koyar, geri kalanı bant olur. Yön bir sonraki hücreye göre.
    func lay(_ s: inout GameState, path: [GridPos], modules: [GridPos: (ModuleKind, PartKind?)]) {
        for (i, p) in path.enumerated() {
            let next = i + 1 < path.count ? path[i + 1] : s.location.sinkPos
            let dir = Direction.from(dx: next.x - p.x, dy: next.y - p.y) ?? .right
            if let (kind, target) = modules[p] {
                let r = s.placeModule(kind, at: p, facing: dir)
                #expect(r.isSuccess, "\(kind) @\(p): \(String(describing: r.error))")
                if let target { s.configure(at: p) { $0.filterTarget = target } }
            } else {
                #expect(s.placeBelt(at: p, facing: dir).isSuccess)
            }
        }
    }

    func play(_ s: inout GameState, untilContractIndex target: Int, maxSeconds: Double) -> Report {
        var sim = Simulation(seed: 99)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        var events: [GameEvent] = []
        var t = 0.0
        var breaches = 0, complaints = 0, delivered = 0
        let dt = 1.0 / 20.0
        let startIndex = s.progress.index
        var completions = 0
        while t < maxSeconds {
            events.removeAll()
            sim.tick(dt: dt, state: &s, events: &events)
            t += dt
            for e in events {
                switch e {
                case .delivered(_, let o):
                    delivered += 1
                    if o.breach { breaches += 1 } else if !o.accepted { complaints += 1 }
                case .contractCompleted: completions += 1
                default: break
                }
            }
            if completions >= target - startIndex { break }
        }
        return Report(seconds: t, delivered: delivered, breaches: breaches, complaints: complaints, money: s.money)
    }

    func column(_ x: Int, _ ys: ClosedRange<Int>) -> [GridPos] { ys.map { GridPos(x, $0) } }
    func row(_ y: Int, _ xs: ClosedRange<Int>) -> [GridPos] { xs.map { GridPos($0, y) } }

    @Test func officeFullRun() {
        var s = GameState(seed: 1)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        // Başlangıç parasıyla kurulabilmeli: ayrıştırıcı 120 + 2 filtre 180 + paketleyici 100 + bantlar.
        let path = row(1, 1...5) + column(6, 1...7)
        lay(&s, path: path, modules: [
            GridPos(2, 1): (.parser, nil), GridPos(3, 1): (.filter, .macro),
            GridPos(4, 1): (.filter, .script), GridPos(5, 1): (.packager, nil),
        ])
        #expect(s.money >= 0)
        let r = play(&s, untilContractIndex: 3, maxSeconds: 3600)
        print("OFİS: \(Int(r.seconds))sn, teslim \(r.delivered), ihlal \(r.breaches), şikayet \(r.complaints), para \(r.money), itibar \(s.reputation)")
        #expect(r.breaches == 0)
        #expect(s.progress.completions >= 1 || s.progress.index == 2)
        #expect(r.seconds < 1800, "Ofis sözleşmeleri 30 dakikadan uzun sürmemeli")
    }

    @Test func officeScannerOnlyFailsAtTierTwo() {
        var s = GameState(seed: 2)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.progress.index = 1 // Avukatlık: betikler
        let path = row(1, 1...5) + column(6, 1...7)
        lay(&s, path: path, modules: [GridPos(2, 1): (.scanner, nil)])
        let r = play(&s, untilContractIndex: 2, maxSeconds: 600)
        print("OFİS sadece tarayıcı: ihlal \(r.breaches), şikayet \(r.complaints) / teslim \(r.delivered)")
        // Tarayıcı bilinen betikleri yakalar ama zararsız makro/gömülü kalır -> şikayet; ihlal olmamalı.
        #expect(r.breaches == 0)
        #expect(r.complaints > 0)
    }

    @Test func companyNeedsParserLevelTwo() {
        var s = GameState(seed: 3)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 20_000
        s.reputation = 100
        #expect(s.unlockLocation(.company).isSuccess)
        #expect(s.switchLocation(.company).isSuccess)
        let path = column(3, 1...10) + [GridPos(4, 10)]
        let mods: [GridPos: (ModuleKind, PartKind?)] = [
            GridPos(3, 2): (.parser, nil), GridPos(3, 3): (.filter, .macro), GridPos(3, 4): (.filter, .script),
            GridPos(3, 5): (.transformer, nil), GridPos(3, 6): (.packager, nil),
        ]
        lay(&s, path: path, modules: mods)
        // Seviye 1 ayrıştırıcı: iç içe yükler kaçar.
        let weak = play(&s, untilContractIndex: 1, maxSeconds: 400)
        print("ŞİRKET L1: ihlal \(weak.breaches)/\(weak.delivered)")
        #expect(weak.breaches > 0)

        var strong = s
        strong.moduleLevels[.parser] = 3
        strong.moduleLevels[.transformer] = 3
        strong.progress = ContractProgress(index: 0)
        let r = play(&strong, untilContractIndex: 3, maxSeconds: 3600)
        print("ŞİRKET L3: \(Int(r.seconds))sn, teslim \(r.delivered), ihlal \(r.breaches), şikayet \(r.complaints), para \(r.money)")
        #expect(r.breaches == 0)
    }

    @Test func bankScannerIsBlindToUnknown() {
        var s = GameState(seed: 4)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 50_000
        s.reputation = 200
        #expect(s.unlockLocation(.bank).isSuccess)
        #expect(s.switchLocation(.bank).isSuccess)
        s.progress.index = 1 // Yatırım bankası: bilinmeyen tehditler
        s.moduleLevels[.scanner] = 3
        s.moduleLevels[.parser] = 3
        // Tarayıcı + filtreler, dönüştürücü yok.
        lay(&s, path: row(6, 1...7), modules: [
            GridPos(1, 6): (.scanner, nil), GridPos(2, 6): (.parser, nil), GridPos(3, 6): (.filter, .macro),
            GridPos(4, 6): (.filter, .script), GridPos(5, 6): (.filter, .embeddedFile), GridPos(6, 6): (.packager, nil),
        ])
        let r = play(&s, untilContractIndex: 2, maxSeconds: 400)
        print("BANKA tarayıcı+filtre: ihlal \(r.breaches)/\(r.delivered)")
        #expect(r.breaches > 0)

        var t = GameState(seed: 4)
        t.xp = 100_000 // seviye kilitleri bu testin konusu değil
        t.money = 50_000; t.reputation = 200
        _ = t.unlockLocation(.bank); _ = t.switchLocation(.bank)
        t.moduleLevels[.parser] = 3; t.moduleLevels[.transformer] = 2
        lay(&t, path: row(6, 1...7), modules: [
            GridPos(1, 6): (.parser, nil), GridPos(2, 6): (.filter, .macro), GridPos(3, 6): (.filter, .script),
            GridPos(4, 6): (.filter, .embeddedFile), GridPos(5, 6): (.transformer, nil), GridPos(6, 6): (.packager, nil),
        ])
        let ok = play(&t, untilContractIndex: 2, maxSeconds: 3600)
        print("BANKA disarm: \(Int(ok.seconds))sn, teslim \(ok.delivered), ihlal \(ok.breaches), şikayet \(ok.complaints)")
        #expect(ok.breaches == 0)
        #expect(ok.complaints == 0)
    }

    @Test func governmentAirGapped() {
        var s = GameState(seed: 5)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 100_000; s.reputation = 500
        _ = s.unlockLocation(.government); _ = s.switchLocation(.government)
        s.moduleLevels[.parser] = 3; s.moduleLevels[.transformer] = 3; s.moduleLevels[.filter] = 3; s.moduleLevels[.packager] = 3
        s.beltLevel = 3
        let path = column(0, 1...12) + row(13, 0...8)
        lay(&s, path: path, modules: [
            GridPos(0, 2): (.parser, nil), GridPos(0, 3): (.filter, .macro), GridPos(0, 4): (.filter, .script),
            GridPos(0, 5): (.filter, .embeddedFile), GridPos(0, 6): (.transformer, nil), GridPos(0, 7): (.packager, nil),
        ])
        let r = play(&s, untilContractIndex: 2, maxSeconds: 3600)
        print("KAMU: \(Int(r.seconds))sn, teslim \(r.delivered), ihlal \(r.breaches), şikayet \(r.complaints), para \(r.money)")
        #expect(r.breaches == 0)
        #expect(r.complaints == 0)
    }
}

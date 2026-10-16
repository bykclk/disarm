import Foundation
import Testing
@testable import DisarmCore

/// Yeni müşteriler (yazılım evi, hastane), şifreli arşiv basamağı ve üç kat iç içe arşivler.
@Suite struct ContentDepthTests {
    func apply(_ kind: ModuleKind, level: Int = 1, target: PartKind = .macro, to f: inout FileItem) -> [ProcessNote] {
        ModuleProcessor.apply(Module(kind: kind, facing: .right, config: ModuleConfig(filterTarget: target)),
                              level: level, airGapped: false, to: &f)
    }

    @Test func encryptedFileCannotBeOpenedOrInspected() {
        var f = FileItem(container: .zip, parts: [Part(kind: .script, malicious: true)], encrypted: true)
        _ = apply(.scanner, level: 3, to: &f)
        #expect(f.hasMalicious, "scanner must not see inside an encrypted file")
        _ = apply(.parser, level: 3, to: &f)
        #expect(!f.isOpen, "parser must not open an encrypted file")
        _ = apply(.filter, target: .script, to: &f)
        _ = apply(.transformer, level: 3, to: &f)
        #expect(f.hasMalicious)
        #expect(f.imageQuality == 1.0)
    }

    @Test func bankRejectsHarmlessEncryptedFileButLawFirmAccepts() {
        let f = FileItem(container: .pdf, parts: [Part(kind: .text)], encrypted: true)
        let bank = DeliveryEvaluator.evaluate(f, policy: .forCustomer(.bank), payPerFile: 100)
        #expect(!bank.breach)
        #expect(bank.pay == 0)
        #expect(bank.issues == [.encryptedRejected])
        let law = DeliveryEvaluator.evaluate(f, policy: .forCustomer(.lawFirm), payPerFile: 100)
        #expect(law.accepted)
        #expect(law.pay == 100)
    }

    @Test func encryptedMaliciousDeliveryIsABreach() {
        let f = FileItem(container: .zip, parts: [Part(kind: .macro, malicious: true)], encrypted: true)
        let o = DeliveryEvaluator.evaluate(f, policy: .forCustomer(.bank), payPerFile: 100)
        #expect(o.breach)
    }

    @Test func softwareHouseKeepsBenignScriptsAndLosesNothingWhenMaliciousOnesGo() {
        let policy = Policy.forCustomer(.softwareHouse)
        var scanned = FileItem(container: .docx, parts: [Part(kind: .text), Part(kind: .script), Part(kind: .script, malicious: true)])
        _ = apply(.scanner, to: &scanned)
        #expect(!scanned.hasMalicious)
        #expect(DeliveryEvaluator.evaluate(scanned, policy: policy, payPerFile: 20).accepted)

        var filtered = FileItem(container: .docx, parts: [Part(kind: .text), Part(kind: .script), Part(kind: .script, malicious: true)])
        _ = apply(.parser, to: &filtered)
        _ = apply(.filter, target: .script, to: &filtered)
        _ = apply(.packager, to: &filtered)
        let o = DeliveryEvaluator.evaluate(filtered, policy: policy, payPerFile: 20)
        #expect(!o.accepted)
        #expect(o.issues.contains(.mustKeepLost(.script)))

        // Yalnızca zararlı betik taşıyan dosya: silinmesi "betik kaybı" sayılmaz.
        var onlyBad = FileItem(container: .pdf, parts: [Part(kind: .text), Part(kind: .script, malicious: true)])
        _ = apply(.scanner, to: &onlyBad)
        #expect(DeliveryEvaluator.evaluate(onlyBad, policy: policy, payPerFile: 20).accepted)
    }

    @Test func hospitalNeedsLevelThreeTransformer() {
        let policy = Policy.forCustomer(.hospital)
        func run(level: Int) -> DeliveryOutcome {
            var f = FileItem(container: .png, parts: [Part(kind: .image), Part(kind: .hiddenData)])
            _ = apply(.parser, to: &f)
            _ = apply(.transformer, level: level, to: &f)
            _ = apply(.packager, to: &f)
            return DeliveryEvaluator.evaluate(f, policy: policy, payPerFile: 40)
        }
        let weak = run(level: 2)
        #expect(!weak.accepted)
        #expect(weak.issues.contains { if case .lowImageQuality = $0 { true } else { false } })
        #expect(run(level: 3).accepted)

        var untouched = FileItem(container: .png, parts: [Part(kind: .image), Part(kind: .hiddenData)])
        _ = apply(.parser, to: &untouched); _ = apply(.packager, to: &untouched)
        #expect(DeliveryEvaluator.evaluate(untouched, policy: policy, payPerFile: 40).issues.contains(.mustRemoveLeft(.hiddenData)))
    }

    @Test func routerDivertsByEncryptionWhenConfigured() {
        let plainZip = FileItem(container: .zip, parts: [])
        let encryptedPdf = FileItem(container: .pdf, parts: [], encrypted: true)
        let byContainer = ModuleConfig(routeTarget: .zip)
        #expect(byContainer.diverts(plainZip))
        #expect(!byContainer.diverts(encryptedPdf))
        let byEncryption = ModuleConfig(routeTarget: .zip, routeEncrypted: true)
        #expect(!byEncryption.diverts(plainZip))
        #expect(byEncryption.diverts(encryptedPdf))
    }

    @Test func tierSixGeneratesBothKindsOfEncryptedFiles() {
        let spec = LocationKind.bank.spec.contracts[2]
        #expect(spec.tier == 6)
        var rng = SplitMix64(seed: 7)
        var encryptedBad = 0, encryptedGood = 0
        for _ in 0..<400 {
            let f = FileGenerator.make(for: spec, rng: &rng)
            if f.encrypted { if f.hasMalicious { encryptedBad += 1 } else { encryptedGood += 1 } }
        }
        #expect(encryptedBad > 20)
        #expect(encryptedGood > 20)

        let lower = LocationKind.bank.spec.contracts[1]
        var rng2 = SplitMix64(seed: 7)
        for _ in 0..<400 { #expect(!FileGenerator.make(for: lower, rng: &rng2).encrypted) }
    }

    @Test func tierFiveNestsThreeLayersDeep() {
        let spec = LocationKind.bank.spec.contracts[1]
        var rng = SplitMix64(seed: 3)
        var deep = 0
        for _ in 0..<600 where FileGenerator.make(for: spec, rng: &rng).parts.contains(where: { $0.depth == 2 && $0.malicious }) { deep += 1 }
        #expect(deep > 10)

        let office = LocationKind.smallOffice.spec.contracts[0]
        var rng2 = SplitMix64(seed: 3)
        for _ in 0..<300 { #expect(!FileGenerator.make(for: office, rng: &rng2).parts.contains { $0.depth == 2 }) }
    }

    @Test func catalogIsWellFormed() {
        var ids = Set<String>()
        for kind in LocationKind.allCases {
            for c in kind.spec.contracts {
                #expect(ids.insert(c.id).inserted, "duplicate contract id \(c.id)")
                #expect(c.tier >= 0 && c.tier <= ContractSpec.maxTier)
                #expect(c.targetFiles > 0 && c.payPerFile > 0 && c.filesPerMinute > 0)
                #expect(!c.containerWeights.isEmpty)
            }
        }
        #expect(LocationKind.smallOffice.spec.contracts.count == 4)
        #expect(LocationKind.company.spec.contracts.count == 4)
        #expect(LocationKind.bank.spec.contracts.count == 3)
        #expect(LocationKind.government.spec.contracts.count == 3)
        #expect(LocationKind.dataCenter.spec.contracts.count == 3)
        // Şifreli dosyalar yalnızca şifreliyi reddeden müşterilerde gelir; aksi halde basamak anlamsız.
        for kind in LocationKind.allCases {
            for c in kind.spec.contracts where c.tier >= 6 { #expect(c.policy.rejectsEncrypted) }
        }
    }
}

/// Yeni sözleşmelerin ders kitabı hatlarıyla oynanabilirliği.
@Suite struct ContentDepthProgressionTests {
    struct Report { var seconds: Double; var delivered: Int; var breaches: Int; var complaints: Int; var quarantined: Int }

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

    func play(_ s: inout GameState, completions target: Int, maxSeconds: Double) -> Report {
        var sim = Simulation(seed: 99)
        var events: [GameEvent] = []
        var t = 0.0
        var r = Report(seconds: 0, delivered: 0, breaches: 0, complaints: 0, quarantined: 0)
        var completions = 0
        let dt = 1.0 / 20.0
        while t < maxSeconds {
            events.removeAll()
            sim.tick(dt: dt, state: &s, events: &events)
            t += dt
            for e in events {
                switch e {
                case .delivered(_, let o):
                    r.delivered += 1
                    if o.breach { r.breaches += 1 } else if !o.accepted { r.complaints += 1 }
                case .quarantined: r.quarantined += 1
                case .contractCompleted: completions += 1
                default: break
                }
            }
            if completions >= target { break }
        }
        r.seconds = t
        return r
    }

    func row(_ y: Int, _ xs: ClosedRange<Int>) -> [GridPos] { xs.map { GridPos($0, y) } }
    func column(_ x: Int, _ ys: ClosedRange<Int>) -> [GridPos] { ys.map { GridPos(x, $0) } }

    @Test func softwareHouseRewardsScannerAndPunishesScriptFilter() {
        var s = GameState(seed: 10)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 5000
        s.progress.index = 3
        #expect(s.activeContract.customer == .softwareHouse)
        let path = row(1, 1...5) + column(6, 1...7)
        lay(&s, path: path, modules: [
            GridPos(1, 1): (.scanner, nil), GridPos(2, 1): (.parser, nil),
            GridPos(3, 1): (.filter, .macro), GridPos(5, 1): (.packager, nil),
        ])
        let good = play(&s, completions: 1, maxSeconds: 1800)
        print("YAZILIM EVİ tarayıcı+makro filtresi: \(Int(good.seconds))sn, teslim \(good.delivered), ihlal \(good.breaches), şikayet \(good.complaints)")
        #expect(good.breaches == 0)
        #expect(good.complaints == 0)
        #expect(good.delivered >= 40)

        var t = GameState(seed: 10)
        t.xp = 100_000 // seviye kilitleri bu testin konusu değil
        t.money = 5000
        t.progress.index = 3
        lay(&t, path: path, modules: [
            GridPos(2, 1): (.parser, nil), GridPos(3, 1): (.filter, .macro),
            GridPos(4, 1): (.filter, .script), GridPos(5, 1): (.packager, nil),
        ])
        let bad = play(&t, completions: 1, maxSeconds: 1800)
        print("YAZILIM EVİ betik filtresi: ihlal \(bad.breaches), şikayet \(bad.complaints) / \(bad.delivered)")
        #expect(bad.breaches == 0)
        #expect(bad.complaints > bad.delivered / 3, "deleting source code must cost the player")
    }

    @Test func hospitalNeedsGentleTransformer() {
        func build(transformerLevel: Int) -> GameState {
            var s = GameState(seed: 11)
            s.xp = 100_000 // seviye kilitleri bu testin konusu değil
            s.money = 30_000; s.reputation = 100
            _ = s.unlockLocation(.company); _ = s.switchLocation(.company)
            s.progress.index = 3
            #expect(s.activeContract.customer == .hospital)
            s.moduleLevels[.parser] = 3
            s.moduleLevels[.transformer] = transformerLevel
            let path = column(3, 1...10) + [GridPos(4, 10)]
            lay(&s, path: path, modules: [
                GridPos(3, 2): (.parser, nil), GridPos(3, 3): (.filter, .macro), GridPos(3, 4): (.filter, .script),
                GridPos(3, 5): (.filter, .embeddedFile), GridPos(3, 6): (.transformer, nil), GridPos(3, 7): (.packager, nil),
            ])
            return s
        }
        var strong = build(transformerLevel: 3)
        let ok = play(&strong, completions: 1, maxSeconds: 1800)
        print("HASTANE L3: \(Int(ok.seconds))sn, teslim \(ok.delivered), ihlal \(ok.breaches), şikayet \(ok.complaints)")
        #expect(ok.breaches == 0)
        #expect(ok.complaints == 0)

        var weak = build(transformerLevel: 2)
        let bad = play(&weak, completions: 1, maxSeconds: 900)
        print("HASTANE L2: ihlal \(bad.breaches), şikayet \(bad.complaints) / \(bad.delivered)")
        #expect(bad.breaches == 0)
        #expect(bad.complaints > bad.delivered / 3)
    }

    @Test func privateBankingNeedsEncryptedRoutingIntoQuarantine() {
        func build(withRouter: Bool) -> GameState {
            var s = GameState(seed: 12)
            s.xp = 100_000 // seviye kilitleri bu testin konusu değil
            s.money = 80_000; s.reputation = 300
            _ = s.unlockLocation(.bank); _ = s.switchLocation(.bank)
            s.progress.index = 2
            #expect(s.activeContract.tier == 6)
            s.moduleLevels[.parser] = 3; s.moduleLevels[.transformer] = 2
            var mods: [GridPos: (ModuleKind, PartKind?)] = [
                GridPos(2, 6): (.parser, nil), GridPos(3, 6): (.filter, .macro), GridPos(4, 6): (.filter, .script),
                GridPos(5, 6): (.filter, .embeddedFile), GridPos(6, 6): (.transformer, nil), GridPos(7, 6): (.packager, nil),
            ]
            if withRouter { mods[GridPos(1, 6)] = (.router, nil) }
            lay(&s, path: row(6, 1...7), modules: mods)
            if withRouter {
                s.configure(at: GridPos(1, 6)) { $0.routeEncrypted = true }
                #expect(s.placeModule(.quarantine, at: GridPos(1, 7), facing: .down).isSuccess)
            }
            return s
        }
        var naive = build(withRouter: false)
        let bad = play(&naive, completions: 1, maxSeconds: 600)
        print("ÖZEL BANKACILIK yönlendiricisiz: ihlal \(bad.breaches), şikayet \(bad.complaints) / \(bad.delivered)")
        #expect(bad.breaches > 0)

        var routed = build(withRouter: true)
        let ok = play(&routed, completions: 1, maxSeconds: 1800)
        print("ÖZEL BANKACILIK yönlendirici→karantina: \(Int(ok.seconds))sn, teslim \(ok.delivered), karantina \(ok.quarantined), ihlal \(ok.breaches), şikayet \(ok.complaints)")
        #expect(ok.breaches == 0)
        #expect(ok.complaints == 0)
        #expect(ok.quarantined > 0)
    }

    @Test func intelligenceServiceAirGappedAndEncrypted() {
        var s = GameState(seed: 13)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 200_000; s.reputation = 500
        _ = s.unlockLocation(.government); _ = s.switchLocation(.government)
        s.progress.index = 2
        #expect(s.activeContract.tier == 6 && s.location.airGapped)
        s.moduleLevels[.parser] = 3; s.moduleLevels[.transformer] = 3; s.moduleLevels[.filter] = 3; s.moduleLevels[.packager] = 3
        s.beltLevel = 3
        // Giriş (0,0) aşağı bakar. Sütun 0'dan satır 3'e dön; sağa bakan yönlendiricinin saat yönü = aşağı → karantina.
        let path = column(0, 1...3) + row(3, 1...8) + column(8, 4...13)
        lay(&s, path: path, modules: [
            GridPos(1, 3): (.router, nil),
            GridPos(2, 3): (.parser, nil), GridPos(3, 3): (.filter, .macro), GridPos(4, 3): (.filter, .script),
            GridPos(5, 3): (.filter, .embeddedFile), GridPos(6, 3): (.transformer, nil), GridPos(7, 3): (.packager, nil),
        ])
        s.configure(at: GridPos(1, 3)) { $0.routeEncrypted = true }
        #expect(s.placeModule(.quarantine, at: GridPos(1, 4), facing: .down).isSuccess)
        let r = play(&s, completions: 1, maxSeconds: 2400)
        print("İSTİHBARAT: \(Int(r.seconds))sn, teslim \(r.delivered), karantina \(r.quarantined), ihlal \(r.breaches), şikayet \(r.complaints)")
        #expect(r.breaches == 0)
        #expect(r.complaints == 0)
        #expect(r.quarantined > 0)
    }
}

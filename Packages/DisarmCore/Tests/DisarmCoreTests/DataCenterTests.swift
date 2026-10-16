import Foundation
import Testing
@testable import DisarmCore

/// Veri Merkezi, Kum Havuzu modülü ve Adli Bilişim müşterisi.
@Suite struct DataCenterTests {
    func apply(_ kind: ModuleKind, level: Int = 1, to f: inout FileItem) -> [ProcessNote] {
        ModuleProcessor.apply(Module(kind: kind, facing: .down), level: level, airGapped: true, to: &f)
    }

    @Test func sandboxRemovesOnlyMaliciousWithoutOpeningOrDegrading() {
        var f = FileItem(container: .png, parts: [
            Part(kind: .image), Part(kind: .macro), Part(kind: .unknown, malicious: true, signatureKnown: false),
            Part(kind: .hiddenData, malicious: true),
        ])
        let notes = apply(.sandbox, to: &f)
        #expect(!f.hasMalicious)
        #expect(!f.isOpen)
        #expect(f.imageQuality == 1.0)
        #expect(f.kinds == [.image, .macro], "harmless content untouched")
        #expect(notes.count == 2)
    }

    @Test func sandboxLevelGatesDepthAndIsBlindToEncryptionAndPolyglot() {
        var nested = FileItem(container: .zip, parts: [Part(kind: .embeddedFile), Part(kind: .embeddedFile, depth: 1),
                                                       Part(kind: .script, depth: 2, malicious: true)])
        _ = apply(.sandbox, level: 2, to: &nested)
        #expect(nested.hasMalicious, "level 2 sees one layer down only")
        _ = apply(.sandbox, level: 3, to: &nested)
        #expect(!nested.hasMalicious)

        var locked = FileItem(container: .zip, parts: [Part(kind: .macro, malicious: true)], encrypted: true)
        _ = apply(.sandbox, level: 3, to: &locked)
        #expect(locked.hasMalicious)

        var poly = FileItem(container: .pdf, parts: [Part(kind: .text), Part(kind: .script, depth: 1, malicious: true)], polyglot: true)
        _ = apply(.sandbox, level: 3, to: &poly)
        #expect(poly.hasMalicious, "the second identity stays hidden from the sandbox")
    }

    @Test func forensicsRejectsAnyTransformerPass() {
        let policy = Policy.forCustomer(.forensicsLab)
        var viaTransformer = FileItem(container: .png, parts: [Part(kind: .image), Part(kind: .unknown, malicious: true, signatureKnown: false)])
        _ = apply(.parser, to: &viaTransformer)
        _ = apply(.transformer, level: 3, to: &viaTransformer)
        _ = apply(.packager, to: &viaTransformer)
        let bad = DeliveryEvaluator.evaluate(viaTransformer, policy: policy, payPerFile: 100)
        #expect(!bad.breach && !bad.accepted)

        var viaSandbox = FileItem(container: .png, parts: [Part(kind: .image), Part(kind: .unknown, malicious: true, signatureKnown: false)])
        _ = apply(.sandbox, to: &viaSandbox)
        #expect(DeliveryEvaluator.evaluate(viaSandbox, policy: policy, payPerFile: 100).accepted)
    }

    @Test func sandboxOnlyAvailableInTheDataCenter() {
        for kind in LocationKind.allCases {
            #expect(kind.spec.availableModules.contains(.sandbox) == (kind == .dataCenter))
        }
        var s = GameState(seed: 1)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 10_000
        #expect(s.placeModule(.sandbox, at: GridPos(1, 1), facing: .right).error == .notAvailableHere)
    }

    // MARK: - İlerleme

    func lay(_ s: inout GameState, path: [GridPos], modules: [GridPos: (ModuleKind, PartKind?)]) {
        for (i, p) in path.enumerated() {
            let next = i + 1 < path.count ? path[i + 1] : s.location.sinkPos
            let dir = Direction.from(dx: next.x - p.x, dy: next.y - p.y) ?? .down
            if let (kind, target) = modules[p] {
                let r = s.placeModule(kind, at: p, facing: dir)
                #expect(r.isSuccess, "\(kind) @\(p): \(String(describing: r.error))")
                if let target { s.configure(at: p) { $0.filterTarget = target } }
            } else {
                #expect(s.placeBelt(at: p, facing: dir).isSuccess)
            }
        }
    }

    struct Report { var seconds = 0.0; var delivered = 0; var breaches = 0; var complaints = 0; var late = 0 }

    func play(_ s: inout GameState, maxSeconds: Double) -> Report {
        var sim = Simulation(seed: 99)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        var events: [GameEvent] = []
        var r = Report()
        let dt = 1.0 / 20.0
        while r.seconds < maxSeconds {
            events.removeAll()
            sim.tick(dt: dt, state: &s, events: &events)
            r.seconds += dt
            var done = false
            for e in events {
                switch e {
                case .delivered(_, let o):
                    r.delivered += 1
                    if o.issues.contains(.late) { r.late += 1 }
                    if o.breach { r.breaches += 1 } else if !o.accepted { r.complaints += 1 }
                case .contractCompleted: done = true
                default: break
                }
            }
            if done { break }
        }
        return r
    }

    func dataCenter(index: Int) -> GameState {
        var s = GameState(seed: 21)
        s.xp = 100_000 // seviye kilitleri bu testin konusu değil
        s.money = 1_000_000; s.reputation = 1000
        for kind in LocationKind.allCases { _ = s.unlockLocation(kind) }
        #expect(s.switchLocation(.dataCenter).isSuccess)
        s.progress.index = index
        s.beltLevel = 3
        return s
    }

    @Test func forensicsLabNeedsTheSandbox() {
        let column = (1...13).map { GridPos(5, $0) }
        var good = dataCenter(index: 1)
        #expect(good.activeContract.customer == .forensicsLab)
        good.moduleLevels[.sandbox] = 3; good.moduleLevels[.parser] = 3
        lay(&good, path: column, modules: [
            GridPos(5, 1): (.sandbox, nil), GridPos(5, 2): (.parser, nil), GridPos(5, 3): (.filter, .macro),
            GridPos(5, 4): (.filter, .script), GridPos(5, 5): (.packager, nil),
        ])
        let ok = play(&good, maxSeconds: 2400)
        print("ADLİ BİLİŞİM kum havuzu: \(Int(ok.seconds))sn, teslim \(ok.delivered), ihlal \(ok.breaches), şikayet \(ok.complaints)")
        #expect(ok.breaches == 0)
        #expect(ok.complaints == 0)
        #expect(ok.delivered >= 70)

        var bad = dataCenter(index: 1)
        bad.moduleLevels[.transformer] = 3; bad.moduleLevels[.parser] = 3
        lay(&bad, path: column, modules: [
            GridPos(5, 1): (.parser, nil), GridPos(5, 2): (.filter, .macro), GridPos(5, 3): (.filter, .script),
            GridPos(5, 4): (.transformer, nil), GridPos(5, 5): (.packager, nil),
        ])
        let r = play(&bad, maxSeconds: 900)
        print("ADLİ BİLİŞİM dönüştürücü: ihlal \(r.breaches), şikayet \(r.complaints) / \(r.delivered)")
        #expect(r.breaches == 0)
        #expect(r.complaints > r.delivered / 3, "every image passed through the transformer is a complaint")
    }

    /// Hyperscale (60 dosya/dk) tek hattın sığasını aşar: dosyalar girişte birikir, geç teslim şikâyetleri gelir.
    @Test func hyperscaleSingleLineFallsBehind() {
        var s = dataCenter(index: 2)
        #expect(s.activeContract.tier == 6)
        s.moduleLevels[.sandbox] = 3; s.moduleLevels[.parser] = 3; s.moduleLevels[.transformer] = 3
        s.moduleLevels[.filter] = 3; s.moduleLevels[.packager] = 3
        s.intakeLevel = 1
        let column = (1...13).map { GridPos(5, $0) }
        lay(&s, path: column, modules: [
            GridPos(5, 1): (.router, nil), GridPos(5, 2): (.sandbox, nil), GridPos(5, 3): (.parser, nil),
            GridPos(5, 4): (.filter, .macro), GridPos(5, 5): (.filter, .script), GridPos(5, 6): (.filter, .embeddedFile),
            GridPos(5, 7): (.packager, nil),
        ])
        s.configure(at: GridPos(5, 1)) { $0.routeEncrypted = true }
        #expect(s.placeModule(.quarantine, at: GridPos(5, 1).moved(Direction.down.clockwise), facing: .down).isSuccess)
        let r = play(&s, maxSeconds: 3600)
        print("HYPERSCALE tek hat: \(Int(r.seconds))sn, teslim \(r.delivered), ihlal \(r.breaches), şikayet \(r.complaints)")
        #expect(r.breaches == 0)
        #expect(r.complaints > 10, "single line cannot keep up: late deliveries")
        #expect(r.late > 10, "complaints are about lateness, not security")
    }

    /// Ayırıcı ile iki paralel kol: aynı talep, sıfır şikâyet.
    @Test func hyperscaleParallelLinesSurvive() {
        var s = dataCenter(index: 2)
        s.moduleLevels[.sandbox] = 3; s.moduleLevels[.parser] = 3; s.moduleLevels[.transformer] = 3
        s.moduleLevels[.filter] = 3; s.moduleLevels[.packager] = 3
        s.intakeLevel = 1
        #expect(s.placeModule(.router, at: GridPos(5, 1), facing: .down).isSuccess)
        s.configure(at: GridPos(5, 1)) { $0.routeEncrypted = true }
        #expect(s.placeModule(.quarantine, at: GridPos(4, 1), facing: .down).isSuccess)
        #expect(s.placeModule(.splitter, at: GridPos(5, 2), facing: .down).isSuccess) // düz (5,3), yan (4,2)
        let line: (Int) -> [GridPos: (ModuleKind, PartKind?)] = { x in [
            GridPos(x, 3): (.sandbox, nil), GridPos(x, 4): (.parser, nil), GridPos(x, 5): (.filter, .macro),
            GridPos(x, 6): (.filter, .script), GridPos(x, 7): (.filter, .embeddedFile), GridPos(x, 8): (.packager, nil),
        ] }
        lay(&s, path: (3...13).map { GridPos(5, $0) }, modules: line(5))
        lay(&s, path: [GridPos(4, 2)] + (3...13).map { GridPos(4, $0) } + [GridPos(5, 13)], modules: line(4))
        let r = play(&s, maxSeconds: 3600)
        print("HYPERSCALE paralel: \(Int(r.seconds))sn, teslim \(r.delivered), ihlal \(r.breaches), şikayet \(r.complaints)")
        #expect(r.breaches == 0)
        #expect(r.complaints == 0)
        #expect(r.delivered >= 150)
    }
}

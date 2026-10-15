import Testing
@testable import DisarmCore

@Suite struct ModuleProcessorTests {
    func file(_ parts: [Part], container: ContainerKind = .docx, polyglot: Bool = false) -> FileItem {
        FileItem(container: container, parts: parts, polyglot: polyglot)
    }

    @Test func scannerRemovesKnownThreatsOnClosedFile() {
        var f = file([Part(kind: .text), Part(kind: .macro, malicious: true)])
        let notes = ModuleProcessor.apply(Module(kind: .scanner, facing: .right), level: 1, airGapped: false, to: &f)
        #expect(!f.hasMalicious)
        #expect(notes == [.removed(.macro, count: 1)])
        #expect(!f.isOpen)
    }

    @Test func scannerMissesUnknownAndNested() {
        var f = file([Part(kind: .unknown, malicious: true, signatureKnown: false),
                      Part(kind: .script, depth: 1, malicious: true)], container: .zip)
        _ = ModuleProcessor.apply(Module(kind: .scanner, facing: .right), level: 1, airGapped: false, to: &f)
        #expect(f.maliciousCount == 2)
        _ = ModuleProcessor.apply(Module(kind: .scanner, facing: .right), level: 2, airGapped: false, to: &f)
        #expect(f.maliciousCount == 1) // seviye 2 bir kat içeri bakar, bilinmeyen yine kalır
    }

    @Test func scannerAirGappedOnlyKnowsMacros() {
        var f = file([Part(kind: .macro, malicious: true), Part(kind: .script, malicious: true)])
        _ = ModuleProcessor.apply(Module(kind: .scanner, facing: .right), level: 3, airGapped: true, to: &f)
        #expect(f.parts.map(\.kind) == [.script])
    }

    @Test func filterRequiresOpenFile() {
        var f = file([Part(kind: .macro, malicious: true)])
        let m = Module(kind: .filter, facing: .right, config: ModuleConfig(filterTarget: .macro))
        let closedNotes = ModuleProcessor.apply(m, level: 1, airGapped: false, to: &f)
        #expect(f.hasMalicious)
        #expect(closedNotes.count == 1)
        _ = ModuleProcessor.apply(Module(kind: .parser, facing: .right), level: 1, airGapped: false, to: &f)
        #expect(f.isOpen)
        _ = ModuleProcessor.apply(m, level: 1, airGapped: false, to: &f)
        #expect(!f.hasMalicious)
    }

    @Test func parserDepthGatesNestedThreats() {
        var f = file([Part(kind: .embeddedFile), Part(kind: .macro, depth: 1, malicious: true)], container: .zip)
        let filter = Module(kind: .filter, facing: .right, config: ModuleConfig(filterTarget: .macro))
        _ = ModuleProcessor.apply(Module(kind: .parser, facing: .right), level: 1, airGapped: false, to: &f)
        _ = ModuleProcessor.apply(filter, level: 1, airGapped: false, to: &f)
        #expect(f.hasMalicious)
        _ = ModuleProcessor.apply(Module(kind: .parser, facing: .right), level: 2, airGapped: false, to: &f)
        _ = ModuleProcessor.apply(filter, level: 1, airGapped: false, to: &f)
        #expect(!f.hasMalicious)
    }

    @Test func polyglotNeedsLevelThreeParser() {
        var f = file([Part(kind: .text), Part(kind: .script, depth: 1, malicious: true)], container: .pdf, polyglot: true)
        let notes = ModuleProcessor.apply(Module(kind: .parser, facing: .right), level: 2, airGapped: false, to: &f)
        #expect(notes.contains(.polyglotUnhandled))
        #expect(f.exposedDepth == 0)
        _ = ModuleProcessor.apply(Module(kind: .parser, facing: .right), level: 3, airGapped: false, to: &f)
        #expect(f.exposedDepth == 2)
    }

    @Test func transformerTradeoffs() {
        var f = file([Part(kind: .image), Part(kind: .formula), Part(kind: .hiddenData, malicious: true)], container: .xlsx)
        _ = ModuleProcessor.apply(Module(kind: .parser, facing: .right), level: 1, airGapped: false, to: &f)
        _ = ModuleProcessor.apply(Module(kind: .transformer, facing: .right), level: 1, airGapped: false, to: &f)
        #expect(!f.hasMalicious)
        #expect(!f.kinds.contains(.formula)) // seviye 1 formülleri düzleştirir
        #expect(abs(f.imageQuality - 0.6) < 0.001)

        var g = file([Part(kind: .image), Part(kind: .formula), Part(kind: .unknown, malicious: true, signatureKnown: false)], container: .xlsx)
        _ = ModuleProcessor.apply(Module(kind: .parser, facing: .right), level: 1, airGapped: false, to: &g)
        _ = ModuleProcessor.apply(Module(kind: .transformer, facing: .right), level: 3, airGapped: false, to: &g)
        #expect(!g.hasMalicious)
        #expect(g.kinds.contains(.formula))
        #expect(g.imageQuality >= 0.95 - 0.001)
    }

    @Test func packagerCloses() {
        var f = file([Part(kind: .text)])
        _ = ModuleProcessor.apply(Module(kind: .parser, facing: .right), level: 1, airGapped: false, to: &f)
        _ = ModuleProcessor.apply(Module(kind: .packager, facing: .right), level: 1, airGapped: false, to: &f)
        #expect(!f.isOpen && f.exposedDepth == -1)
    }
}

@Suite struct DeliveryTests {
    @Test func breachIsExpensive() {
        let f = FileItem(container: .docx, parts: [Part(kind: .macro, malicious: true)])
        let o = DeliveryEvaluator.evaluate(f, policy: .forCustomer(.bank), payPerFile: 10)
        #expect(o.breach && o.pay == -30 && o.reputationDelta < 0)
    }

    @Test func openFileIsUnusable() {
        var f = FileItem(container: .pdf, parts: [Part(kind: .text)])
        f.isOpen = true
        let o = DeliveryEvaluator.evaluate(f, policy: .forCustomer(.lawFirm), payPerFile: 10)
        #expect(o.pay == 0 && !o.breach)
    }

    @Test func accountingWantsFormulasKept() {
        var f = FileItem(container: .xlsx, parts: [Part(kind: .formula), Part(kind: .macro)])
        f.parts.removeAll { $0.kind == .formula } // dönüştürücü düzleştirdi
        f.parts.removeAll { $0.kind == .macro }
        let o = DeliveryEvaluator.evaluate(f, policy: .forCustomer(.accounting), payPerFile: 10)
        #expect(o.usability < 0.9)
        #expect(o.issues.contains(.mustKeepLost(.formula)))
    }

    @Test func bankRejectsBenignMacro() {
        let f = FileItem(container: .xlsx, parts: [Part(kind: .formula), Part(kind: .macro)])
        let o = DeliveryEvaluator.evaluate(f, policy: .forCustomer(.bank), payPerFile: 10)
        #expect(!o.breach && o.usability < 0.9)
    }

    @Test func designAgencyCaresAboutQuality() {
        var f = FileItem(container: .png, parts: [Part(kind: .image)])
        f.imageQuality = 0.6
        let o = DeliveryEvaluator.evaluate(f, policy: .forCustomer(.designAgency), payPerFile: 10)
        #expect(o.usability < 0.9)
        f.imageQuality = 0.95
        #expect(DeliveryEvaluator.evaluate(f, policy: .forCustomer(.designAgency), payPerFile: 10).accepted)
    }
}

@Suite struct GeneratorTests {
    @Test func tierZeroHasNoThreats() {
        var rng = SplitMix64(seed: 1)
        var spec = LocationKind.smallOffice.spec.contracts[0]
        spec.tier = 0
        for _ in 0..<200 {
            #expect(!FileGenerator.make(for: spec, rng: &rng).hasMalicious)
        }
    }

    @Test func tierFiveProducesUnknowns() {
        var rng = SplitMix64(seed: 7)
        let spec = LocationKind.bank.spec.contracts[1]
        var unknowns = 0
        for _ in 0..<300 {
            let f = FileGenerator.make(for: spec, rng: &rng)
            if f.parts.contains(where: { $0.kind == .unknown }) { unknowns += 1 }
        }
        #expect(unknowns > 20)
    }

    @Test func deterministicWithSeed() {
        var a = SplitMix64(seed: 42), b = SplitMix64(seed: 42)
        let spec = LocationKind.company.spec.contracts[0]
        for _ in 0..<20 {
            let x = FileGenerator.make(for: spec, rng: &a), y = FileGenerator.make(for: spec, rng: &b)
            #expect(x.container == y.container && x.parts.map(\.kind) == y.parts.map(\.kind))
        }
    }
}

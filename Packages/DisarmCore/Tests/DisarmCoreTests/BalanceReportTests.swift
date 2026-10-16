import Foundation
import Testing
@testable import DisarmCore

/// Tüm kampanya için denge raporu: her mekânın "ders kitabı" hattı, o mekânın her sözleşmesini
/// ihlalsiz ve neredeyse şikayetsiz bitirebilmeli. Tabloyu basar; süre ve oranları sınırlar.
@Suite struct BalanceReportTests {
    struct Row {
        var location: String; var contract: String; var tier: Int
        var seconds: Double; var delivered: Int; var accepted: Int; var complaints: Int; var breaches: Int
        var quarantined: Int; var earned: Int
    }

    /// Mekânın tam yükseltilmiş ders kitabı hattı. Yol boyunca modüller; `rest` kalan hücreler bant.
    func textbook(_ kind: LocationKind, into s: inout GameState) {
        func lay(_ path: [GridPos], _ modules: [GridPos: (ModuleKind, PartKind?)]) {
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
        func routerToQuarantine(_ p: GridPos, facing: Direction) {
            s.configure(at: p) { $0.routeEncrypted = true }
            #expect(s.placeModule(.quarantine, at: p.moved(facing.clockwise), facing: .down).isSuccess)
        }
        func col(_ x: Int, _ ys: ClosedRange<Int>) -> [GridPos] { ys.map { GridPos(x, $0) } }
        func row(_ y: Int, _ xs: ClosedRange<Int>) -> [GridPos] { xs.map { GridPos($0, y) } }

        switch kind {
        case .smallOffice:
            lay(row(1, 1...5) + col(6, 1...7), [
                GridPos(1, 1): (.scanner, nil), GridPos(2, 1): (.parser, nil),
                GridPos(3, 1): (.filter, .macro), GridPos(4, 1): (.packager, nil),
            ])
        case .company:
            lay(col(3, 1...10) + [GridPos(4, 10)], [
                GridPos(3, 1): (.parser, nil), GridPos(3, 2): (.filter, .macro), GridPos(3, 3): (.filter, .script),
                GridPos(3, 4): (.filter, .embeddedFile), GridPos(3, 5): (.transformer, nil), GridPos(3, 6): (.packager, nil),
            ])
        case .bank:
            lay(row(6, 1...7), [
                GridPos(1, 6): (.router, nil), GridPos(2, 6): (.parser, nil), GridPos(3, 6): (.filter, .macro),
                GridPos(4, 6): (.filter, .script), GridPos(5, 6): (.filter, .embeddedFile),
                GridPos(6, 6): (.transformer, nil), GridPos(7, 6): (.packager, nil),
            ])
            routerToQuarantine(GridPos(1, 6), facing: .right)
        case .government:
            lay(col(0, 1...3) + row(3, 1...8) + col(8, 4...13), [
                GridPos(1, 3): (.router, nil), GridPos(2, 3): (.parser, nil), GridPos(3, 3): (.filter, .macro),
                GridPos(4, 3): (.filter, .script), GridPos(5, 3): (.filter, .embeddedFile),
                GridPos(6, 3): (.transformer, nil), GridPos(7, 3): (.packager, nil),
            ])
            routerToQuarantine(GridPos(1, 3), facing: .right)
        case .dataCenter:
            // 52 dosya/dk tek hattın sığası üstünde: yönlendirici→karantina, sonra ayırıcı ile iki paralel kol
            // (sütun 5 ve sütun 4), (5,13)'te birleşip teslimata.
            #expect(s.placeModule(.router, at: GridPos(5, 1), facing: .down).isSuccess)
            routerToQuarantine(GridPos(5, 1), facing: .down) // karantina (4,1)
            #expect(s.placeModule(.splitter, at: GridPos(5, 2), facing: .down).isSuccess) // düz (5,3), sağ = sol (4,2)
            let line: (Int) -> [GridPos: (ModuleKind, PartKind?)] = { x in [
                GridPos(x, 3): (.sandbox, nil), GridPos(x, 4): (.parser, nil), GridPos(x, 5): (.filter, .macro),
                GridPos(x, 6): (.filter, .script), GridPos(x, 7): (.filter, .embeddedFile), GridPos(x, 8): (.packager, nil),
            ] }
            lay(col(5, 3...13), line(5))
            lay([GridPos(4, 2)] + col(4, 3...13) + [GridPos(5, 13)], line(4))
        }
    }

    func play(_ s: inout GameState, maxSeconds: Double) -> Row {
        var sim = Simulation(seed: 77)
        sim.incidentsEnabled = false // krizler bu testin konusu değil
        var events: [GameEvent] = []
        var r = Row(location: s.location.displayName, contract: s.activeContract.title, tier: s.activeContract.tier,
                    seconds: 0, delivered: 0, accepted: 0, complaints: 0, breaches: 0, quarantined: 0, earned: 0)
        let startMoney = s.money
        let dt = 1.0 / 20.0
        var done = false
        while r.seconds < maxSeconds && !done {
            events.removeAll()
            sim.tick(dt: dt, state: &s, events: &events)
            r.seconds += dt
            for e in events {
                switch e {
                case .delivered(_, let o):
                    r.delivered += 1
                    if o.breach { r.breaches += 1 } else if o.accepted { r.accepted += 1 } else { r.complaints += 1 }
                case .quarantined: r.quarantined += 1
                case .contractCompleted: done = true
                default: break
                }
            }
        }
        r.earned = s.money - startMoney
        return r
    }

    @Test func everyContractIsBeatableWithTheTextbookLine() {
        var rows: [Row] = []
        for kind in LocationKind.allCases {
            for (i, spec) in kind.spec.contracts.enumerated() {
                var s = GameState(seed: 100 + UInt64(i))
                s.money = 1_000_000; s.reputation = 10_000
                s.xp = 100_000 // tam yükseltilmiş hat: seviye kilitleri bu testin konusu değil
                s.tutorialSeen = true
                for k in LocationKind.allCases { _ = s.unlockLocation(k) }
                #expect(s.switchLocation(kind).isSuccess)
                for m in ModuleKind.allCases where m.isPlaceable { s.moduleLevels[m] = m.maxLevel }
                s.beltLevel = 3
                textbook(kind, into: &s)
                s.progress.index = i
                let r = play(&s, maxSeconds: 1800)
                rows.append(r)
                #expect(r.breaches == 0, "\(spec.id): \(r.breaches) breaches")
                #expect(r.delivered >= spec.targetFiles, "\(spec.id): not completed in 30 min (\(r.delivered)/\(spec.targetFiles))")
                #expect(Double(r.complaints) <= Double(max(1, r.delivered)) * 0.05, "\(spec.id): \(r.complaints) complaints / \(r.delivered)")
            }
        }

        let total = rows.reduce(0.0) { $0 + $1.seconds }
        print("DENGE RAPORU (ders kitabı hattı, tüm modüller maks seviye, bant L3)")
        print(String(format: "%-14@ %-26@ %4@ %7@ %6@ %6@ %6@ %6@ %6@ %8@", "Mekân", "Sözleşme", "Tier", "Süre", "Tesl.", "Kabul", "Şik.", "İhlal", "Kar.", "Kazanç"))
        for r in rows {
            print(String(format: "%-14@ %-26@ %4d %6.0fs %6d %6d %6d %6d %6d %8d",
                         String(r.location.prefix(14)), String(r.contract.prefix(26)), r.tier, r.seconds, r.delivered, r.accepted, r.complaints, r.breaches, r.quarantined, r.earned))
        }
        print(String(format: "Toplam kampanya süresi (kesintisiz, maks seviye): %.0f dk", total / 60))
    }
}

import SpriteKit
import UIKit
import DisarmCore

@MainActor
final class GameScene: SKScene {
    weak var engine: GameEngine?

    private var cs: CGFloat = 40
    private var origin = CGPoint.zero
    private var gridW = 1
    private var gridH = 1
    private var renderedLayoutVersion = -1
    private var lastTime: TimeInterval?

    private let root = SKNode()
    private let boardLayer = SKNode()
    private let cellLayer = SKNode()
    private let itemLayer = SKNode()
    private let fxLayer = SKNode()
    private let overlayLayer = SKNode()
    private var itemNodes: [UUID: ItemNode] = [:]
    private var moduleNodes: [GridPos: SKNode] = [:]
    private var busyModules: Set<GridPos> = []
    private var knownCells: Set<GridPos> = []
    private var firstBuild = true
    private var particleTexture: SKTexture?
    private static var textureCache: [String: SKTexture] = [:]

    private var touchStartCell: GridPos?
    private var lastDragCell: GridPos?
    private var dragged = false
    private var lastTapTime: TimeInterval = 0

    override func didMove(to view: SKView) {
        backgroundColor = Theme.background
        scaleMode = .resizeFill
        boardLayer.zPosition = 0
        cellLayer.zPosition = 10
        itemLayer.zPosition = 20
        fxLayer.zPosition = 30
        overlayLayer.zPosition = 100
        addChild(root)
        root.addChild(boardLayer)
        root.addChild(cellLayer)
        root.addChild(itemLayer)
        root.addChild(fxLayer)
        addChild(overlayLayer)
        let dot = SKShapeNode(circleOfRadius: 6)
        dot.fillColor = .white
        dot.strokeColor = .clear
        particleTexture = view.texture(from: dot)
        relayout()
        AudioManager.shared.startMusic()
    }

    override func didChangeSize(_ oldSize: CGSize) {
        relayout()
    }

    // MARK: - Geometri

    private func relayout() {
        guard let engine else { return }
        let g = engine.state.grid
        gridW = g.width
        gridH = g.height
        let pad: CGFloat = 12
        cs = floor(min((size.width - pad * 2) / CGFloat(gridW), (size.height - pad * 2) / CGFloat(gridH)))
        origin = CGPoint(x: (size.width - cs * CGFloat(gridW)) / 2, y: (size.height - cs * CGFloat(gridH)) / 2)
        renderedLayoutVersion = -1
        itemNodes.values.forEach { $0.removeFromParent() }
        itemNodes.removeAll()
    }

    func point(for p: GridPos) -> CGPoint {
        CGPoint(x: origin.x + (CGFloat(p.x) + 0.5) * cs,
                y: origin.y + (CGFloat(gridH - 1 - p.y) + 0.5) * cs)
    }

    func cell(at pt: CGPoint) -> GridPos? {
        let x = Int(floor((pt.x - origin.x) / cs))
        let yFromBottom = Int(floor((pt.y - origin.y) / cs))
        let y = gridH - 1 - yFromBottom
        guard x >= 0, y >= 0, x < gridW, y < gridH else { return nil }
        return GridPos(x, y)
    }

    private func vector(_ d: Direction) -> CGVector {
        CGVector(dx: CGFloat(d.dx), dy: -CGFloat(d.dy))
    }

    // MARK: - Döngü

    override func update(_ currentTime: TimeInterval) {
        guard let engine else { return }
        let dt = lastTime.map { currentTime - $0 } ?? 0
        lastTime = currentTime
        engine.tick(dt: dt)

        if engine.state.grid.width != gridW || engine.state.grid.height != gridH {
            relayout()
        }
        if engine.layoutVersion != renderedLayoutVersion {
            rebuildCells()
            renderedLayoutVersion = engine.layoutVersion
        }
        syncItems()
        drainFx()
    }

    // MARK: - Hücreler

    private func rebuildCells() {
        guard let engine else { return }
        boardLayer.removeAllChildren()
        cellLayer.removeAllChildren()
        moduleNodes.removeAll()
        let g = engine.state.grid
        let spec = engine.state.location
        var nowCells: Set<GridPos> = []

        for p in g.allPositions {
            let bg = SKShapeNode(rectOf: CGSize(width: cs - 1, height: cs - 1), cornerRadius: 3)
            bg.fillColor = Theme.cellEmpty
            bg.strokeColor = Theme.gridLine
            bg.lineWidth = 1
            bg.position = point(for: p)
            boardLayer.addChild(bg)

            guard let cell = g[p] else { continue }
            let node: SKNode
            switch cell {
            case .belt(let d): node = makeBelt(d)
            case .module(let m): node = makeModule(m, level: engine.state.level(of: m.kind), airGapped: spec.airGapped)
            }
            node.position = point(for: p)
            cellLayer.addChild(node)
            nowCells.insert(p)
            if case .module = cell { moduleNodes[p] = node }
            if !firstBuild && !knownCells.contains(p) {
                node.setScale(0.4)
                node.run(.sequence([.scale(to: 1.12, duration: 0.12), .scale(to: 1.0, duration: 0.08)]))
            }
        }
        knownCells = nowCells
        firstBuild = false
    }

    private func makeBelt(_ d: Direction) -> SKNode {
        let n = SKNode()
        let base = SKShapeNode(rectOf: CGSize(width: cs - 2, height: cs - 2), cornerRadius: 4)
        base.fillColor = Theme.belt
        base.strokeColor = .clear
        let outer = SKNode()
        outer.addChild(base)
        let crop = SKCropNode()
        let maskNode = SKShapeNode(rectOf: CGSize(width: cs - 6, height: cs - 6), cornerRadius: 3)
        maskNode.fillColor = .white
        crop.maskNode = maskNode
        crop.addChild(n)
        outer.addChild(crop)
        // İki chevron, yarım faz farkıyla yukarı akar: bant hareket ediyor hissi.
        let span = cs * 0.5
        for i in 0..<2 {
            let chev = chevron(size: cs * 0.2)
            let phase = CGFloat(i) * 0.5
            chev.position = CGPoint(x: 0, y: -span / 2 + span * phase)
            chev.alpha = 0.6
            let flow = SKAction.sequence([
                .moveBy(x: 0, y: span * (1 - phase), duration: 0.7 * Double(1 - phase)),
                .moveTo(y: -span / 2, duration: 0),
                .repeatForever(.sequence([.moveBy(x: 0, y: span, duration: 0.7), .moveTo(y: -span / 2, duration: 0)])),
            ])
            chev.run(flow)
            n.addChild(chev)
        }

        outer.zRotation = -CGFloat(d.angle)
        return outer
    }

    private func chevron(size s: CGFloat) -> SKShapeNode {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -s, y: -s * 0.5))
        path.addLine(to: CGPoint(x: 0, y: s * 0.5))
        path.addLine(to: CGPoint(x: s, y: -s * 0.5))
        let n = SKShapeNode(path: path)
        n.strokeColor = Theme.beltArrow
        n.lineWidth = max(2, cs * 0.08)
        n.lineCap = .round
        n.lineJoin = .round
        return n
    }

    private func makeModule(_ m: Module, level: Int, airGapped: Bool) -> SKNode {
        let n = SKNode()
        let color = Theme.color(m.kind)
        let body = SKShapeNode(rectOf: CGSize(width: cs - 3, height: cs - 3), cornerRadius: cs * 0.18)
        body.fillColor = color.withAlphaComponent(0.28)
        body.strokeColor = color
        body.lineWidth = 2
        body.name = "body"
        n.addChild(body)

        if let tex = Self.texture(symbol: Theme.symbol(m.kind), size: cs * 0.5) {
            let icon = SKSpriteNode(texture: tex)
            icon.size = CGSize(width: cs * 0.46, height: cs * 0.46)
            icon.position = CGPoint(x: 0, y: cs * 0.08)
            icon.color = color
            icon.colorBlendFactor = 1
            icon.name = "icon"
            n.addChild(icon)
        }
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.fontSize = cs * 0.17
        label.fontColor = UIColor(white: 1, alpha: 0.9)
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -cs * 0.32)
        switch m.kind {
        case .filter: label.text = m.config.filterTarget.displayName.uppercased()
        case .router: label.text = m.config.routeEncrypted ? String(localized: "LOCK") : m.config.routeTarget.displayName
        default: label.text = m.kind.shortName
        }
        n.addChild(label)

        if level > 1 {
            let badge = SKLabelNode(fontNamed: "AvenirNext-Bold")
            badge.text = "L\(level)"
            badge.fontSize = cs * 0.16
            badge.fontColor = Theme.warning
            badge.verticalAlignmentMode = .center
            badge.horizontalAlignmentMode = .right
            badge.position = CGPoint(x: cs * 0.42, y: cs * 0.36)
            n.addChild(badge)
        }
        if m.kind == .scanner && airGapped {
            let x = SKLabelNode(fontNamed: "AvenirNext-Bold")
            x.text = "✕"
            x.fontSize = cs * 0.3
            x.fontColor = Theme.danger
            x.verticalAlignmentMode = .center
            x.position = CGPoint(x: -cs * 0.3, y: cs * 0.3)
            n.addChild(x)
        }

        // Çıkış oku.
        if m.kind != .sink && m.kind != .quarantine {
            n.addChild(outputArrow(m.facing, color: color))
            if m.kind == .router { n.addChild(outputArrow(m.facing.clockwise, color: Theme.warning)) }
        }
        return n
    }

    private func outputArrow(_ d: Direction, color: UIColor) -> SKShapeNode {
        let s = cs * 0.14
        let path = CGMutablePath()
        path.move(to: CGPoint(x: -s, y: 0))
        path.addLine(to: CGPoint(x: 0, y: s))
        path.addLine(to: CGPoint(x: s, y: 0))
        path.closeSubpath()
        let n = SKShapeNode(path: path)
        n.fillColor = color
        n.strokeColor = .clear
        let v = vector(d)
        n.position = CGPoint(x: v.dx * cs * 0.44, y: v.dy * cs * 0.44)
        n.zRotation = -CGFloat(d.angle)
        return n
    }

    static func texture(symbol: String, size: CGFloat) -> SKTexture? {
        let key = "\(symbol)-\(Int(size))"
        if let t = textureCache[key] { return t }
        let cfg = UIImage.SymbolConfiguration(pointSize: size * 2, weight: .semibold)
        guard let sym = UIImage(systemName: symbol, withConfiguration: cfg) else { return nil }
        // Sembolü beyaz bitmap olarak çiz; SpriteKit sonra colorBlendFactor ile boyar.
        let side = max(sym.size.width, sym.size.height)
        let canvas = CGSize(width: side, height: side)
        let img = UIGraphicsImageRenderer(size: canvas).image { _ in
            UIColor.white.set()
            let origin = CGPoint(x: (side - sym.size.width) / 2, y: (side - sym.size.height) / 2)
            sym.withTintColor(.white, renderingMode: .alwaysTemplate)
                .draw(in: CGRect(origin: origin, size: sym.size))
        }
        let t = SKTexture(image: img)
        textureCache[key] = t
        return t
    }

    // MARK: - Dosyalar

    private func syncItems() {
        guard let engine else { return }
        var seen: Set<UUID> = []
        var busy: Set<GridPos> = []
        for item in engine.sim.items {
            seen.insert(item.id)
            if item.inModule { busy.insert(item.pos) }
            let node: ItemNode
            if let existing = itemNodes[item.id] {
                node = existing
            } else {
                node = ItemNode()
                itemNodes[item.id] = node
                itemLayer.addChild(node)
            }
            node.configure(item.file, cs: cs)
            let base = point(for: item.pos)
            if item.inModule {
                node.position = CGPoint(x: base.x, y: base.y + cs * 0.04)
                node.setScale(0.8)
                node.setProgress(item.progress)
                node.zPosition = 1
            } else {
                let v = vector(item.heading)
                let off = CGFloat(item.progress - 0.5) * cs
                node.position = CGPoint(x: base.x + v.dx * off, y: base.y + v.dy * off)
                node.setScale(1)
                node.setProgress(nil)
                node.zPosition = 0
            }
        }
        for (id, node) in itemNodes where !seen.contains(id) {
            node.removeFromParent()
            itemNodes[id] = nil
        }
        // Çalışan modül: parlama ve ikon nabzı.
        for p in busy.subtracting(busyModules) {
            guard let n = moduleNodes[p] else { continue }
            (n.childNode(withName: "body") as? SKShapeNode)?.glowWidth = cs * 0.07
            n.childNode(withName: "icon")?.run(.repeatForever(.sequence([.scale(to: 1.15, duration: 0.25), .scale(to: 1.0, duration: 0.25)])), withKey: "pulse")
        }
        for p in busyModules.subtracting(busy) {
            guard let n = moduleNodes[p] else { continue }
            (n.childNode(withName: "body") as? SKShapeNode)?.glowWidth = 0
            n.childNode(withName: "icon")?.removeAction(forKey: "pulse")
            n.childNode(withName: "icon")?.setScale(1)
        }
        busyModules = busy
    }

    private func drainFx() {
        guard let engine, !engine.fx.isEmpty else { return }
        let events = engine.fx
        engine.fx.removeAll()
        let sinkPt = point(for: engine.state.location.sinkPos)
        for e in events {
            switch e {
            case .processed(let pos, let text, let removed):
                floatLabel(text, at: point(for: pos), color: removed ? Theme.danger : Theme.accent, size: cs * 0.2, rise: cs * 0.6, duration: 0.9)
            case .delivered(let pay, let good):
                let text = pay >= 0 ? "+\(money(pay))" : money(pay)
                floatLabel(text, at: CGPoint(x: sinkPt.x, y: sinkPt.y + cs * 0.45), color: good ? Theme.success : (pay < 0 ? Theme.danger : Theme.warning), size: cs * 0.3, rise: cs * 1.1, duration: 1.0)
                if good { burst(at: sinkPt, color: Theme.success, count: 14, speed: cs * 2.2) }
            case .breach:
                burst(at: sinkPt, color: Theme.danger, count: 24, speed: cs * 3.5)
                let ring = SKShapeNode(circleOfRadius: cs * 0.5)
                ring.strokeColor = Theme.danger
                ring.lineWidth = 3
                ring.fillColor = Theme.danger.withAlphaComponent(0.25)
                ring.position = sinkPt
                fxLayer.addChild(ring)
                ring.run(.sequence([.group([.scale(to: 2.4, duration: 0.6), .fadeOut(withDuration: 0.6)]), .removeFromParent()]))
                shake(amplitude: cs * 0.18)
                flash(Theme.danger.withAlphaComponent(0.22))
            case .contractCompleted:
                confetti()
                flash(Theme.success.withAlphaComponent(0.12))
            case .campaignCompleted:
                confetti()
                run(.sequence([.wait(forDuration: 0.5), .run { [weak self] in self?.confetti() },
                               .wait(forDuration: 0.5), .run { [weak self] in self?.confetti() }]))
                flash(Theme.warning.withAlphaComponent(0.2))
            case .contractFailed:
                shake(amplitude: cs * 0.3)
                flash(Theme.danger.withAlphaComponent(0.3))
            }
        }
    }

    private func floatLabel(_ text: String, at p: CGPoint, color: UIColor, size: CGFloat, rise: CGFloat, duration: Double) {
        let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
        label.text = text
        label.fontSize = size
        label.fontColor = color
        label.position = p
        label.zPosition = 5
        label.setScale(0.6)
        fxLayer.addChild(label)
        label.run(.sequence([
            .group([.scale(to: 1, duration: 0.12), .moveBy(x: 0, y: rise, duration: duration),
                    .sequence([.wait(forDuration: duration * 0.5), .fadeOut(withDuration: duration * 0.5)])]),
            .removeFromParent(),
        ]))
    }

    private func burst(at p: CGPoint, color: UIColor, count: Int, speed: CGFloat) {
        guard let particleTexture else { return }
        let e = SKEmitterNode()
        e.particleTexture = particleTexture
        e.position = p
        e.zPosition = 4
        e.numParticlesToEmit = count
        e.particleBirthRate = 400
        e.particleLifetime = 0.6
        e.particleLifetimeRange = 0.3
        e.particleSpeed = speed
        e.particleSpeedRange = speed * 0.5
        e.emissionAngleRange = .pi * 2
        e.particleScale = cs * 0.012
        e.particleScaleSpeed = -cs * 0.012
        e.particleAlphaSpeed = -1.2
        e.particleColor = color
        e.particleColorBlendFactor = 1
        e.yAcceleration = -speed * 1.2
        fxLayer.addChild(e)
        e.run(.sequence([.wait(forDuration: 1.2), .removeFromParent()]))
    }

    private func confetti() {
        guard let particleTexture else { return }
        let e = SKEmitterNode()
        e.particleTexture = particleTexture
        e.position = CGPoint(x: size.width / 2, y: size.height + 10)
        e.particlePositionRange = CGVector(dx: size.width, dy: 0)
        e.zPosition = 6
        e.numParticlesToEmit = 120
        e.particleBirthRate = 150
        e.particleLifetime = 2.2
        e.particleSpeed = 60
        e.particleSpeedRange = 40
        e.emissionAngle = -.pi / 2
        e.emissionAngleRange = 0.6
        e.yAcceleration = -160
        e.particleScale = cs * 0.014
        e.particleScaleRange = cs * 0.006
        e.particleRotationSpeed = 4
        e.particleRotationRange = .pi
        e.particleAlphaSpeed = -0.4
        e.particleColorSequence = SKKeyframeSequence(keyframeValues: [Theme.success, Theme.accent, Theme.warning, UIColor.white], times: [0, 0.33, 0.66, 1])
        e.particleColorBlendFactor = 1
        fxLayer.addChild(e)
        e.run(.sequence([.wait(forDuration: 3.5), .removeFromParent()]))
    }

    private func shake(amplitude: CGFloat) {
        root.removeAction(forKey: "shake")
        var actions: [SKAction] = []
        var a = amplitude
        for _ in 0..<6 {
            let dx = CGFloat.random(in: -a...a), dy = CGFloat.random(in: -a...a)
            actions.append(.moveBy(x: dx, y: dy, duration: 0.03))
            actions.append(.moveBy(x: -dx, y: -dy, duration: 0.03))
            a *= 0.7
        }
        actions.append(.move(to: .zero, duration: 0))
        root.run(.sequence(actions), withKey: "shake")
    }

    private func flash(_ color: UIColor) {
        let f = SKSpriteNode(color: color, size: size)
        f.position = CGPoint(x: size.width / 2, y: size.height / 2)
        overlayLayer.addChild(f)
        f.run(.sequence([.fadeOut(withDuration: 0.35), .removeFromParent()]))
    }

    private func itemHit(_ pt: CGPoint) -> UUID? {
        var best: (UUID, CGFloat)?
        for (id, node) in itemNodes {
            let d = hypot(node.position.x - pt.x, node.position.y - pt.y)
            if d < cs * 0.45, best == nil || d < best!.1 { best = (id, d) }
        }
        return best?.0
    }

    // MARK: - Dokunma

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let engine, let t = touches.first else { return }
        let pt = t.location(in: self)
        dragged = false
        if engine.tool == .select, let id = itemHit(pt) {
            engine.itemTapped(id)
            touchStartCell = nil
            return
        }
        touchStartCell = cell(at: pt)
        lastDragCell = touchStartCell
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let engine, let t = touches.first, let c = cell(at: t.location(in: self)) else { return }
        guard let last = lastDragCell else { lastDragCell = c; return }
        guard c != last else { return }
        dragged = true
        switch engine.tool {
        case .belt:
            // Atlanan hücreleri Manhattan yoluyla doldur.
            var cur = last
            while cur != c {
                let next: GridPos
                if cur.x != c.x { next = GridPos(cur.x + (c.x > cur.x ? 1 : -1), cur.y) }
                else { next = GridPos(cur.x, cur.y + (c.y > cur.y ? 1 : -1)) }
                engine.dragBelt(from: cur, to: next)
                cur = next
            }
        case .erase:
            engine.dragErase(c)
        default:
            break
        }
        lastDragCell = c
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        defer { touchStartCell = nil; lastDragCell = nil; dragged = false }
        guard let engine, !dragged, let c = touchStartCell else { return }
        engine.tapped(c)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        touchStartCell = nil
        lastDragCell = nil
        dragged = false
    }
}

/// Bir dosyanın bant üzerindeki görünümü: kap + parça noktaları.
@MainActor
final class ItemNode: SKNode {
    private var signature = ""
    private var bar: SKShapeNode?
    private var barFill: SKShapeNode?
    private var cs: CGFloat = 0

    func configure(_ f: FileItem, cs: CGFloat) {
        let sig = "\(f.container.rawValue)|\(f.isOpen)|\(f.exposedDepth)|\(f.polyglot)|\(f.encrypted)|\(Int(f.imageQuality * 100))|" +
            f.parts.map { "\($0.kind.rawValue)\($0.depth)\($0.malicious ? "!" : "")" }.joined(separator: ",") + "|\(Int(cs))"
        guard sig != signature else { return }
        signature = sig
        self.cs = cs
        removeAllChildren()

        let w = cs * 0.5, h = cs * 0.6
        let color = Theme.color(f.container)
        let body = SKShapeNode(rectOf: CGSize(width: w, height: h), cornerRadius: cs * 0.06)
        body.fillColor = f.isOpen ? color.withAlphaComponent(0.55) : color
        body.strokeColor = f.isOpen ? .white : UIColor(white: 0, alpha: 0.5)
        body.lineWidth = f.isOpen ? 1.5 : 1
        addChild(body)

        let name = SKLabelNode(fontNamed: "AvenirNext-Bold")
        name.text = f.container.displayName
        name.fontSize = cs * 0.13
        name.fontColor = .white
        name.verticalAlignmentMode = .center
        name.position = CGPoint(x: 0, y: h * 0.28)
        addChild(name)

        if f.polyglot {
            let badge = SKShapeNode(circleOfRadius: cs * 0.08)
            badge.fillColor = Theme.color(.hiddenData)
            badge.strokeColor = .white
            badge.lineWidth = 1
            badge.position = CGPoint(x: -w * 0.5, y: h * 0.5)
            badge.zPosition = 2
            let l = SKLabelNode(fontNamed: "AvenirNext-Bold")
            l.text = "2"
            l.fontSize = cs * 0.11
            l.verticalAlignmentMode = .center
            badge.addChild(l)
            addChild(badge)
        }

        if f.encrypted {
            // Kilit: dosyanın sağ üst köşesinde sarı rozet, gövde koyulaşır.
            body.fillColor = color.withAlphaComponent(0.7)
            body.strokeColor = Theme.warning
            body.lineWidth = 1.5
            let badge = SKShapeNode(circleOfRadius: cs * 0.09)
            badge.fillColor = Theme.warning
            badge.strokeColor = UIColor(white: 0, alpha: 0.6)
            badge.lineWidth = 1
            badge.position = CGPoint(x: w * 0.5, y: h * 0.5)
            badge.zPosition = 2
            let shackle = SKShapeNode(rectOf: CGSize(width: cs * 0.06, height: cs * 0.06), cornerRadius: cs * 0.03)
            shackle.fillColor = .clear
            shackle.strokeColor = .black
            shackle.lineWidth = 1.2
            shackle.position = CGPoint(x: 0, y: cs * 0.03)
            badge.addChild(shackle)
            let lockBody = SKShapeNode(rectOf: CGSize(width: cs * 0.09, height: cs * 0.065), cornerRadius: cs * 0.012)
            lockBody.fillColor = .black
            lockBody.strokeColor = .clear
            lockBody.position = CGPoint(x: 0, y: -cs * 0.02)
            badge.addChild(lockBody)
            addChild(badge)
        }

        // Parça noktaları: en fazla 2 sıra × 4.
        let parts = Array(f.parts.prefix(8))
        let r = cs * 0.055
        let cols = 4
        for (i, p) in parts.enumerated() {
            let col = i % cols, row = i / cols
            let dot = SKShapeNode(circleOfRadius: r)
            let exposed = f.isExposed(p)
            let hiddenNested = p.depth > 0 && !exposed
            dot.fillColor = hiddenNested ? UIColor(white: 0.5, alpha: 0.5) : Theme.color(p.kind)
            dot.strokeColor = p.malicious && !hiddenNested ? Theme.danger : (exposed ? .white : .clear)
            dot.lineWidth = p.malicious ? 1.5 : 0.8
            dot.position = CGPoint(x: (CGFloat(col) - 1.5) * r * 2.4, y: -h * 0.12 - CGFloat(row) * r * 2.4)
            dot.zPosition = 1
            addChild(dot)
        }

        let bar = SKShapeNode(rectOf: CGSize(width: cs * 0.7, height: cs * 0.07), cornerRadius: 2)
        bar.fillColor = UIColor(white: 0, alpha: 0.5)
        bar.strokeColor = .clear
        bar.position = CGPoint(x: 0, y: -h * 0.5 - cs * 0.1)
        bar.isHidden = true
        addChild(bar)
        let fill = SKShapeNode(rectOf: CGSize(width: cs * 0.7, height: cs * 0.07), cornerRadius: 2)
        fill.fillColor = Theme.accent
        fill.strokeColor = .clear
        fill.position = CGPoint(x: -cs * 0.35, y: 0)
        bar.addChild(fill)
        self.bar = bar
        self.barFill = fill
    }

    func setProgress(_ p: Double?) {
        guard let bar, let barFill else { return }
        if let p {
            bar.isHidden = false
            barFill.xScale = max(0.01, CGFloat(p))
            barFill.position = CGPoint(x: -cs * 0.35 * (1 - CGFloat(p)), y: 0)
        } else {
            bar.isHidden = true
        }
    }
}

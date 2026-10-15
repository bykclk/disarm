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

    private let boardLayer = SKNode()
    private let cellLayer = SKNode()
    private let itemLayer = SKNode()
    private let fxLayer = SKNode()
    private var itemNodes: [UUID: ItemNode] = [:]
    private var shownOutcomes: Set<UUID> = []
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
        addChild(boardLayer)
        addChild(cellLayer)
        addChild(itemLayer)
        addChild(fxLayer)
        relayout()
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
        syncOutcomes()
    }

    // MARK: - Hücreler

    private func rebuildCells() {
        guard let engine else { return }
        boardLayer.removeAllChildren()
        cellLayer.removeAllChildren()
        let g = engine.state.grid
        let spec = engine.state.location

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
        }
    }

    private func makeBelt(_ d: Direction) -> SKNode {
        let n = SKNode()
        let base = SKShapeNode(rectOf: CGSize(width: cs - 2, height: cs - 2), cornerRadius: 4)
        base.fillColor = Theme.belt
        base.strokeColor = .clear
        n.addChild(base)
        for i in 0..<2 {
            let chev = chevron(size: cs * 0.22)
            chev.position = CGPoint(x: 0, y: CGFloat(i) * cs * 0.3 - cs * 0.15)
            chev.alpha = 0.6
            n.addChild(chev)
        }
        n.zRotation = -CGFloat(d.angle)
        return n
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
        n.addChild(body)

        if let tex = Self.texture(symbol: Theme.symbol(m.kind), size: cs * 0.5) {
            let icon = SKSpriteNode(texture: tex)
            icon.size = CGSize(width: cs * 0.46, height: cs * 0.46)
            icon.position = CGPoint(x: 0, y: cs * 0.08)
            icon.color = color
            icon.colorBlendFactor = 1
            n.addChild(icon)
        }
        let label = SKLabelNode(fontNamed: "AvenirNext-DemiBold")
        label.fontSize = cs * 0.17
        label.fontColor = UIColor(white: 1, alpha: 0.9)
        label.verticalAlignmentMode = .center
        label.position = CGPoint(x: 0, y: -cs * 0.32)
        switch m.kind {
        case .filter: label.text = m.config.filterTarget.displayName.uppercased()
        case .router: label.text = m.config.routeTarget.displayName
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
        for item in engine.sim.items {
            seen.insert(item.id)
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
    }

    private func syncOutcomes() {
        guard let engine else { return }
        let sinkPt = point(for: engine.state.location.sinkPos)
        for o in engine.recentOutcomes where !shownOutcomes.contains(o.id) {
            shownOutcomes.insert(o.id)
            let label = SKLabelNode(fontNamed: "AvenirNext-Bold")
            label.fontSize = cs * 0.3
            label.text = o.good ? "✓" : "✕"
            label.fontColor = o.good ? Theme.success : Theme.danger
            label.position = CGPoint(x: sinkPt.x, y: sinkPt.y + cs * 0.4)
            label.zPosition = 5
            fxLayer.addChild(label)
            label.run(.sequence([.group([.moveBy(x: 0, y: cs * 0.8, duration: 0.8), .fadeOut(withDuration: 0.8)]), .removeFromParent()]))
        }
        if shownOutcomes.count > 200 { shownOutcomes.removeAll() }
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
        let sig = "\(f.container.rawValue)|\(f.isOpen)|\(f.exposedDepth)|\(f.polyglot)|\(Int(f.imageQuality * 100))|" +
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

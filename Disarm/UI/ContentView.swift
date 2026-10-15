import SwiftUI
import SpriteKit
import DisarmCore

struct ContentView: View {
    @Bindable var engine: GameEngine
    @State private var scene: GameScene = {
        let s = GameScene()
        s.scaleMode = .resizeFill
        return s
    }()

    var body: some View {
        ZStack {
            Color(Theme.background).ignoresSafeArea()
            VStack(spacing: 0) {
                HUDView(engine: engine)
                GuidanceBanner(engine: engine)
                SpriteView(scene: scene, preferredFramesPerSecond: 60)
                    .onAppear { scene.engine = engine }
                    .overlay(alignment: .top) { ToastStack(toasts: engine.toasts) }
                PaletteView(engine: engine)
            }
        }
        .sheet(item: $engine.sheet) { kind in
            SheetRouter(engine: engine, kind: kind)
                .presentationDragIndicator(.visible)
                .preferredColorScheme(.dark)
        }
    }
}

// MARK: - HUD

struct HUDView: View {
    @Bindable var engine: GameEngine

    var body: some View {
        let s = engine.state
        let c = s.activeContract
        let p = s.progress
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Label(money(s.money), systemImage: "banknote")
                    .font(.system(.headline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(Theme.success))
                Label("\(s.reputation)", systemImage: "star.fill")
                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                    .foregroundStyle(Color(Theme.warning))
                Spacer()
                Button { engine.speed = engine.speed == 1 ? 2 : 1 } label: {
                    Text(engine.speed == 1 ? "1×" : "2×")
                        .font(.system(.caption, design: .rounded).weight(.bold))
                        .frame(width: 34, height: 28)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                Button { engine.paused.toggle() } label: {
                    Image(systemName: engine.paused ? "play.fill" : "pause.fill")
                        .frame(width: 34, height: 28)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
                Menu {
                    Button { engine.sheet = .upgrades } label: { Label("Upgrades", systemImage: "arrow.up.circle") }
                    Button { engine.sheet = .locations } label: { Label("Sites", systemImage: "map") }
                    Button { engine.sheet = .log } label: { Label("Event Log", systemImage: "list.bullet.rectangle") }
                    Button { engine.sheet = .help } label: { Label("How to Play", systemImage: "questionmark.circle") }
                    Divider()
                    Button(role: .destructive) { engine.clearLayout() } label: { Label("Clear Line", systemImage: "trash") }
                } label: {
                    Image(systemName: "line.3.horizontal")
                        .frame(width: 34, height: 28)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .foregroundStyle(.white)

            Button { engine.sheet = .contracts } label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: Theme.symbol(c.customer))
                        Text(c.title).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(s.location.displayName)" + (s.location.airGapped ? " · air-gap" : ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        ProgressView(value: Double(p.delivered), total: Double(c.targetFiles))
                            .tint(Color(Theme.accent))
                        Text("\(p.delivered)/\(c.targetFiles)")
                            .font(.caption.monospacedDigit())
                        Text("Breach \(p.breaches)/\(c.maxBreaches)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(p.breaches > 0 ? Color(Theme.danger) : .secondary)
                    }
                }
                .foregroundStyle(.white)
                .padding(8)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }
}

// MARK: - Palet

struct PaletteView: View {
    @Bindable var engine: GameEngine

    var body: some View {
        let s = engine.state
        VStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    toolButton(.select, "hand.point.up.left", String(localized: "Select"), nil)
                    toolButton(.belt, "arrow.right", String(localized: "Belt"), GameState.beltCost)
                    toolButton(.erase, "eraser", String(localized: "Erase"), nil)
                    Button { engine.brush = engine.brush.clockwise } label: {
                        VStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .rotationEffect(.radians(engine.brush.angle))
                                .font(.title3)
                                .frame(height: 24)
                            Text("Facing").font(.caption2)
                        }
                        .frame(width: 58, height: 56)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }
                    .foregroundStyle(.white)
                    Divider().frame(height: 40)
                    ForEach(s.location.availableModules, id: \.self) { kind in
                        moduleButton(kind)
                    }
                }
                .padding(.horizontal, 12)
            }
            Text(hint)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.bottom, 4)
        }
        .padding(.top, 6)
        .background(.black.opacity(0.3))
    }

    private var hint: String {
        switch engine.tool {
        case .select: String(localized: "Tap a module: settings · Tap a file: see contents · Tap a belt: rotate")
        case .belt: String(localized: "Tap: place belt · Drag: draw belts · Tap existing belt: rotate")
        case .erase: String(localized: "Tap or drag: remove (modules refund 50%)")
        case .place(let k): String(localized: "\(k.displayName): tap an empty cell · facing \(engine.brush.displayName) · tap same module: rotate")
        }
    }

    @ViewBuilder
    private func toolButton(_ tool: Tool, _ icon: String, _ title: String, _ cost: Int?) -> some View {
        let active = engine.tool == tool
        Button { engine.tool = tool } label: {
            VStack(spacing: 2) {
                Image(systemName: icon).font(.title3).frame(height: 24)
                Text(cost.map { "\(title) \(money($0))" } ?? title).font(.caption2)
            }
            .frame(width: 58, height: 56)
            .background(active ? Color(Theme.accent).opacity(0.35) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color(Theme.accent) : .clear, lineWidth: 1.5))
        }
        .foregroundStyle(.white)
    }

    @ViewBuilder
    private func moduleButton(_ kind: ModuleKind) -> some View {
        let active = engine.tool == .place(kind)
        let affordable = engine.state.money >= kind.baseCost
        let level = engine.state.level(of: kind)
        Button { engine.tool = .place(kind) } label: {
            VStack(spacing: 2) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: Theme.symbol(kind))
                        .font(.title3)
                        .foregroundStyle(Color(Theme.color(kind)))
                        .frame(width: 40, height: 24)
                    if level > 1 {
                        Text("L\(level)").font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color(Theme.warning))
                    }
                }
                Text(kind.displayName).font(.system(size: 9)).lineLimit(1)
                Text(money(kind.baseCost)).font(.system(size: 9)).foregroundStyle(affordable ? .secondary : Color(Theme.danger))
            }
            .frame(width: 70, height: 56)
            .background(active ? Color(Theme.color(kind)).opacity(0.3) : .white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color(Theme.color(kind)) : .clear, lineWidth: 1.5))
        }
        .foregroundStyle(.white)
        .opacity(affordable ? 1 : 0.6)
    }
}

// MARK: - Toast

struct ToastStack: View {
    var toasts: [Toast]
    var body: some View {
        VStack(spacing: 6) {
            ForEach(toasts) { t in
                Text(t.text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(color(t.style).opacity(0.9), in: Capsule())
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .padding(.top, 8)
        .animation(.easeOut(duration: 0.2), value: toasts)
        .allowsHitTesting(false)
    }

    func color(_ s: Toast.Style) -> Color {
        switch s {
        case .info: Color(Theme.accent).opacity(0.8)
        case .good: Color(Theme.success)
        case .bad: Color(Theme.danger)
        case .warn: Color(Theme.warning)
        }
    }
}

// MARK: - Yönlendirme

struct GuidanceBanner: View {
    @Bindable var engine: GameEngine

    var body: some View {
        if let step = engine.tutorialStep {
            HStack(alignment: .top, spacing: 8) {
                Text("\(step.rawValue + 1)/\(GameEngine.TutorialStep.allCases.count)")
                    .font(.caption.bold()).foregroundStyle(Color(Theme.accent))
                Text(step.text).font(.caption).foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color(Theme.accent).opacity(0.15))
            .transition(.opacity)
        } else if !engine.lineConnected {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Color(Theme.warning))
                Text("Line isn't connected to delivery: files will pile up or drop.").font(.caption).foregroundStyle(.white)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(Color(Theme.warning).opacity(0.15))
        }
    }
}

import SwiftUI
import DisarmCore

struct SheetRouter: View {
    @Bindable var engine: GameEngine
    var kind: SheetKind

    var body: some View {
        switch kind {
        case .contracts: ContractsView(engine: engine).presentationDetents([.medium, .large])
        case .upgrades: UpgradesView(engine: engine).presentationDetents([.large])
        case .locations: LocationsView(engine: engine).presentationDetents([.medium, .large])
        case .help: HelpView(engine: engine).presentationDetents([.large])
        case .log: LogView(engine: engine).presentationDetents([.medium, .large])
        case .module(let p): ModuleConfigView(engine: engine, pos: p).presentationDetents([.medium])
        case .file(let id): FileInspectorView(engine: engine, id: id).presentationDetents([.medium])
        case .offline(let secs, let earned): OfflineView(seconds: secs, earned: earned).presentationDetents([.height(260)])
        }
    }
}

// MARK: - Sözleşmeler

struct ContractsView: View {
    @Bindable var engine: GameEngine

    var body: some View {
        let s = engine.state
        let active = s.activeContract
        NavigationStack {
            List {
                Section("Active Contract") {
                    ContractRow(spec: active, progress: s.progress, isActive: true)
                }
                Section("Customer Policy") {
                    ForEach(PartKind.allCases, id: \.self) { k in
                        let rule = active.policy.rule(for: k)
                        if rule != .dontCare {
                            HStack {
                                Image(systemName: Theme.symbol(k)).foregroundStyle(Color(Theme.color(k))).frame(width: 24)
                                Text(k.displayName)
                                Spacer()
                                Text(rule.displayName)
                                    .foregroundStyle(rule == .mustRemove ? Color(Theme.danger) : Color(Theme.success))
                            }
                        }
                    }
                    if active.policy.minImageQuality > 0 {
                        HStack {
                            Image(systemName: "photo").foregroundStyle(Color(Theme.color(.image))).frame(width: 24)
                            Text("Image quality")
                            Spacer()
                            Text("at least \("\(Int(active.policy.minImageQuality * 100))%")")
                        }
                    }
                    if active.policy.rejectsEncrypted {
                        HStack {
                            Image(systemName: "lock.fill").foregroundStyle(Color(Theme.warning)).frame(width: 24)
                            Text("Encrypted files")
                            Spacer()
                            Text("refused").foregroundStyle(Color(Theme.danger))
                        }
                    }
                    Text("Delivering malicious content is always a breach: \(money(active.payPerFile * 3)) penalty and reputation loss.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("\(s.location.displayName) contracts") {
                    ForEach(Array(s.location.contracts.enumerated()), id: \.offset) { i, c in
                        HStack {
                            Image(systemName: i < s.progress.index ? "checkmark.circle.fill" : (i == s.progress.index ? "play.circle.fill" : "lock.circle"))
                                .foregroundStyle(i < s.progress.index ? Color(Theme.success) : (i == s.progress.index ? Color(Theme.accent) : .secondary))
                            VStack(alignment: .leading) {
                                Text(c.title).font(.subheadline.weight(.semibold))
                                Text("\(c.customer.displayName) · tier \(c.tier) · \(money(c.payPerFile))/file")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Contracts")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct ContractRow: View {
    var spec: ContractSpec
    var progress: ContractProgress
    var isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: Theme.symbol(spec.customer)).font(.title2)
                VStack(alignment: .leading) {
                    Text(spec.title).font(.headline)
                    Text(spec.customer.displayName).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("Tier \(spec.tier)").font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(Theme.warning).opacity(0.25), in: Capsule())
            }
            Text(spec.brief).font(.subheadline)
            HStack {
                Label("\(money(spec.payPerFile))/file", systemImage: "banknote")
                Label("Bonus \(money(spec.completionBonus))", systemImage: "gift")
                Label("+\(spec.reputationReward)", systemImage: "star")
            }
            .font(.caption).foregroundStyle(.secondary)
            if isActive {
                HStack {
                    Text("Delivered \(progress.delivered)/\(spec.targetFiles)")
                    Text("· Accepted \(progress.accepted)")
                    Text("· Complaints \(progress.complaints)")
                    Text("· Breaches \(progress.breaches)/\(spec.maxBreaches)").foregroundStyle(progress.breaches > 0 ? Color(Theme.danger) : .primary)
                }
                .font(.caption2.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                if progress.completions > 0 {
                    Text("This contract has been completed \(progress.completions) times").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Yükseltmeler

struct UpgradesView: View {
    @Bindable var engine: GameEngine

    var body: some View {
        let s = engine.state
        NavigationStack {
            List {
                Section {
                    HStack { Text("Balance"); Spacer(); Text(money(s.money)).bold().foregroundStyle(Color(Theme.success)) }
                }
                Section("Infrastructure") {
                    upgradeRow(title: String(localized: "Belt speed"), subtitle: String(format: String(localized: "%.2f cells/s"), s.beltSpeed),
                               level: s.beltLevel, max: GameState.maxBeltLevel, cost: s.beltUpgradeCost()) { engine.upgradeBelt() }
                    upgradeRow(title: String(localized: "File intake"), subtitle: String(localized: "Intake rate ×") + String(format: "%.1f", s.intakeMultiplier),
                               level: s.intakeLevel, max: GameState.maxIntakeLevel, cost: s.intakeUpgradeCost()) { engine.upgradeIntake() }
                }
                Section("Modules") {
                    ForEach(ModuleKind.allCases.filter { $0.isPlaceable && $0.maxLevel > 1 }, id: \.self) { k in
                        let lvl = s.level(of: k)
                        upgradeRow(title: k.displayName, subtitle: levelBlurb(k, lvl),
                                   level: lvl, max: k.maxLevel, cost: k.upgradeCost(toLevel: lvl + 1),
                                   color: Color(Theme.color(k)), symbol: Theme.symbol(k)) { engine.upgrade(k) }
                    }
                }
                Section {
                    Text("Upgrades apply to every module of that type at all sites. Each level speeds processing up by 50%.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Upgrades")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    func levelBlurb(_ k: ModuleKind, _ lvl: Int) -> String {
        switch k {
        case .parser: ["", String(localized: "Opens the top layer"), String(localized: "Opens ZIP inside ZIP"), String(localized: "Resolves polyglot files")][min(lvl, 3)]
        case .transformer: ["", String(localized: "Image −40%, formulas flattened"), String(localized: "Image −20%, formulas kept"), String(localized: "Image −5%, formulas kept")][min(lvl, 3)]
        case .scanner: ["", String(localized: "Top-layer signatures"), String(localized: "Also looks inside ZIPs"), String(localized: "Faster")][min(lvl, 3)]
        default: String(localized: "Processing time \(String(format: "%.2f", k.processTime(level: lvl))) s")
        }
    }

    @ViewBuilder
    func upgradeRow(title: String, subtitle: String, level: Int, max: Int, cost: Int,
                    color: Color = Color(Theme.accent), symbol: String = "speedometer", action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading) {
                Text("\(title)  ·  Level \(level)/\(max)").font(.subheadline.weight(.semibold))
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if level >= max {
                Text("MAX").font(.caption.bold()).foregroundStyle(.secondary)
            } else {
                Button(action: action) {
                    Text(money(cost)).font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(engine.state.money >= cost ? color.opacity(0.3) : Color.gray.opacity(0.2), in: Capsule())
                }
                .buttonStyle(.plain)
                .disabled(engine.state.money < cost)
            }
        }
    }
}

// MARK: - Mekânlar

struct LocationsView: View {
    @Bindable var engine: GameEngine

    var body: some View {
        let s = engine.state
        NavigationStack {
            List {
                ForEach(LocationKind.allCases, id: \.self) { l in
                    let spec = l.spec
                    let unlocked = s.unlockedLocations.contains(l)
                    let current = s.currentLocation == l
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: Theme.symbol(l)).font(.title2).foregroundStyle(unlocked ? Color(Theme.accent) : .secondary)
                            VStack(alignment: .leading) {
                                Text(spec.displayName).font(.headline)
                                Text("\(spec.width)×\(spec.height) cells" + (spec.airGapped ? " · air-gapped" : "")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if current {
                                Text("YOU ARE HERE").font(.caption2.bold()).foregroundStyle(Color(Theme.success))
                            } else if unlocked {
                                Button("Go") { engine.switchLocation(l) }.buttonStyle(.borderedProminent).controlSize(.small)
                            } else {
                                Button {
                                    engine.unlock(l)
                                } label: {
                                    VStack(spacing: 1) {
                                        Text(money(spec.unlockCost)).font(.caption.bold())
                                        Text("★ \(spec.unlockReputation)").font(.caption2)
                                    }
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                                .disabled(s.money < spec.unlockCost || s.reputation < spec.unlockReputation)
                            }
                        }
                        Text(spec.description).font(.subheadline)
                        HStack(spacing: 6) {
                            ForEach(spec.availableModules, id: \.self) { k in
                                Image(systemName: Theme.symbol(k)).font(.caption).foregroundStyle(Color(Theme.color(k)))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Text("Switching sites drops the files on the belt; layout and contract progress are stored per site.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Sites")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Modül ayarı

struct ModuleConfigView: View {
    @Bindable var engine: GameEngine
    var pos: GridPos

    var body: some View {
        NavigationStack {
            if let m = engine.state.grid[pos]?.module {
                let level = engine.state.level(of: m.kind)
                List {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: Theme.symbol(m.kind)).font(.largeTitle).foregroundStyle(Color(Theme.color(m.kind)))
                            VStack(alignment: .leading) {
                                Text(m.kind.displayName).font(.headline)
                                Text("Level \(level) · \(String(format: "%.2f", m.kind.processTime(level: level))) s/file · output: \(m.facing.displayName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(m.kind.blurb).font(.subheadline)
                        if m.kind == .scanner && engine.state.location.airGapped {
                            Label("Signatures don't update on this network; the scanner only recognizes old macros.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(Color(Theme.danger))
                        }
                    }
                    if m.kind == .filter {
                        Section("Target part") {
                            Picker("Target", selection: Binding(
                                get: { m.config.filterTarget },
                                set: { engine.setFilter(at: pos, $0) })) {
                                ForEach(PartKind.filterable, id: \.self) { k in
                                    Label(k.displayName, systemImage: Theme.symbol(k)).tag(k)
                                }
                            }
                            .pickerStyle(.inline)
                            .labelsHidden()
                        }
                    }
                    if m.kind == .router {
                        Section("Diverted right") {
                            Toggle(isOn: Binding(
                                get: { m.config.routeEncrypted },
                                set: { engine.setRouteEncrypted(at: pos, $0) })) {
                                Label("Encrypted files", systemImage: "lock.fill")
                            }
                            Picker("Container", selection: Binding(
                                get: { m.config.routeTarget },
                                set: { engine.setRoute(at: pos, $0) })) {
                                ForEach(ContainerKind.allCases, id: \.self) { c in
                                    Text(c.displayName).tag(c)
                                }
                            }
                            .pickerStyle(.segmented)
                            .disabled(m.config.routeEncrypted)
                            Text(m.config.routeEncrypted
                                 ? "Password-protected files go right (toward quarantine, say); everything else goes straight."
                                 : "Files of the selected container type go right; everything else goes straight.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        if m.kind.isPlaceable {
                            Button { engine.rotate(at: pos) } label: { Label("Rotate (clockwise)", systemImage: "rotate.right") }
                            if level < m.kind.maxLevel {
                                Button { engine.upgrade(m.kind) } label: {
                                    Label("Upgrade → Level \(level + 1)  (\(money(m.kind.upgradeCost(toLevel: level + 1))))", systemImage: "arrow.up.circle")
                                }
                            }
                            Button(role: .destructive) { engine.remove(at: pos) } label: {
                                Label("Remove (\(money(m.kind.baseCost / 2)) refund)", systemImage: "trash")
                            }
                        } else {
                            Text("This module is fixed to the site.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Module")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Module removed", systemImage: "xmark.square")
            }
        }
    }
}

// MARK: - Dosya inceleme

struct FileInspectorView: View {
    @Bindable var engine: GameEngine
    var id: UUID

    var body: some View {
        NavigationStack {
            if let item = engine.item(id) {
                let f = item.file
                let policy = engine.state.activeContract.policy
                List {
                    Section {
                        HStack(spacing: 12) {
                            RoundedRectangle(cornerRadius: 6).fill(Color(Theme.color(f.container))).frame(width: 36, height: 44)
                                .overlay(Text(f.container.displayName).font(.system(size: 9, weight: .bold)))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.container.displayName + (f.polyglot ? " (polyglot: also a ZIP)" : "")).font(.headline)
                                if f.encrypted {
                                    Label("Encrypted: can't be opened or inspected", systemImage: "lock.fill")
                                        .font(.caption).foregroundStyle(Color(Theme.warning))
                                } else {
                                    Text(f.isOpen ? "Open · visible layer \(f.exposedDepth)" : "Closed").font(.caption).foregroundStyle(.secondary)
                                }
                                if f.hasImage {
                                    Text("Image quality \("\(Int(f.imageQuality * 100))%")").font(.caption).foregroundStyle(.secondary)
                                }
                                if let note = item.lastNote, !note.isEmpty {
                                    Text("Last step: \(note)").font(.caption).foregroundStyle(Color(Theme.accent))
                                }
                            }
                        }
                    }
                    Section("Parts") {
                        if f.parts.isEmpty { Text("Empty container").foregroundStyle(.secondary) }
                        ForEach(f.parts) { p in
                            let exposed = f.isExposed(p)
                            let hiddenNested = p.depth > 0 && !exposed
                            HStack {
                                Image(systemName: hiddenNested ? "questionmark.circle" : Theme.symbol(p.kind))
                                    .foregroundStyle(hiddenNested ? .secondary : Color(Theme.color(p.kind))).frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(hiddenNested ? "Hidden content (layer \(p.depth))" : p.kind.displayName)
                                    Text(partStatus(p, exposed: exposed, hiddenNested: hiddenNested, policy: policy))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if p.malicious && !hiddenNested {
                                    Text(p.signatureKnown ? "MALICIOUS" : "MALICIOUS · no signature")
                                        .font(.caption2.bold()).foregroundStyle(Color(Theme.danger))
                                }
                            }
                        }
                    }
                    Section {
                        let o = DeliveryEvaluator.evaluate(f, policy: policy, payPerFile: engine.state.activeContract.payPerFile)
                        Text(o.breach ? "If delivered now: BREACH (\(money(o.pay)))" : "If delivered now: \(money(o.pay)) · usability \("\(Int(o.usability * 100))%")")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(o.breach ? Color(Theme.danger) : (o.accepted ? Color(Theme.success) : Color(Theme.warning)))
                        ForEach(o.issues, id: \.self) { Text($0.text).font(.caption) }
                    }
                }
                .navigationTitle("File")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("File left the line", systemImage: "doc.questionmark")
            }
        }
    }

    func partStatus(_ p: Part, exposed: Bool, hiddenNested: Bool, policy: Policy) -> String {
        var bits: [String] = []
        if p.depth > 0 { bits.append(String(localized: "layer \(p.depth)")) }
        if hiddenNested { bits.append(String(localized: "parser didn't open this layer")) }
        else if exposed { bits.append(String(localized: "open, filterable")) }
        else { bits.append(String(localized: "inside closed container")) }
        let rule = policy.rule(for: p.kind)
        if rule != .dontCare { bits.append(String(localized: "customer: \(rule.displayName)")) }
        return bits.joined(separator: " · ")
    }
}

// MARK: - Günlük

struct LogView: View {
    @Bindable var engine: GameEngine
    var body: some View {
        NavigationStack {
            List {
                Section("Statistics") {
                    let st = engine.state.stats
                    LabeledContent("Delivered", value: "\(st.totalDelivered)")
                    LabeledContent("Accepted", value: "\(st.totalAccepted)")
                    LabeledContent("Breach", value: "\(st.totalBreaches)")
                    LabeledContent("Quarantined", value: "\(st.totalQuarantined)")
                    LabeledContent("Total earned", value: money(st.totalEarned))
                    LabeledContent("Income rate", value: String(format: "%.1f ₺/dk", engine.state.incomeRatePerSec * 60))
                }
                Section("Recent events") {
                    if engine.log.isEmpty { Text("No events yet").foregroundStyle(.secondary) }
                    ForEach(engine.log) { e in
                        HStack(alignment: .top) {
                            Text(e.time, style: .time).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            Text(e.text).font(.caption)
                                .foregroundStyle(e.style == .bad ? Color(Theme.danger) : (e.style == .good ? Color(Theme.success) : .primary))
                        }
                    }
                }
                Section {
                    Button(role: .destructive) { engine.resetGame() } label: { Label("Reset game", systemImage: "arrow.counterclockwise") }
                }
            }
            .navigationTitle("Log")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Offline

struct OfflineView: View {
    var seconds: Double
    var earned: Int
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "moon.zzz.fill").font(.largeTitle).foregroundStyle(Color(Theme.accent))
            Text("The line kept running while you were away").font(.headline)
            Text("The pipeline processed files for \(Int(seconds / 60)) minutes.").font(.subheadline).foregroundStyle(.secondary)
            Text("+\(money(earned))").font(.system(.largeTitle, design: .rounded).bold()).foregroundStyle(Color(Theme.success))
            Button("Continue") { dismiss() }.buttonStyle(.borderedProminent)
        }
        .padding()
    }
}

// MARK: - Yardım

struct HelpView: View {
    @Bindable var engine: GameEngine
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Goal") {
                    Text("Customer files flow in from the intake. You arrange modules and belts to clean, package and deliver them. A clean file that meets the contract earns money; delivering malicious content is a breach.")
                }
                Section("Tension: security ↔ usability") {
                    Text("Clean too aggressively and the file breaks, the customer won't pay. Go easy and malware slips through. Accounting wants formulas, the bank wants zero active content, the design agency wants image quality.")
                }
                Section("Basic line") {
                    Text("Intake → Parser → Filter(Macro) → Packager → Delivery. Filter and transformer only work on opened files; deliver an open file and the customer can't open it.")
                }
                Section("Modules") {
                    ForEach(ModuleKind.allCases.filter(\.isPlaceable), id: \.self) { k in
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: Theme.symbol(k)).foregroundStyle(Color(Theme.color(k))).frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(k.displayName).font(.subheadline.weight(.semibold))
                                Text(k.blurb).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Controls") {
                    Text("Drag with the Belt tool to draw a belt path. Tap an empty cell with a module tool to place it (pick the output direction with the Facing button). Tap a module with the Select tool for settings; tap a file on the belt to see what it carries.")
                }
                Section("Threat tiers") {
                    Text("1 Macro → 2 Script → 3 ZIP inside ZIP (parser level 2) → 4 Polyglot and hidden data (parser level 3, transformer) → 5 Unknown: no signature, the scanner can't see it, only the transformer destroys it; archives nest three deep → 6 Encrypted: nothing can open it. Set a router to divert encrypted files into quarantine.")
                    Text("Not every customer wants everything stripped: a software house needs its scripts kept, a hospital needs its images intact. Read the policy before you build.")
                }
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Start") { engine.state.tutorialSeen = true; dismiss() }
            }
        }
    }
}

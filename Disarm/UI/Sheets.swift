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
                Section("Aktif Sözleşme") {
                    ContractRow(spec: active, progress: s.progress, isActive: true)
                }
                Section("Müşteri Politikası") {
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
                            Text("Görsel kalitesi")
                            Spacer()
                            Text("en az %\(Int(active.policy.minImageQuality * 100))")
                        }
                    }
                    Text("Zararlı içerik teslim etmek her koşulda ihlaldir: \(money(active.payPerFile * 3)) ceza ve itibar kaybı.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("\(s.location.displayName) sözleşmeleri") {
                    ForEach(Array(s.location.contracts.enumerated()), id: \.offset) { i, c in
                        HStack {
                            Image(systemName: i < s.progress.index ? "checkmark.circle.fill" : (i == s.progress.index ? "play.circle.fill" : "lock.circle"))
                                .foregroundStyle(i < s.progress.index ? Color(Theme.success) : (i == s.progress.index ? Color(Theme.accent) : .secondary))
                            VStack(alignment: .leading) {
                                Text(c.title).font(.subheadline.weight(.semibold))
                                Text("\(c.customer.displayName) · seviye \(c.tier) · \(money(c.payPerFile))/dosya")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sözleşmeler")
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
                Text("Seviye \(spec.tier)").font(.caption.weight(.bold))
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color(Theme.warning).opacity(0.25), in: Capsule())
            }
            Text(spec.brief).font(.subheadline)
            HStack {
                Label("\(money(spec.payPerFile))/dosya", systemImage: "banknote")
                Label("Bonus \(money(spec.completionBonus))", systemImage: "gift")
                Label("+\(spec.reputationReward)", systemImage: "star")
            }
            .font(.caption).foregroundStyle(.secondary)
            if isActive {
                HStack {
                    Text("Teslim \(progress.delivered)/\(spec.targetFiles)")
                    Text("· Kabul \(progress.accepted)")
                    Text("· Şikayet \(progress.complaints)")
                    Text("· İhlal \(progress.breaches)/\(spec.maxBreaches)").foregroundStyle(progress.breaches > 0 ? Color(Theme.danger) : .primary)
                }
                .font(.caption.monospacedDigit())
                if progress.completions > 0 {
                    Text("Bu sözleşme \(progress.completions) kez tamamlandı").font(.caption2).foregroundStyle(.secondary)
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
                    HStack { Text("Bakiye"); Spacer(); Text(money(s.money)).bold().foregroundStyle(Color(Theme.success)) }
                }
                Section("Altyapı") {
                    upgradeRow(title: "Bant hızı", subtitle: String(format: "%.2f hücre/sn", s.beltSpeed),
                               level: s.beltLevel, max: GameState.maxBeltLevel, cost: s.beltUpgradeCost()) { engine.upgradeBelt() }
                    upgradeRow(title: "Dosya akışı", subtitle: "Giriş hızı ×" + String(format: "%.1f", s.intakeMultiplier),
                               level: s.intakeLevel, max: GameState.maxIntakeLevel, cost: s.intakeUpgradeCost()) { engine.upgradeIntake() }
                }
                Section("Modüller") {
                    ForEach(ModuleKind.allCases.filter { $0.isPlaceable && $0.maxLevel > 1 }, id: \.self) { k in
                        let lvl = s.level(of: k)
                        upgradeRow(title: k.displayName, subtitle: levelBlurb(k, lvl),
                                   level: lvl, max: k.maxLevel, cost: k.upgradeCost(toLevel: lvl + 1),
                                   color: Color(Theme.color(k)), symbol: Theme.symbol(k)) { engine.upgrade(k) }
                    }
                }
                Section {
                    Text("Yükseltmeler tüm mekânlardaki aynı tür modüllere uygulanır. Her seviye işlem hızını %50 artırır.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Yükseltmeler")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    func levelBlurb(_ k: ModuleKind, _ lvl: Int) -> String {
        switch k {
        case .parser: ["", "Üst katmanı açar", "ZIP içinde ZIP'i açar", "Polyglot dosyaları çözer"][min(lvl, 3)]
        case .transformer: ["", "Görsel −%40, formüller düzleşir", "Görsel −%20, formüller korunur", "Görsel −%5, formüller korunur"][min(lvl, 3)]
        case .scanner: ["", "Üst katman imzaları", "ZIP içine de bakar", "Daha hızlı"][min(lvl, 3)]
        default: "İşlem süresi \(String(format: "%.2f", k.processTime(level: lvl))) sn"
        }
    }

    @ViewBuilder
    func upgradeRow(title: String, subtitle: String, level: Int, max: Int, cost: Int,
                    color: Color = Color(Theme.accent), symbol: String = "speedometer", action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 28)
            VStack(alignment: .leading) {
                Text("\(title)  ·  Seviye \(level)/\(max)").font(.subheadline.weight(.semibold))
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
                                Text("\(spec.width)×\(spec.height) hücre" + (spec.airGapped ? " · air-gapped" : "")).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if current {
                                Text("BURADASIN").font(.caption2.bold()).foregroundStyle(Color(Theme.success))
                            } else if unlocked {
                                Button("Git") { engine.switchLocation(l) }.buttonStyle(.borderedProminent).controlSize(.small)
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
                    Text("Mekân değiştirince bant üzerindeki dosyalar düşer; hat ve sözleşme ilerlemesi her mekân için ayrı saklanır.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Mekânlar")
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
                                Text("Seviye \(level) · \(String(format: "%.2f", m.kind.processTime(level: level))) sn/dosya · çıkış: \(m.facing.displayName)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Text(m.kind.blurb).font(.subheadline)
                        if m.kind == .scanner && engine.state.location.airGapped {
                            Label("Bu ağda imzalar güncellenmiyor; tarayıcı yalnızca eski makroları tanır.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(Color(Theme.danger))
                        }
                    }
                    if m.kind == .filter {
                        Section("Hedef parça") {
                            Picker("Hedef", selection: Binding(
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
                        Section("Sağa ayrılacak kap türü") {
                            Picker("Kap", selection: Binding(
                                get: { m.config.routeTarget },
                                set: { engine.setRoute(at: pos, $0) })) {
                                ForEach(ContainerKind.allCases, id: \.self) { c in
                                    Text(c.displayName).tag(c)
                                }
                            }
                            .pickerStyle(.segmented)
                        }
                    }
                    Section {
                        if m.kind.isPlaceable {
                            Button { engine.rotate(at: pos) } label: { Label("Döndür (saat yönü)", systemImage: "rotate.right") }
                            if level < m.kind.maxLevel {
                                Button { engine.upgrade(m.kind) } label: {
                                    Label("Yükselt → Seviye \(level + 1)  (\(money(m.kind.upgradeCost(toLevel: level + 1))))", systemImage: "arrow.up.circle")
                                }
                            }
                            Button(role: .destructive) { engine.remove(at: pos) } label: {
                                Label("Kaldır (\(money(m.kind.baseCost / 2)) iade)", systemImage: "trash")
                            }
                        } else {
                            Text("Bu modül mekâna sabittir.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .navigationTitle("Modül")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Modül kaldırıldı", systemImage: "xmark.square")
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
                                Text(f.container.displayName + (f.polyglot ? " (polyglot: ayrıca ZIP)" : "")).font(.headline)
                                Text(f.isOpen ? "Açık · görünür katman \(f.exposedDepth)" : "Kapalı").font(.caption).foregroundStyle(.secondary)
                                if f.hasImage {
                                    Text("Görsel kalitesi %\(Int(f.imageQuality * 100))").font(.caption).foregroundStyle(.secondary)
                                }
                                if let note = item.lastNote, !note.isEmpty {
                                    Text("Son işlem: \(note)").font(.caption).foregroundStyle(Color(Theme.accent))
                                }
                            }
                        }
                    }
                    Section("Parçalar") {
                        if f.parts.isEmpty { Text("Boş kap").foregroundStyle(.secondary) }
                        ForEach(f.parts) { p in
                            let exposed = f.isExposed(p)
                            let hiddenNested = p.depth > 0 && !exposed
                            HStack {
                                Image(systemName: hiddenNested ? "questionmark.circle" : Theme.symbol(p.kind))
                                    .foregroundStyle(hiddenNested ? .secondary : Color(Theme.color(p.kind))).frame(width: 24)
                                VStack(alignment: .leading) {
                                    Text(hiddenNested ? "Gizli içerik (katman \(p.depth))" : p.kind.displayName)
                                    Text(partStatus(p, exposed: exposed, hiddenNested: hiddenNested, policy: policy))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if p.malicious && !hiddenNested {
                                    Text(p.signatureKnown ? "ZARARLI" : "ZARARLI · imzasız")
                                        .font(.caption2.bold()).foregroundStyle(Color(Theme.danger))
                                }
                            }
                        }
                    }
                    Section {
                        let o = DeliveryEvaluator.evaluate(f, policy: policy, payPerFile: engine.state.activeContract.payPerFile)
                        Text(o.breach ? "Şu an teslim edilse: İHLAL (\(money(o.pay)))" : "Şu an teslim edilse: \(money(o.pay)) · kullanılabilirlik %\(Int(o.usability * 100))")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(o.breach ? Color(Theme.danger) : (o.accepted ? Color(Theme.success) : Color(Theme.warning)))
                        ForEach(o.issues, id: \.self) { Text($0).font(.caption) }
                    }
                }
                .navigationTitle("Dosya")
                .navigationBarTitleDisplayMode(.inline)
            } else {
                ContentUnavailableView("Dosya hattan ayrıldı", systemImage: "doc.questionmark")
            }
        }
    }

    func partStatus(_ p: Part, exposed: Bool, hiddenNested: Bool, policy: Policy) -> String {
        var bits: [String] = []
        if p.depth > 0 { bits.append("katman \(p.depth)") }
        if hiddenNested { bits.append("ayrıştırıcı bu katmanı açmadı") }
        else if exposed { bits.append("açık, filtrelenebilir") }
        else { bits.append("kapalı kapta") }
        let rule = policy.rule(for: p.kind)
        if rule != .dontCare { bits.append("müşteri: \(rule.displayName)") }
        return bits.joined(separator: " · ")
    }
}

// MARK: - Günlük

struct LogView: View {
    @Bindable var engine: GameEngine
    var body: some View {
        NavigationStack {
            List {
                Section("İstatistik") {
                    let st = engine.state.stats
                    LabeledContent("Teslim", value: "\(st.totalDelivered)")
                    LabeledContent("Kabul", value: "\(st.totalAccepted)")
                    LabeledContent("İhlal", value: "\(st.totalBreaches)")
                    LabeledContent("Karantina", value: "\(st.totalQuarantined)")
                    LabeledContent("Toplam kazanç", value: money(st.totalEarned))
                    LabeledContent("Kazanç hızı", value: String(format: "%.1f ₺/dk", engine.state.incomeRatePerSec * 60))
                }
                Section("Son olaylar") {
                    if engine.log.isEmpty { Text("Henüz olay yok").foregroundStyle(.secondary) }
                    ForEach(engine.log) { e in
                        HStack(alignment: .top) {
                            Text(e.time, style: .time).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            Text(e.text).font(.caption)
                                .foregroundStyle(e.style == .bad ? Color(Theme.danger) : (e.style == .good ? Color(Theme.success) : .primary))
                        }
                    }
                }
                Section {
                    Button(role: .destructive) { engine.resetGame() } label: { Label("Oyunu sıfırla", systemImage: "arrow.counterclockwise") }
                }
            }
            .navigationTitle("Günlük")
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
            Text("Sen yokken hat çalıştı").font(.headline)
            Text("\(Int(seconds / 60)) dakika boyunca pipeline dosya işledi.").font(.subheadline).foregroundStyle(.secondary)
            Text("+\(money(earned))").font(.system(.largeTitle, design: .rounded).bold()).foregroundStyle(Color(Theme.success))
            Button("Devam") { dismiss() }.buttonStyle(.borderedProminent)
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
                Section("Amaç") {
                    Text("Müşterilerin dosyaları girişten akar. Sen modülleri ve bantları dizerek dosyaları temizler, paketler ve teslimata ulaştırırsın. Temiz ve sözleşmeye uygun dosya para kazandırır; zararlı içerik teslim etmek ihlaldir.")
                }
                Section("Gerilim: güvenlik ↔ kullanılabilirlik") {
                    Text("Her şeyi agresif temizlersen dosya bozulur, müşteri ödemez. Gevşek bırakırsan zararlı kaçar. Muhasebe formül ister, banka hiçbir aktif içerik istemez, tasarım ajansı görsel kalitesi ister.")
                }
                Section("Temel hat") {
                    Text("Giriş → Ayrıştırıcı → Filtre(Makro) → Paketleyici → Teslimat. Filtre ve dönüştürücü yalnızca açılmış dosyada çalışır; açık dosya teslim edilirse müşteri açamaz.")
                }
                Section("Modüller") {
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
                Section("Kontroller") {
                    Text("Bant aracıyla parmağını sürükle: bant yolu çizilir. Modül aracıyla boş hücreye dokun: yerleşir (yön butonuyla çıkış yönünü seç). Seç aracıyla modüle dokun: ayarlar; bant üzerindeki dosyaya dokun: ne taşıdığını gör.")
                }
                Section("Tehdit seviyeleri") {
                    Text("1 Makro → 2 Betik → 3 ZIP içinde ZIP (ayrıştırıcı seviye 2) → 4 Polyglot ve gizli veri (ayrıştırıcı seviye 3, dönüştürücü) → 5 Bilinmeyen: imza yok, tarayıcı göremez, sadece dönüştürücü yok eder.")
                }
            }
            .navigationTitle("Nasıl Oynanır")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Başla") { engine.state.tutorialSeen = true; dismiss() }
            }
        }
    }
}

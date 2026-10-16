import Foundation

/// Tek seferlik ipucu kartları: mekâna giriş, yeni sözleşme, yükseltme parası, kampanya bitişi.
/// Hangi ipucunun gösterileceği durumdan türetilir; görülenler `GameState.seenHints`'te tutulur.
public enum Hint: String, Codable, CaseIterable, Sendable {
    case scripts, imageQuality, keepScripts, upgrades
    case company, nestedZip, hiddenData, polyglot, hospital
    case bank, unknownThreat, encrypted
    case airGapped
    case dataCenter, forensics
    /// Mekânın tüm sözleşmeleri bitti, sıradaki mekân kilitli: oyuncuyu Mekânlar sayfasına yönlendir.
    case officeDone, companyDone, bankDone, governmentDone
    case campaignDone

    public enum Action: Sendable, Equatable {
        case openContracts, openUpgrades, openCampaign, openLocations
    }

    /// "Mekân bitti" ipucunun ait olduğu mekân.
    public var finishedSite: LocationKind? {
        switch self {
        case .officeDone: .smallOffice
        case .companyDone: .company
        case .bankDone: .bank
        case .governmentDone: .government
        default: nil
        }
    }

    static func siteDoneText(from site: LocationKind) -> String {
        guard let next = site.next else { return "" }
        let spec = next.spec
        return L("Every contract in \(site.spec.displayName) is done. Next up: \(spec.displayName). Unlock it from Sites for \(spec.unlockCost) cash and \(spec.unlockReputation) reputation; the line here keeps earning meanwhile.")
    }

    public var text: String {
        switch self {
        case .scripts:
            L("Scripts have joined the macros. A Filter drops only one part type: add a second filter set to Script, or put a cheap Signature Scanner at the front to catch known threats before parsing.")
        case .imageQuality:
            L("The agency pays for image quality. Filters don't touch images, but a low-level Transformer would ruin them; keep the line simple here.")
        case .keepScripts:
            L("This customer keeps its scripts. Don't filter Script: a Signature Scanner removes only the malicious ones and leaves the source code alone.")
        case .upgrades:
            L("Modules can be upgraded: a level 2 Parser opens nested archives, a level 2 Scanner looks inside ZIPs. Open Upgrades from the menu.")
        case .company:
            L("New site, new tools: the Router diverts one container type sideways and the Transformer destroys hidden data. Bigger grid, faster flow; rebuild your line.")
        case .nestedZip:
            L("The payload hides one layer down. A level 1 Parser never sees it: upgrade the Parser to level 2 before the breaches pile up.")
        case .hiddenData:
            L("Hidden data sits inside images. Only the Transformer destroys it, but level 1 wrecks image quality and the publisher wants 85%. Upgrade it.")
        case .polyglot:
            L("Polyglot files are PDF and ZIP at once. Only a level 3 Parser exposes the second identity; the scanner is blind to it.")
        case .hospital:
            L("Images must stay above 90% and hidden patient data must go. Only a level 3 Transformer is gentle enough.")
        case .bank:
            L("Zero active content: even harmless macros, scripts and embedded files count as complaints here. Filter all three and let the Transformer handle the rest.")
        case .unknownThreat:
            L("Threats without signatures: the scanner can't see them, and some archives nest three deep. A level 3 Parser plus the Transformer is the only answer.")
        case .encrypted:
            L("Encrypted archives can't be opened or scanned. Tap a Router, switch it to Encrypted files and point its side output at a Quarantine. Harmless ones are lost income; the rest would be breaches.")
        case .airGapped:
            L("Air-gapped network: no signature updates. The scanner only recognizes ancient macros; disarm everything with Parser, Filters and Transformer.")
        case .dataCenter:
            L("Top floor. The Sandbox detonates a file in isolation and removes whatever misbehaves: no signatures, no quality loss, closed files welcome. It is slow and blind to encryption and polyglots. At this flow rate, build parallel lines.")
        case .forensics:
            L("Evidence must stay untouched, so no transformer here. Put a Sandbox first for unsigned payloads, then Parser, Filter(Macro) and Packager for the harmless macros.")
        case .officeDone, .companyDone, .bankDone, .governmentDone:
            Self.siteDoneText(from: finishedSite!)
        case .campaignDone:
            L("Every contract delivered. The Campaign page now offers a new campaign with permanent bonuses.")
        }
    }

    /// SF Symbol adı.
    public var icon: String {
        switch self {
        case .scripts: "chevron.left.forwardslash.chevron.right"
        case .imageQuality: "photo"
        case .keepScripts: "terminal"
        case .upgrades: "arrow.up.circle"
        case .company: "building"
        case .nestedZip: "square.stack.3d.up"
        case .hiddenData: "eye.slash"
        case .polyglot: "doc.on.doc"
        case .hospital: "cross.case"
        case .bank: "building.columns"
        case .unknownThreat: "questionmark.diamond"
        case .encrypted: "lock.fill"
        case .airGapped: "antenna.radiowaves.left.and.right.slash"
        case .dataCenter: "flame"
        case .forensics: "magnifyingglass"
        case .officeDone, .companyDone, .bankDone, .governmentDone: "map"
        case .campaignDone: "trophy.fill"
        }
    }

    public var action: Action? {
        switch self {
        case .upgrades, .nestedZip, .hiddenData, .hospital: .openUpgrades
        case .bank, .company: .openContracts
        case .officeDone, .companyDone, .bankDone, .governmentDone: .openLocations
        case .campaignDone: .openCampaign
        default: nil
        }
    }

    /// Bu durumda geçerli mi? (Görülmüş olup olmadığına bakmaz.)
    public func applies(to s: GameState) -> Bool {
        let loc = s.currentLocation
        let index = s.progress.index
        switch self {
        case .campaignDone: return s.campaignCompleted
        case .officeDone, .companyDone, .bankDone, .governmentDone:
            guard let site = finishedSite, let next = site.next else { return false }
            return loc == site && s.isFinished(site) && !s.unlockedLocations.contains(next)
        case .scripts: return loc == .smallOffice && index == 1
        case .imageQuality: return loc == .smallOffice && index == 2
        case .keepScripts: return loc == .smallOffice && index == 3
        case .upgrades:
            return s.tutorialSeen && loc == .smallOffice && index >= 1
                && s.level >= Progression.requiredLevel(forUpgradeTo: 2)
                && s.level(of: .parser) == 1 && s.money >= ModuleKind.parser.upgradeCost(toLevel: 2)
        case .company: return loc == .company
        case .nestedZip: return loc == .company && index == 0 && s.level(of: .parser) < 2
        case .hiddenData: return loc == .company && index == 1 && s.level(of: .transformer) < 2
        case .polyglot: return loc == .company && index == 2
        case .hospital: return loc == .company && index == 3 && s.level(of: .transformer) < 3
        case .bank: return loc == .bank
        case .unknownThreat: return loc == .bank && index == 1
        case .encrypted: return loc == .bank && index == 2
        case .airGapped: return loc == .government
        case .dataCenter: return loc == .dataCenter
        case .forensics: return loc == .dataCenter && index == 1 && s.grid.positions(of: .sandbox).isEmpty
        }
    }

    /// Gösterilecek ilk ipucu: önce kampanya, sonra mekân girişi, sonra sözleşmeye özel olanlar.
    /// Küçük ofisin ilk sözleşmesinde adım adım öğretici sürerken ipucu gösterilmez.
    public static func pending(for s: GameState) -> Hint? {
        if !s.tutorialSeen && s.currentLocation == .smallOffice { return nil }
        // Öncelik: kampanya bitişi, sonra "mekân bitti" yönlendirmesi, sonra geri kalanlar.
        let first: [Hint] = [.campaignDone, .officeDone, .companyDone, .bankDone, .governmentDone]
        let order: [Hint] = first + allCases.filter { !first.contains($0) }
        return order.first { !s.seenHints.contains($0) && $0.applies(to: s) }
    }
}

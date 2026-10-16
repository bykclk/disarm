import Foundation

/// Süreli krizler: oyuncu kurulu hattı anlık uyarlamak zorunda kalır. İkinci sözleşme bitince başlar,
/// 2,5–5 dakikada bir rastgele biri gelir.
public enum IncidentKind: String, Codable, CaseIterable, Sendable {
    /// Bilinmeyen (imzasız) tehdit dalgası: dosyaların %40'ına ek imzasız yük biner.
    case zeroDay
    /// İmza sunucusu kesintisi: tarayıcı yalnızca eski makroları tanır (air-gapped gibi).
    case signatureOutage
    /// Acil müşteri: ödeme ×2, akış ×1,5.
    case rushOrder
    /// Denetim: tek bir ihlal sözleşmeyi iptal eder.
    case audit

    public var duration: Double {
        switch self {
        case .zeroDay: 60
        case .signatureOutage: 45
        case .rushOrder: 60
        case .audit: 90
        }
    }

    public var displayName: String {
        switch self {
        case .zeroDay: L("Zero-day wave")
        case .signatureOutage: L("Signature outage")
        case .rushOrder: L("Rush order")
        case .audit: L("Compliance audit")
        }
    }

    public var detail: String {
        switch self {
        case .zeroDay: L("Unsigned payloads are riding in on many files. Scanners can't see them; transformers and sandboxes can.")
        case .signatureOutage: L("The signature feed is down. Scanners recognize only ancient macros until it returns.")
        case .rushOrder: L("A customer pays double and sends files half again as fast. Keep up without breaches.")
        case .audit: L("Regulators are watching: a single breach cancels the contract until the audit ends.")
        }
    }

    public var icon: String {
        switch self {
        case .zeroDay: "bolt.trianglebadge.exclamationmark"
        case .signatureOutage: "antenna.radiowaves.left.and.right.slash"
        case .rushOrder: "hare.fill"
        case .audit: "eye.trianglebadge.exclamationmark"
        }
    }

    /// Oyuncu için fırsat mı (yeşil) yoksa tehdit mi (kırmızı)?
    public var isOpportunity: Bool { self == .rushOrder }
}

public struct Incident: Codable, Hashable, Sendable {
    public var kind: IncidentKind
    public var remaining: Double
    public init(kind: IncidentKind, remaining: Double) {
        self.kind = kind
        self.remaining = remaining
    }
}

public extension Simulation {
    static let incidentMinContracts = 2
    static let incidentDelay: ClosedRange<Double> = 150...300

    mutating func nextIncidentDelay() -> Double {
        Double.random(in: Self.incidentDelay, using: &rng)
    }

    /// Her tick: aktif olayı say, bittiyse kapat; yoksa zamanlayıcıyı ilerlet ve yeni olay başlat.
    mutating func tickIncidents(dt: Double, state: GameState, events: inout [GameEvent]) {
        guard incidentsEnabled, state.stats.contractsCompleted >= Self.incidentMinContracts else { return }
        if var inc = activeIncident {
            inc.remaining -= dt
            if inc.remaining <= 0 {
                activeIncident = nil
                incidentTimer = nextIncidentDelay()
                events.append(.incidentEnded(inc.kind))
            } else {
                activeIncident = inc
            }
            return
        }
        incidentTimer -= dt
        if incidentTimer <= 0 {
            let kind = IncidentKind.allCases[Int.random(in: 0..<IncidentKind.allCases.count, using: &rng)]
            activeIncident = Incident(kind: kind, remaining: kind.duration)
            events.append(.incidentStarted(kind))
        }
    }

    var zeroDayActive: Bool { activeIncident?.kind == .zeroDay }
    var signatureOutageActive: Bool { activeIncident?.kind == .signatureOutage }
    var rushOrderActive: Bool { activeIncident?.kind == .rushOrder }
    var auditActive: Bool { activeIncident?.kind == .audit }
}

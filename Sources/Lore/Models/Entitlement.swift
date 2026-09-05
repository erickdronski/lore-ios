import Foundation

/// Row shape of the `entitlements` table, a user's paid access grants. Own
/// rows only, via RLS. A `status` of `active` or `trialing` means the Lore+
/// gate is open.
/// `GET /rest/v1/entitlements?entitlement=eq.plus` (with a user bearer token)
///
/// Live columns: `user_id`, `entitlement`, `status`, `expires_at`,
/// `environment`.
struct Entitlement: Codable, Identifiable, Hashable {
    /// Canonical Lore+ grant name. Product ids keep the `lore_plus_*` prefix, but
    /// the entitlement row itself is the cross-platform `plus` grant.
    static let plusName = "plus"

    let userID: String
    /// The grant name (`plus`, …).
    let entitlement: String
    /// `active` | `trialing` | `expired` | `refunded` | `grace` | …
    let status: Status
    /// Apple transaction environment. Legacy non-Apple grants predate this
    /// column and decode as `nil` so they remain compatible.
    let environment: Environment?
    /// When this grant's paid window closes. `nil` means open-ended (a lifetime
    /// purchase or a founder comp). Enforced in `isActive` so a stale server
    /// `active`/`grace` row — a Trip Pass with no Apple expiry event, or a
    /// dropped EXPIRED webhook — can no longer over-grant Plus (audit docs/30).
    let expiresAt: Date?

    /// One row per (user, entitlement).
    var id: String { "\(userID)#\(entitlement)" }

    enum CodingKeys: String, CodingKey {
        case entitlement, status
        case userID = "user_id"
        case expiresAt = "expires_at"
        case environment
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        entitlement = try container.decode(String.self, forKey: .entitlement)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .unknown
        environment = try container.decodeIfPresent(Environment.self, forKey: .environment)
        // Null or missing expiration supports an open-ended grant; malformed
        // timestamps fail closed instead of turning into lifetime access.
        if let raw = try? container.decode(String.self, forKey: .expiresAt) {
            guard let parsed = Entitlement.iso8601.date(from: raw)
                ?? ISO8601DateFormatter().date(from: raw) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .expiresAt, in: container, debugDescription: "Invalid entitlement expiration"
                )
            }
            expiresAt = parsed
        } else if let legacy = try? container.decode(Double.self, forKey: .expiresAt) {
            // v2 cache records used JSONEncoder's numeric reference-date format.
            expiresAt = Date(timeIntervalSinceReferenceDate: legacy)
        } else if !container.contains(.expiresAt) || (try? container.decodeNil(forKey: .expiresAt)) == true {
            expiresAt = nil
        } else {
            throw DecodingError.dataCorruptedError(
                forKey: .expiresAt, in: container, debugDescription: "Invalid entitlement expiration"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(userID, forKey: .userID)
        try container.encode(entitlement, forKey: .entitlement)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(environment, forKey: .environment)
        try container.encodeIfPresent(expiresAt.map { Self.iso8601.string(from: $0) }, forKey: .expiresAt)
    }

    init(
        userID: String,
        entitlement: String,
        status: Status,
        expiresAt: Date? = nil,
        environment: Environment? = nil
    ) {
        self.userID = userID
        self.entitlement = entitlement
        self.status = status
        self.expiresAt = expiresAt
        self.environment = environment
    }

    /// Postgres `timestamptz` serializes with fractional seconds; a plain
    /// ISO8601DateFormatter rejects those, so parse with fractional support first.
    private static let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Entitlement lifecycle states. Billing grace remains entitled while
    /// Apple retries payment; expiration and cancellation fail closed unless
    /// StoreKit still reports a current transaction for the paid-through term.
    enum Status: String, Codable, Hashable {
        case active
        case trialing
        case expired
        case refunded
        case canceled
        case gracePeriod = "grace"
        case unknown

        /// Forward-compatible: unrecognized statuses decode as `.unknown`
        /// (which does NOT unlock, failing closed). Accepts the legacy
        /// `grace_period` spelling as well as the canonical server `grace`.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            if raw == "grace_period" { self = .gracePeriod; return }
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    /// Apple names transaction environments with title-case strings in signed
    /// transaction data. Unknown non-null values fail closed; only a missing
    /// value is treated as a compatible legacy non-Apple grant.
    enum Environment: String, Codable, Hashable {
        case production = "Production"
        case sandbox = "Sandbox"
        case unknown

        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            switch raw.lowercased() {
            case "production": self = .production
            case "sandbox": self = .sandbox
            default: self = .unknown
            }
        }
    }

    /// True when this grant currently confers access. A billing grace period is
    /// paid access under Apple's subscription lifecycle and must not strand a
    /// traveler while the App Store retries payment — but an expired window
    /// never unlocks, even if the stored status still reads active/grace.
    func isActive(asOf now: Date = Date()) -> Bool {
        guard entitlement == Self.plusName else { return false }
        let statusGrants = status == .active || status == .trialing || status == .gracePeriod
        guard statusGrants else { return false }
        if let expiresAt { return expiresAt > now }
        return true
    }

    /// Non-parameterized accessor for call sites that don't thread a clock.
    var isActive: Bool { isActive() }
}

/// Controls which server-side Apple entitlement environments may unlock this
/// installation. App Store builds accept Production rows only. TestFlight and
/// local sandbox builds accept both Production and Sandbox rows.
struct EntitlementEnvironmentPolicy: Equatable {
    enum Runtime: Equatable {
        case production
        case sandbox
    }

    let runtime: Runtime

    static let production = EntitlementEnvironmentPolicy(runtime: .production)
    static let sandbox = EntitlementEnvironmentPolicy(runtime: .sandbox)

    static var current: EntitlementEnvironmentPolicy {
        resolved(
            receiptURL: Bundle.main.appStoreReceiptURL,
            isDebugBuild: isDebugBuild
        )
    }

    /// Kept parameterized so release/TestFlight detection can be tested without
    /// depending on the host test bundle's receipt or build configuration.
    static func resolved(
        receiptURL: URL?,
        isDebugBuild: Bool
    ) -> EntitlementEnvironmentPolicy {
        if isDebugBuild || receiptURL?.lastPathComponent.lowercased() == "sandboxreceipt" {
            return .sandbox
        }
        return .production
    }

    func allows(_ entitlement: Entitlement) -> Bool {
        switch entitlement.environment {
        case nil, .production:
            return true
        case .sandbox:
            return runtime == .sandbox
        case .unknown:
            return false
        }
    }

    func grantsAccess(_ entitlement: Entitlement, asOf now: Date) -> Bool {
        allows(entitlement) && entitlement.isActive(asOf: now)
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }
}

import Foundation

/// Row shape of the `entitlements` table — a user's paid access grants. Own
/// rows only, via RLS. A `status` of `active` or `trialing` means the Lore+
/// gate is open.
/// `GET /rest/v1/entitlements` (with a user bearer token)
///
/// Live columns: `user_id`, `entitlement`, `status`.
struct Entitlement: Codable, Identifiable, Hashable {
    let userID: String
    /// The grant name (`lore_plus`, …).
    let entitlement: String
    /// `active` | `trialing` | `expired` | `canceled` | `grace_period` | …
    let status: Status

    /// One row per (user, entitlement).
    var id: String { "\(userID)#\(entitlement)" }

    enum CodingKeys: String, CodingKey {
        case entitlement, status
        case userID = "user_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        entitlement = try container.decode(String.self, forKey: .entitlement)
        status = try container.decodeIfPresent(Status.self, forKey: .status) ?? .unknown
    }

    init(userID: String, entitlement: String, status: Status) {
        self.userID = userID
        self.entitlement = entitlement
        self.status = status
    }

    /// Entitlement lifecycle states. `active` and `trialing` unlock Lore+.
    enum Status: String, Codable, Hashable {
        case active
        case trialing
        case expired
        case canceled
        case gracePeriod = "grace_period"
        case unknown

        /// Forward-compatible: unrecognized statuses decode as `.unknown`
        /// (which does NOT unlock, failing closed).
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Status(rawValue: raw) ?? .unknown
        }
    }

    /// True when this grant currently confers access (the only two states the
    /// backend contract says open Lore+).
    var isActive: Bool {
        status == .active || status == .trialing
    }
}

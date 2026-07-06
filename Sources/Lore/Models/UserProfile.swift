import Foundation

/// Row shape of `user_profile` (own row readable via RLS; mirrors
/// `lore-web/lib/types.ts`).
struct UserProfile: Codable, Identifiable, Hashable {
    let id: String
    let handle: String
    let displayName: String?
    let avatarURL: String?
    let bio: String?
    /// 'scout' | 'guide' | 'historian' | 'curator', the trust ladder
    /// (lore/docs/06-CROWDSOURCING.md).
    let trustTier: String
    let insightPoints: Int
    let claAcceptedAt: String?
    let claVersion: String?
    let createdAt: String
    let updatedAt: String

    enum CodingKeys: String, CodingKey {
        case id, handle, bio
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case trustTier = "trust_tier"
        case insightPoints = "insight_points"
        case claAcceptedAt = "cla_accepted_at"
        case claVersion = "cla_version"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    var displayNameOrHandle: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return "@\(handle)"
    }

    var trustTierLabel: String { trustTier.uppercased() }
}

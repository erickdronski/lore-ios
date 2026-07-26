import Foundation

/// Row shape of `user_profile` (own row readable via RLS; mirrors
/// `lore-web/lib/types.ts`).
struct UserProfile: Codable, Identifiable, Hashable {
    let id: String
    let handle: String?
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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        handle = Self.nonempty(try container.decodeIfPresent(String.self, forKey: .handle))
        displayName = Self.nonempty(try container.decodeIfPresent(String.self, forKey: .displayName))
        avatarURL = Self.nonempty(try container.decodeIfPresent(String.self, forKey: .avatarURL))
        bio = Self.nonempty(try container.decodeIfPresent(String.self, forKey: .bio))
        trustTier = try container.decodeIfPresent(String.self, forKey: .trustTier) ?? "scout"
        insightPoints = max(0, try container.decodeIfPresent(Int.self, forKey: .insightPoints) ?? 0)
        claAcceptedAt = try container.decodeIfPresent(String.self, forKey: .claAcceptedAt)
        claVersion = try container.decodeIfPresent(String.self, forKey: .claVersion)
        createdAt = try container.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    init(
        id: String,
        handle: String? = nil,
        displayName: String? = nil,
        avatarURL: String? = nil,
        bio: String? = nil,
        trustTier: String = "scout",
        insightPoints: Int = 0,
        claAcceptedAt: String? = nil,
        claVersion: String? = nil,
        createdAt: String = "",
        updatedAt: String = ""
    ) {
        self.id = id
        self.handle = Self.nonempty(handle)
        self.displayName = Self.nonempty(displayName)
        self.avatarURL = Self.nonempty(avatarURL)
        self.bio = Self.nonempty(bio)
        self.trustTier = trustTier
        self.insightPoints = max(0, insightPoints)
        self.claAcceptedAt = claAcceptedAt
        self.claVersion = claVersion
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var displayNameOrHandle: String {
        if let displayName { return displayName }
        if let handle { return "@\(handle)" }
        return "Lore traveler"
    }

    var trustTierLabel: String { trustTier.uppercased() }

    var initials: String {
        let words = displayNameOrHandle
            .replacingOccurrences(of: "@", with: "")
            .split(whereSeparator: \.isWhitespace)
        let letters = words.prefix(2).compactMap(\.first)
        return letters.isEmpty ? "L" : String(letters).uppercased()
    }

    /// Remote avatars are display-only and must use encrypted transport.
    var secureAvatarURL: URL? {
        guard let avatarURL,
              let url = URL(string: avatarURL),
              url.scheme?.lowercased() == "https" else { return nil }
        return url
    }

    /// The three identity fields travelers can maintain in-app.
    var completedIdentityFieldCount: Int {
        [displayName, handle, bio].compactMap { $0 }.count
    }

    var identityCompletionFraction: Double {
        Double(completedIdentityFieldCount) / 3.0
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else { return nil }
        return normalized
    }

    // MARK: - Editable identity

    struct Edit: Equatable, Encodable {
        static let displayNameLimit = 60
        static let bioLimit = 280

        let displayName: String?
        let handle: String?
        let bio: String?

        enum CodingKeys: String, CodingKey {
            case displayName = "display_name"
            case handle, bio
        }

        init(displayName: String, handle: String, bio: String) throws {
            let cleanName = Self.clean(displayName)
            let cleanHandle = Self.clean(handle)
                .map { String($0.drop(while: { $0 == "@" })).lowercased() }
            let cleanBio = Self.clean(bio)

            if let cleanName, cleanName.count > Self.displayNameLimit {
                throw ValidationError.displayNameTooLong
            }
            if let cleanHandle,
               cleanHandle.range(of: "^[a-z0-9_]{3,24}$", options: .regularExpression) == nil {
                throw ValidationError.invalidHandle
            }
            if let cleanBio, cleanBio.count > Self.bioLimit {
                throw ValidationError.bioTooLong
            }

            self.displayName = cleanName
            self.handle = cleanHandle
            self.bio = cleanBio
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(displayName, forKey: .displayName)
            try container.encode(handle, forKey: .handle)
            try container.encode(bio, forKey: .bio)
        }

        private static func clean(_ value: String) -> String? {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
    }

    enum ValidationError: LocalizedError, Equatable {
        case displayNameTooLong
        case invalidHandle
        case bioTooLong

        var errorDescription: String? {
            switch self {
            case .displayNameTooLong:
                return "Display name must be \(Edit.displayNameLimit) characters or fewer."
            case .invalidHandle:
                return "Username must be 3-24 lowercase letters, numbers, or underscores."
            case .bioTooLong:
                return "Bio must be \(Edit.bioLimit) characters or fewer."
            }
        }
    }
}

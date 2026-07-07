import Foundation

/// Row shape of the `achievement` table, the catalog of earnable badges
/// (definitions only; a user's progress lives in `user_achievement`).
/// `GET /rest/v1/achievement?order=sort`
///
/// ```json
/// { "slug": "first-steps", "name": "First Steps",
///   "description": "Log your very first visit", "emoji": "👣",
///   "category": "milestone", "tier": "bronze",
///   "criteria": { "n": 1, "type": "visit_count" }, "points": 10,
///   "secret": false, "sort": 1 }
/// ```
///
/// The table's stable identity is `slug` (no `id` column); `user_achievement`
/// joins back on `achievement_slug`.
struct Achievement: Codable, Identifiable, Hashable {
    let slug: String
    let name: String
    let description: String?
    let emoji: String?
    /// Grouping bucket (`milestone`, `explorer`, `collector`, …).
    let category: String?
    /// `bronze` | `silver` | `gold` | `platinum`, the badge tier.
    let tier: Tier
    /// Machine-readable unlock rule, e.g. `{ "n": 10, "type": "visit_count" }`.
    /// Kept as a flexible value bag so a new criteria type never breaks decode.
    let criteria: JSONValue?
    /// Insight points awarded on unlock.
    let points: Int
    /// Hidden until earned (surprise badges); render as "???" while locked.
    let secret: Bool
    let sort: Int?

    /// `slug` is the identity, the table has no `id` column.
    var id: String { slug }

    enum CodingKeys: String, CodingKey {
        case slug, name, description, emoji, category, tier, criteria, points, secret, sort
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        slug = try container.decode(String.self, forKey: .slug)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        emoji = try container.decodeIfPresent(String.self, forKey: .emoji)
        category = try container.decodeIfPresent(String.self, forKey: .category)
        tier = try container.decodeIfPresent(Tier.self, forKey: .tier) ?? .bronze
        criteria = try container.decodeIfPresent(JSONValue.self, forKey: .criteria)
        points = try container.decodeIfPresent(Int.self, forKey: .points) ?? 0
        secret = try container.decodeIfPresent(Bool.self, forKey: .secret) ?? false
        sort = try container.decodeIfPresent(Int.self, forKey: .sort)
    }

    /// Badge tiers, ordered, `Comparable` so UIs can sort/rank by prestige.
    enum Tier: String, Codable, Hashable, CaseIterable, Comparable {
        case bronze, silver, gold, platinum

        /// Forward-compatible: unknown tiers fall back to `.bronze`.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Tier(rawValue: raw) ?? .bronze
        }

        private var rank: Int {
            switch self {
            case .bronze: return 0
            case .silver: return 1
            case .gold: return 2
            case .platinum: return 3
            }
        }

        static func < (lhs: Tier, rhs: Tier) -> Bool { lhs.rank < rhs.rank }

        var label: String { rawValue.capitalized }
    }

    var displayEmoji: String {
        if let emoji, !emoji.isEmpty { return emoji }
        return "🏅"
    }

    /// A crisp SF Symbol per badge, drawn on the medallion instead of an emoji
    /// (scalable, tintable, professional). Unknown slugs fall back by category,
    /// then a rosette; an unknown symbol renders blank rather than crashing.
    var symbolName: String {
        switch slug {
        case "first-steps": return "shoeprints.fill"
        case "getting-around": return "figure.walk"
        case "city-slicker": return "building.2.fill"
        case "seasoned-wanderer": return "safari.fill"
        case "centurion": return "trophy.fill"
        case "living-atlas": return "map.fill"
        case "two-cities": return "building.2.crop.circle.fill"
        case "city-hopper": return "airplane"
        case "passport-stamped": return "airplane.circle.fill"
        case "globetrotter": return "globe.americas.fill"
        case "grand-tour": return "globe.europe.africa.fill"
        case "windy-city-native": return "wind"
        case "empire-explorer": return "building.fill"
        case "city-of-brotherly-love": return "bell.fill"
        case "bridge-walker": return "figure.walk.motion"
        case "park-ranger": return "leaf.fill"
        case "forest-bather": return "tree.fill"
        case "statue-spotter": return "figure.stand"
        case "museum-member": return "building.columns.fill"
        case "deco-detective": return "magnifyingglass"
        case "gothic-soul": return "building.columns.fill"
        case "sky-high": return "building.2.fill"
        case "engineer-eye": return "gearshape.fill"
        case "star-map": return "film.fill"
        case "encore": return "guitars.fill"
        case "encore-encore": return "music.mic"
        case "record-keeper": return "rosette"
        case "patron": return "paintpalette.fill"
        case "survivor-seeker": return "shield.fill"
        case "ghost-hunter", "night-owl": return "moon.stars.fill"
        case "last-call": return "wineglass.fill"
        case "stage-door": return "theatermasks.fill"
        case "take-me-out": return "baseball.fill"
        case "curious-mind": return "book.fill"
        case "scholar": return "graduationcap.fill"
        case "docent": return "books.vertical.fill"
        case "local-lingo": return "text.bubble.fill"
        case "star-struck": return "star.fill"
        case "on-a-roll", "unstoppable": return "flame.fill"
        case "weekend-wanderer": return "calendar"
        case "completionist": return "checkmark.seal.fill"
        case "first-to-chronicle": return "square.and.pencil"
        default:
            switch category {
            case "collector": return "square.stack.3d.up.fill"
            case "milestone": return "flag.checkered"
            case "city": return "building.2.fill"
            case "knowledge": return "book.fill"
            case "streak": return "flame.fill"
            case "special": return "sparkles"
            default: return "rosette"
            }
        }
    }

    /// The `type` field inside `criteria` (`visit_count`, `city_count`, …),
    /// if the criteria is an object with a string `type`.
    var criteriaType: String? {
        if case .object(let dict)? = criteria, case .string(let t)? = dict["type"] {
            return t
        }
        return nil
    }

    /// The numeric target inside `criteria` (`n`), if present, the default
    /// `target` when a `user_achievement` row hasn't set its own.
    var criteriaTarget: Int? {
        if case .object(let dict)? = criteria, case .number(let n)? = dict["n"] {
            return Int(n)
        }
        return nil
    }
}

/// Row shape of the `user_achievement` table, a signed-in user's progress
/// toward (and unlock time of) each achievement. Own rows only, via RLS.
/// `GET /rest/v1/user_achievement` (with a user bearer token)
///
/// Live columns: `user_id`, `achievement_slug`, `progress`, `target`,
/// `unlocked_at`.
struct UserAchievement: Codable, Identifiable, Hashable {
    let userID: String
    /// Foreign key back to `achievement.slug`.
    let achievementSlug: String
    /// How far along (e.g. 7 of 10 visits).
    let progress: Int
    /// The goal (mirrors `achievement.criteria.n` at grant time).
    let target: Int
    /// When earned; nil ⇒ still in progress.
    let unlockedAt: String?

    /// Composite identity: one row per (user, achievement).
    var id: String { "\(userID)#\(achievementSlug)" }

    enum CodingKeys: String, CodingKey {
        case progress, target
        case userID = "user_id"
        case achievementSlug = "achievement_slug"
        case unlockedAt = "unlocked_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        userID = try container.decode(String.self, forKey: .userID)
        achievementSlug = try container.decode(String.self, forKey: .achievementSlug)
        progress = try container.decodeIfPresent(Int.self, forKey: .progress) ?? 0
        target = try container.decodeIfPresent(Int.self, forKey: .target) ?? 0
        unlockedAt = try container.decodeIfPresent(String.self, forKey: .unlockedAt)
    }

    init(
        userID: String,
        achievementSlug: String,
        progress: Int,
        target: Int,
        unlockedAt: String? = nil
    ) {
        self.userID = userID
        self.achievementSlug = achievementSlug
        self.progress = progress
        self.target = target
        self.unlockedAt = unlockedAt
    }

    /// True once earned.
    var isUnlocked: Bool { unlockedAt != nil }

    /// Progress as a 0…1 fraction (guards divide-by-zero and clamps).
    var fraction: Double {
        guard target > 0 else { return isUnlocked ? 1 : 0 }
        return min(1, max(0, Double(progress) / Double(target)))
    }
}

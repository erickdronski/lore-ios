import Foundation

/// Row shape of the publicly readable `fact` table, the dive dossier's raw
/// provenance rows (mirrors `lore-web/lib/types.ts`). `value` is jsonb and can
/// be a string, number, or object, hence `JSONValue`.
struct Fact: Codable, Identifiable, Hashable {
    let id: String
    let placeID: String
    /// Constrained key registry (docs/04 §2): `name`, `hook`, `built_year`,
    /// `architect`, `style`, `height_m`, `nrhp_ref`, `story:<slug>`, …
    let key: String
    let value: JSONValue
    let lang: String?
    let source: String?
    let sourceURL: String?
    let license: String?
    let contributorID: String?
    let confidence: Double?
    let verifyState: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, key, value, lang, source, license, confidence
        case placeID = "place_id"
        case sourceURL = "source_url"
        case contributorID = "contributor_id"
        case verifyState = "verify_state"
        case createdAt = "created_at"
    }

    /// Best-effort human-readable rendering of the jsonb value.
    var displayValue: String { value.displayString }
}

/// Minimal Codable representation of an arbitrary jsonb value.
enum JSONValue: Codable, Hashable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported jsonb value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    var displayString: String {
        switch self {
        case .string(let s): return s
        case .number(let n):
            return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return b ? "yes" : "no"
        case .object(let o):
            return o.map { "\($0.key): \($0.value.displayString)" }
                .sorted()
                .joined(separator: ", ")
        case .array(let a):
            return a.map(\.displayString).joined(separator: ", ")
        case .null: return "-"
        }
    }
}

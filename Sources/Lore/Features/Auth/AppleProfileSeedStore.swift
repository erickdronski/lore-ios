import Foundation
import Security

/// Apple's name and relay email are only returned on the first authorization.
/// Preserve that one-time seed in the Keychain until the profile write surface
/// can consume it; process memory is not a safe holding area for this data.
struct AppleProfileSeed: Codable, Equatable {
    let userID: String
    let displayName: String?
    let email: String?

    static func make(
        userID: String,
        fullName: PersonNameComponents?,
        email: String?
    ) -> AppleProfileSeed? {
        let displayName = fullName.map {
            PersonNameComponentsFormatter().string(from: $0)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.flatMap { $0.isEmpty ? nil : $0 }
        let cleanEmail = email?.trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
        guard displayName != nil || cleanEmail != nil else { return nil }
        return AppleProfileSeed(userID: userID, displayName: displayName, email: cleanEmail)
    }
}

enum AppleProfileSeedStore {
    private static let service = "com.erickdronski.lore.auth.apple-profile"

    @discardableResult
    static func save(_ seed: AppleProfileSeed) -> Bool {
        guard let data = try? JSONEncoder().encode(seed) else { return false }
        let query = baseQuery(userID: seed.userID)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let update = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var add = query
        add.merge(attributes) { _, new in new }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func load(userID: String) -> AppleProfileSeed? {
        var query = baseQuery(userID: userID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let seed = try? JSONDecoder().decode(AppleProfileSeed.self, from: data) else {
            return nil
        }
        return seed
    }

    static func clear(userID: String) {
        SecItemDelete(baseQuery(userID: userID) as CFDictionary)
    }

    private static func baseQuery(userID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: userID,
        ]
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

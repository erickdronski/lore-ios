import Foundation
import Security

/// Keychain-backed persistence for the GoTrue session, so relaunching the app
/// keeps the user signed in (TestFlight feedback: "I already signed in, why am
/// I being asked to sign in again"). The whole encoded `AuthSession` is stored
/// under one generic-password item, readable after first unlock.
enum SessionStore {
    private static let service = "com.erickdronski.lore.auth"
    private static let account = "gotrue-session"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    static func save(_ session: AuthSession) -> Bool {
        guard let data = try? JSONEncoder().encode(session) else { return false }
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return true }
        guard updateStatus == errSecItemNotFound else { return false }

        var add = baseQuery
        add.merge(update) { _, new in new }
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func load() -> AuthSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        guard let session = try? JSONDecoder().decode(AuthSession.self, from: data) else {
            clear()
            return nil
        }
        return session
    }

    static func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

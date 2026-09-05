import Foundation
import Observation

struct CachedEntitlementRecord: Codable, Equatable {
    let entitlement: Entitlement
    let verifiedAt: Date
}

enum EntitlementCachePolicy {
    /// A short resilience window prevents a transient backend outage from
    /// locking out a traveler while still bounding stale server grants. Native
    /// StoreKit transactions remain the longer-lived offline source of truth.
    static let maximumAge: TimeInterval = 72 * 60 * 60

    static func usable(
        _ record: CachedEntitlementRecord?,
        for userID: String?,
        now: Date,
        environmentPolicy: EntitlementEnvironmentPolicy
    ) -> Entitlement? {
        guard let record,
              let userID,
              record.entitlement.userID == userID,
              environmentPolicy.grantsAccess(record.entitlement, asOf: now),
              now.timeIntervalSince(record.verifiedAt) >= 0,
              now.timeIntervalSince(record.verifiedAt) <= maximumAge
        else { return nil }
        return record.entitlement
    }

    /// Supabase access tokens are signed JWTs. Decoding the subject here does
    /// not establish trust; it only identity-binds an already local cache to
    /// the same authenticated session and prevents account crossover.
    static func userID(fromJWT token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var encoded = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        encoded += String(repeating: "=", count: (4 - encoded.count % 4) % 4)
        guard let data = Data(base64Encoded: encoded),
              let payload = try? JSONDecoder().decode(JWTPayload.self, from: data)
        else { return nil }
        return payload.sub
    }

    private struct JWTPayload: Decodable {
        let sub: String
    }
}

/// Combines identity-bound server membership with verified device purchases.
/// Server fallback retains its verification timestamp and is rechecked on every
/// read. A request generation prevents old accounts and cancelled tasks from
/// publishing after sign-out or a newer refresh.
@Observable
@MainActor
final class EntitlementStore {
    typealias EntitlementLoader = (String) async throws -> Entitlement?

    private enum CacheKey {
        static let verifiedEntitlement = "lore.premium.cachedEntitlement.v2"
    }

    private(set) var entitlement: Entitlement?
    var storeKit: StoreKitService?
    private(set) var isRefreshing = false
    private(set) var lastError: String?

    private let defaults: UserDefaults
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private let entitlementLoader: EntitlementLoader
    private let environmentPolicy: EntitlementEnvironmentPolicy
    private var cachedRecord: CachedEntitlementRecord?
    private var usingCache = false
    private var activeUserID: String?
    private var refreshGeneration: UInt64 = 0
    private var expirationRevision = 0
    @ObservationIgnored private var expirationTask: Task<Void, Never>?

    private var currentDate: Date {
        _ = expirationRevision
        return now()
    }

    private var usableCachedEntitlement: Entitlement? {
        guard usingCache else { return nil }
        return EntitlementCachePolicy.usable(
            cachedRecord, for: activeUserID, now: currentDate,
            environmentPolicy: environmentPolicy
        )
    }

    var isUsingCachedEntitlement: Bool { usableCachedEntitlement != nil }

    var isPlus: Bool {
        #if DEBUG
        if Self.devForcePlus { return true }
        #endif
        let server = entitlement.map {
            environmentPolicy.grantsAccess($0, asOf: currentDate)
        } ?? false
        return server || usableCachedEntitlement != nil || (storeKit?.hasActiveEntitlement ?? false)
    }

    #if DEBUG
    static var devForcePlus: Bool {
        ProcessInfo.processInfo.environment["LORE_DEV_PLUS"] == "1"
            || UserDefaults.standard.bool(forKey: "lore.dev.forcePlus")
    }
    #endif

    var isTrialing: Bool {
        let server = entitlement.map {
            $0.status == .trialing && environmentPolicy.grantsAccess($0, asOf: currentDate)
        } ?? false
        return server || usableCachedEntitlement?.status == .trialing
            || (storeKit?.isInIntroPeriod ?? false)
    }

    init(
        entitlement: Entitlement? = nil,
        defaults: UserDefaults = .standard,
        now: @escaping () -> Date = Date.init,
        environmentPolicy: EntitlementEnvironmentPolicy = .current,
        entitlementLoader: @escaping EntitlementLoader = { token in
            try await LoreAPI.shared.entitlement(accessToken: token)
        }
    ) {
        self.entitlement = entitlement
        self.activeUserID = entitlement?.userID
        self.defaults = defaults
        self.now = now
        self.environmentPolicy = environmentPolicy
        self.entitlementLoader = entitlementLoader
        if let data = defaults.data(forKey: CacheKey.verifiedEntitlement) {
            cachedRecord = try? JSONDecoder().decode(CachedEntitlementRecord.self, from: data)
        }
        scheduleExpiration()
    }

    deinit { expirationTask?.cancel() }

    /// Change identity before any suspension, then reconcile device/server state.
    func refresh(accessToken: String?) async {
        guard !Task.isCancelled else { return }
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let userID = accessToken.flatMap(EntitlementCachePolicy.userID(fromJWT:))
        if activeUserID != userID {
            entitlement = nil
            usingCache = false
        }
        activeUserID = userID
        lastError = nil
        isRefreshing = accessToken != nil && userID != nil
        defer {
            if generation == refreshGeneration {
                isRefreshing = false
                scheduleExpiration()
            }
        }

        guard let accessToken, let userID else {
            entitlement = nil
            usingCache = false
            await storeKit?.refreshEntitlements()
            return
        }
        await storeKit?.refreshEntitlements()
        guard generation == refreshGeneration, !Task.isCancelled else { return }
        do {
            let result = try await entitlementLoader(accessToken)
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            guard result == nil || result?.userID == userID else {
                throw LoreAPI.APIError.invalidResponse
            }
            entitlement = result
            usingCache = false
            if let result {
                persist(result, verifiedAt: now())
            } else if cachedRecord?.entitlement.userID == userID {
                removeCachedRecord()
            }
        } catch {
            guard generation == refreshGeneration, !Task.isCancelled,
                  !(error is CancellationError),
                  (error as? URLError)?.code != .cancelled else { return }
            entitlement = nil
            // An explicit auth rejection is not an offline membership verdict.
            if case LoreAPI.APIError.http(let status, _) = error, [401, 403].contains(status) {
                usingCache = false
                if cachedRecord?.entitlement.userID == userID { removeCachedRecord() }
            } else {
                usingCache = true
            }
            lastError = isUsingCachedEntitlement
                ? "You're offline. Recently verified membership is available for up to 72 hours."
                : "Couldn't verify your membership. Free Lore remains available while you reconnect."
        }
    }

    /// Invalidate pending responses synchronously; device purchases retain their
    /// independent Apple-account access according to StoreKitService's policy.
    func clear() {
        refreshGeneration &+= 1
        activeUserID = nil
        entitlement = nil
        usingCache = false
        lastError = nil
        isRefreshing = false
        expirationTask?.cancel()
        expirationTask = nil
    }

    private func persist(_ entitlement: Entitlement, verifiedAt: Date) {
        let record = CachedEntitlementRecord(entitlement: entitlement, verifiedAt: verifiedAt)
        cachedRecord = record
        if let data = try? JSONEncoder().encode(record) {
            defaults.set(data, forKey: CacheKey.verifiedEntitlement)
        }
    }

    private func removeCachedRecord() {
        cachedRecord = nil
        usingCache = false
        defaults.removeObject(forKey: CacheKey.verifiedEntitlement)
    }

    /// Wake observable UI gates at expiry, including while no network work occurs.
    private func scheduleExpiration() {
        expirationTask?.cancel()
        expirationTask = nil
        var deadlines = [entitlement?.expiresAt].compactMap { $0 }
        if usingCache, let record = cachedRecord {
            deadlines.append(record.verifiedAt.addingTimeInterval(EntitlementCachePolicy.maximumAge))
            if let expiry = record.entitlement.expiresAt { deadlines.append(expiry) }
        }
        guard let next = deadlines.filter({ $0 > now() }).min() else { return }
        let delay = max(0.01, next.timeIntervalSince(now()))
        expirationTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(delay)) } catch { return }
            guard let self else { return }
            self.expirationRevision &+= 1
            self.scheduleExpiration()
        }
    }
}

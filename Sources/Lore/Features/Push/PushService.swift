import Foundation
import Observation
import UserNotifications
import UIKit

/// A validated in-app destination extracted from an APNs/local-notification
/// payload. Unknown schemes and malformed identifiers are ignored rather than
/// handed to UIApplication.
enum PushDestination: Equatable {
    case place(String)
    case tour(String)
    case map(city: String?)

    var url: URL? {
        var components = URLComponents()
        components.scheme = "lore"
        switch self {
        case .place(let id):
            components.host = "place"
            components.path = "/\(id)"
        case .tour(let slug):
            components.host = "tour"
            components.path = "/\(slug)"
        case .map(let city):
            components.host = "map"
            if let city { components.queryItems = [URLQueryItem(name: "city", value: city)] }
        }
        return components.url
    }

    static func parse(_ userInfo: [AnyHashable: Any]) -> PushDestination? {
        if let raw = userInfo["deep_link"] as? String,
           let direct = parseLoreURL(raw) {
            return direct
        }

        switch userInfo["type"] as? String {
        case "nearby_lore":
            return clean(userInfo["place_id"] as? String).map(PushDestination.place)
        case "new_city":
            return .map(city: clean(userInfo["city"] as? String))
        case "tour_reminder":
            return clean(userInfo["tour_slug"] as? String).map(PushDestination.tour)
        default:
            return nil
        }
    }

    private static func parseLoreURL(_ raw: String) -> PushDestination? {
        guard let url = URL(string: raw), url.scheme?.lowercased() == "lore" else { return nil }
        let segments = url.pathComponents.filter { $0 != "/" }
        switch url.host?.lowercased() {
        case "place":
            guard segments.count == 1 else { return nil }
            return clean(segments[0]).map(PushDestination.place)
        case "tour":
            guard segments.count == 1 else { return nil }
            return clean(segments[0]).map(PushDestination.tour)
        case "map":
            guard segments.isEmpty else { return nil }
            let city = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "city" })?.value
            return .map(city: clean(city))
        default: return nil
        }
    }

    private static func clean(_ raw: String?) -> String? {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty,
              value.count <= 200,
              !value.contains("/")
        else { return nil }
        return value
    }
}

/// The push-notification client scaffold (docs/16-APPLE-TOOLKITS.md §5): request
/// notification authorization, register for remote notifications, and hold the
/// APNs device token once the system hands it back.
///
/// Scope (docs/16 §5): this is the **client half**. It gets the app ready to
/// *receive* the "nearby-lore / new-city" retention pushes. The **server sender**
///, a Supabase Edge Function that signs an APNs JWT with the token-auth `.p8`
/// key and POSTs to `api.push.apple.com`, is a TODO owned server-side (see the
/// TODO on `registerTokenWithBackend`). The `remote-notification` background
/// mode is set in `project.yml`; the Push *capability* + `aps-environment`
/// entitlement are portal-gated and commented in `project.yml`.
///
/// Consent doctrine (docs/16 §5, docs/09 §5.2): notifications are opt-in and the
/// onboarding flow already collects the intent. This service only *asks* the
/// system for authorization when the app decides to (post-onboarding), never at
/// cold launch, so we don't burn the one-shot prompt.
///
/// Two proximity paths exist (docs/16 §5): the **preferred on-device** one
/// (`CLMonitor` geofence → *local* notification, no APNs, no server) and this
/// **remote** one (server-targeted). Local notifications also flow through this
/// service's `UNUserNotificationCenter` delegate.
@Observable
@MainActor
final class PushService: NSObject {
    /// Kinds of push the app cares about (matches the server payload `type`).
    enum Category: String {
        /// "You're near a place with a story you haven't read."
        case nearbyLore = "nearby_lore"
        /// "Lore just launched in <city>."
        case newCity = "new_city"
    }

    /// The current notification authorization status (mirrors the system).
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// The APNs device token as a hex string, once registered. `nil` until the
    /// system delivers it (or on the simulator, which has no APNs token).
    private(set) var deviceToken: String?

    /// Set when registration failed, non-fatal, surfaced only if useful.
    private(set) var lastError: String?

    /// True once the user has granted notification authorization.
    var isAuthorized: Bool {
        authorizationStatus == .authorized
            || authorizationStatus == .provisional
            || authorizationStatus == .ephemeral
    }

    var educationText: String {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Lore nudges are on. Alerts are designed to be occasional and relevant."
        case .denied:
            return "Notifications are off in Settings. Lore still works normally without them."
        case .notDetermined:
            return "Lore can explain nearby-story nudges before asking for notification access."
        @unknown default:
            return "Notification status is unavailable right now."
        }
    }

    /// Refresh the cached authorization status from the system. Call on
    /// foreground so a Settings-side change is reflected.
    func refreshAuthorizationStatus(registerIfAuthorized: Bool = false) async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if registerIfAuthorized, isAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    /// Ask the user for notification permission, then register for remote
    /// notifications if granted. Call this from the onboarding notification step
    /// (or a Profile toggle), never at cold launch (docs/16 §5).
    ///
    /// Registration triggers the `AppDelegate` APNs callbacks, which call back
    /// into `didRegister(tokenData:)` / `didFailToRegister(error:)` here.
    func requestAuthorizationAndRegister() async {
        await refreshAuthorizationStatus()
        if authorizationStatus == .denied {
            lastError = "Notifications are off in Settings. Turn them on there whenever you want nearby-story nudges."
            return
        }
        if isAuthorized {
            lastError = nil
            UIApplication.shared.registerForRemoteNotifications()
            return
        }
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await refreshAuthorizationStatus()
            guard granted else {
                lastError = "Notifications remain off. Lore still works normally, and you can enable nudges later in Settings."
                return
            }
            // Must run on the main thread; registration is a UIApplication call.
            UIApplication.shared.registerForRemoteNotifications()
        } catch {
            lastError = "Couldn't set up notifications. You can turn them on later in Settings."
        }
    }

    /// Set this app instance as the `UNUserNotificationCenter` delegate so
    /// foreground presentation + taps route here. Call once at launch.
    func becomeNotificationCenterDelegate() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(
                identifier: Category.nearbyLore.rawValue,
                actions: [UNNotificationAction(identifier: "EXPLORE_LORE", title: "Explore story")],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: Category.newCity.rawValue,
                actions: [UNNotificationAction(identifier: "EXPLORE_CITY", title: "Explore city")],
                intentIdentifiers: [],
                options: []
            ),
        ])
    }

    // MARK: - APNs token callbacks (called by AppDelegate)

    /// Store the freshly-issued APNs token and hand it to the backend.
    func didRegister(tokenData: Data) {
        let token = tokenData.map { String(format: "%02x", $0) }.joined()
        deviceToken = token
        lastError = nil
        Task { await registerTokenWithBackend(token) }
    }

    /// Record a registration failure (e.g. no network, simulator). Non-fatal.
    func didFailToRegister(error: Error) {
        #if targetEnvironment(simulator)
        lastError = "Push delivery requires a real iPhone. Notification UI can still be tested in Simulator."
        #else
        lastError = "Lore couldn't register this device for nudges. Check your connection and try again later."
        #endif
    }

    /// Send the APNs token to the backend so the server sender can target this
    /// device.
    ///
    /// TODO(P2/server, docs/16 §5): POST the token (+ the user id when signed in,
    /// + coarse city for new-city targeting) to a Supabase table/Edge Function.
    /// The **sender** is a separate Edge Function that signs the APNs JWT with
    /// the token-auth `.p8` and POSTs to `api.push.apple.com`. No third-party
    /// push vendor needed at our scale. This method is the client stub that
    /// makes the token available; the server pieces are not in this repo.
    private func registerTokenWithBackend(_ token: String) async {
        // Intentionally a no-op until the server endpoint exists. Kept as the
        // single seam so wiring the backend is a one-method change.
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushService: UNUserNotificationCenterDelegate {
    /// Present notifications while the app is foregrounded (banner + sound), so
    /// a proximity nudge that fires while the user is in-app is still seen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .list])
    }

    /// Handle a tap on a notification, deep-link into the matching surface.
    ///
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier,
              let destination = PushDestination.parse(response.notification.request.content.userInfo),
              let url = destination.url
        else {
            completionHandler()
            return
        }
        Task { @MainActor in
            UIApplication.shared.open(url)
            completionHandler()
        }
    }
}

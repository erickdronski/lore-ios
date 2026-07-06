import UIKit
import UserNotifications

/// The `UIApplicationDelegate` adaptor for the SwiftUI app, it exists **only**
/// to receive the APNs remote-notification token callbacks, which have no
/// SwiftUI-native equivalent (docs/16-APPLE-TOOLKITS.md §5).
///
/// It owns the single `PushService` and forwards the token / failure callbacks
/// to it. `LoreApp` installs this via `@UIApplicationDelegateAdaptor` and reads
/// `delegate.push` to inject the same instance into the environment, so the
/// onboarding notification step and the Profile toggle drive the same service
/// the delegate feeds.
final class AppDelegate: NSObject, UIApplicationDelegate {
    /// The app-wide push client. Created here so the delegate and the SwiftUI
    /// environment share one instance.
    let push = PushService()

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Become the notification-center delegate immediately so foreground
        // presentation + taps route through `PushService`. Authorization itself
        // is requested later, from onboarding (docs/16 §5, never at cold launch).
        Task { @MainActor in
            push.becomeNotificationCenterDelegate()
            await push.refreshAuthorizationStatus()
        }
        return true
    }

    /// APNs handed us a device token. Forward it to `PushService`, which hex-
    /// encodes it and (TODO server) registers it with the backend sender.
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in push.didRegister(tokenData: deviceToken) }
    }

    /// APNs registration failed (no network, simulator, revoked capability).
    /// Non-fatal, the app runs fine without push.
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in push.didFailToRegister(error: error) }
    }

    /// A silent / content push arrived. Left as a seam for the "new content
    /// nearby" background refresh.
    ///
    /// TODO(P2/server): inspect `userInfo["type"]` and refresh the relevant
    /// cache (e.g. re-pull near-me so the widget snapshot updates), then call
    /// the completion handler with the right `UIBackgroundFetchResult`.
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        completionHandler(.noData)
    }
}

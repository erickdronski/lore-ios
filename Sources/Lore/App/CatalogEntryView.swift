import SwiftUI

/// The bundled guide can open on a first install without remote configuration.
struct CatalogEntryView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PrefsCoordinator.self) private var prefs
    @Environment(AppRouter.self) private var router
    static let preferStarterKey = "lore.preferStarterGuide"
    @AppStorage(CatalogEntryView.preferStarterKey) private var preferStarter = false
    @AppStorage("lore.lastServiceFailure") private var lastFailure: Double = 0
    @State private var connected: Bool?
    @State private var startedExploring = false
    @State private var checking = false
    @State private var attempts = 0
    @State private var pendingLink: URL?
    @State private var launchLink: URL?

    var body: some View {
        Group {
            switch connected {
            case true:
                RootTabView()
                    .loreOnboarding(auth: auth, prefs: prefs)
                    .task {
                        if let pendingLink {
                            self.pendingLink = nil
                            router.handleDeepLink(pendingLink)
                        }
                    }
            default:
                StarterGuideView(checking: checking, tried: attempts > 1, pendingLink: $pendingLink,
                                 onInteraction: { startedExploring = true }) {
                    Task { await checkService(manual: true) }
                }
            }
        }
        .task { if connected == nil { await checkService(manual: false) } }
        .onChange(of: preferStarter) { _, enabled in
            if enabled { connected = false }
        }
        .onOpenURL { url in
            if connected == true { router.handleDeepLink(url) }
            else if url.scheme == "lore" {
                if connected == nil { launchLink = url } else { pendingLink = url }
            }
        }
    }

    @MainActor private func checkService(manual: Bool) async {
        guard !checking else { return }
        checking = true
        defer {
            checking = false
            if let launchLink {
                self.launchLink = nil
                pendingLink = launchLink
            }
        }
        attempts += 1
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-lore-starter-guide") {
            connected = false
            return
        }
        if ScreenshotSupport.isActive {
            connected = true
            return
        }
        #endif
        let age = Date().timeIntervalSince1970 - lastFailure
        if !manual && (preferStarter || (0..<900).contains(age)) {
            connected = false
            return
        }
        let live = await LoreServiceAvailability.shared.check()
        lastFailure = live ? 0 : Date().timeIntervalSince1970
        if live { preferStarter = false }
        connected = live && (manual || !startedExploring)
    }
}

import SwiftUI

/// The bundled guide can open on a first install without remote configuration.
struct CatalogEntryView: View {
    @Environment(AuthService.self) private var auth
    @Environment(PrefsCoordinator.self) private var prefs
    @Environment(AppRouter.self) private var router
    @State private var connected: Bool?
    @State private var checking = false
    @State private var attempts = 0
    @State private var pendingLink: URL?

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
            case false:
                StarterGuideView(checking: checking, tried: attempts > 1, pendingLink: $pendingLink) {
                    Task { await checkService() }
                }
            default:
                ProgressView("Opening Lore…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if connected == nil { await checkService() } }
        .onOpenURL { url in
            if connected == true { router.handleDeepLink(url) }
            else if url.scheme == "lore" { pendingLink = url }
        }
    }

    @MainActor private func checkService() async {
        guard !checking else { return }
        checking = true
        defer { checking = false }
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
        connected = await LoreServiceAvailability.shared.check()
    }
}

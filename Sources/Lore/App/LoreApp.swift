import SwiftUI

/// Lore — every place has a story.
///
/// Tab root for the P0 native scaffold: Map (the reviewable-from-anywhere
/// surface, docs/10 §5 row 4), Scanner (GPS+compass coarse mode, docs/05 §5
/// rung 2), Tours, Profile. The AR pipeline proper (ARKit + ARCore Geospatial
/// + RealityKit) replaces the Scanner tab's internals at P1 — the tab
/// structure and everything else here survives that swap.
@main
struct LoreApp: App {
    /// Single auth instance for the whole app — SignInView and ProfileScreen
    /// read it from the environment.
    @State private var auth = AuthService()

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environment(auth)
                // App chrome is the app's words — Ink/Brass, never Amber
                // (Amber is reserved for the world: pins, outlines, beacon —
                // brand/DESIGN.md §4). brass700 is the AA-safe brass on Bone.
                .tint(LoreColor.brass700)
        }
    }
}

struct RootTabView: View {
    enum Tab: Hashable {
        case map, scanner, tours, profile
    }

    @State private var selection: Tab = .map

    var body: some View {
        TabView(selection: $selection) {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map") }
                .tag(Tab.map)

            ScannerScreen()
                .tabItem { Label("Scanner", systemImage: "camera.viewfinder") }
                .tag(Tab.scanner)

            ToursScreen()
                .tabItem { Label("Tours", systemImage: "figure.walk") }
                .tag(Tab.tours)

            ProfileScreen()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
                .tag(Tab.profile)
        }
    }
}

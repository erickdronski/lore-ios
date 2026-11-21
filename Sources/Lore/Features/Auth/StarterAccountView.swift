import SwiftUI

/// The starter guide shares Settings' Apple restore, subscription management,
/// account deletion and support actions with the full app.
struct StarterAccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            SettingsView(starterAccountOnly: true)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .onChange(of: auth.session?.user.id, initial: true) { _, userID in
            entitlements.bindOfflineAccount(userID: userID)
        }
        .preferredColorScheme(.light)
    }
}

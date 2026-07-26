import SwiftUI

struct DeleteAccountView: View {
    @Environment(AuthService.self) private var auth
    @Environment(EntitlementStore.self) private var entitlements
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let onDeleted: () -> Void

    @State private var confirmation = ""
    @State private var understandsSubscription = false
    @State private var deleting = false
    @State private var failureMessage: String?
    @FocusState private var confirmationFocused: Bool

    private var canDelete: Bool {
        AccountDeletionConfirmation.isConfirmed(confirmation)
            && (!entitlements.isPlus || understandsSubscription)
            && !deleting
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    warningHeader
                    deletionManifest
                    subscriptionWarning
                    confirmationField

                    if let failureMessage {
                        failureCard(failureMessage)
                    }

                    Button(role: .destructive) {
                        confirmationFocused = false
                        Task { await deleteAccount() }
                    } label: {
                        HStack(spacing: 10) {
                            if deleting { ProgressView().tint(.white) }
                            Text(deleteButtonTitle)
                                .font(LoreType.button)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 52)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(LoreColor.error)
                    .disabled(!canDelete)
                    .accessibilityHint(canDelete ? "Permanently deletes this Lore account" : "Complete the confirmation above first")

                    Link(destination: ProfileSupportLinks.support) {
                        Label("Contact support instead", systemImage: "lifepreserver.fill")
                            .font(LoreType.body)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(LoreColor.ink)
                }
                .frame(maxWidth: 620, alignment: .leading)
                .padding(20)
                .frame(maxWidth: .infinity)
            }
            .background(LoreColor.bone100)
            .navigationTitle("Delete account")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(deleting)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(deleting)
                }
            }
        }
    }

    private var deleteButtonTitle: String {
        if deleting { return "Deleting account…" }
        if failureMessage != nil { return "Try deletion again" }
        return "Delete account permanently"
    }

    private var warningHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(LoreColor.error)
                .accessibilityHidden(true)
            Text("This cannot be undone")
                .font(LoreType.displayM)
                .foregroundStyle(LoreColor.ink)
            Text("Lore verifies your current secure session immediately before deletion. If it has expired, no data is removed and you will be asked to sign in again.")
                .font(LoreType.body)
                .foregroundStyle(LoreColor.ink600)
        }
    }

    private var deletionManifest: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Permanently removed")
                .loreLabelStyle()
                .foregroundStyle(LoreColor.ink600)
            ForEach([
                ("person.crop.circle.badge.xmark", "Profile and account access"),
                ("map.fill", "Saved visits and travel preferences"),
                ("book.closed.fill", "Private journal notes and photos"),
                ("medal.fill", "Badges, progress, and Insight record"),
            ], id: \.1) { item in
                Label(item.1, systemImage: item.0)
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)
            }
            Text("Accepted factual contributions may remain only in de-identified form, without your account ID or public attribution.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
        }
        .padding(16)
        .background(LoreColor.bone, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LoreColor.bone300))
    }

    private var subscriptionWarning: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Apple billing is separate", systemImage: "creditcard.fill")
                .font(LoreType.body.weight(.semibold))
                .foregroundStyle(LoreColor.ink)
            Text("Deleting your Lore account does not cancel an Apple subscription or create a refund.")
                .font(LoreType.caption)
                .foregroundStyle(LoreColor.ink600)
            Button("Manage Apple subscription") {
                openURL(ProfileSupportLinks.manageSubscriptions)
            }
            .font(LoreType.button)
            .buttonStyle(.bordered)
            .tint(LoreColor.brass700)

            if entitlements.isPlus {
                Toggle("I understand Apple billing continues until I cancel it", isOn: $understandsSubscription)
                    .font(LoreType.caption)
                    .tint(LoreColor.brass700)
            }
        }
        .padding(16)
        .background(LoreColor.brass.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
    }

    private var confirmationField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Type DELETE to confirm")
                .font(LoreType.body.weight(.semibold))
                .foregroundStyle(LoreColor.ink)
            TextField(AccountDeletionConfirmation.requiredPhrase, text: $confirmation)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($confirmationFocused)
                .padding(13)
                .background(LoreColor.bone, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            AccountDeletionConfirmation.isConfirmed(confirmation) ? LoreColor.error : LoreColor.bone300,
                            lineWidth: 1.5
                        )
                )
                .accessibilityHint("Enter the uppercase word DELETE")
        }
    }

    private func failureCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Account not deleted", systemImage: "xmark.octagon.fill")
                .font(LoreType.body.weight(.semibold))
            Text(message).font(LoreType.caption)
            Text("Nothing else will happen unless you choose Try again.")
                .font(LoreType.caption)
        }
        .foregroundStyle(LoreColor.error)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(LoreColor.error.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
    }

    @MainActor
    private func deleteAccount() async {
        guard canDelete else { return }
        deleting = true
        failureMessage = nil
        defer { deleting = false }

        guard await auth.validAccessToken(forceRefresh: true) != nil else {
            failureMessage = "Your secure session could not be verified. Sign in again, then retry deletion."
            return
        }

        if await auth.deleteAccount() {
            onDeleted()
        } else {
            failureMessage = auth.lastError ?? "Lore couldn't complete deletion. Check your connection and try again, or contact support."
        }
    }
}

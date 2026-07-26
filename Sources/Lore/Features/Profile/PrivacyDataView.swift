import SwiftUI

struct PrivacyDataView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.openURL) private var openURL

    @State private var requestOpened = false

    var body: some View {
        List {
            Section {
                privacyPromise(
                    "Core scanning stays on your device",
                    detail: "Live camera, heading, and nearby ranking are not saved as a continuous feed.",
                    icon: "iphone.gen3.radiowaves.left.and.right"
                )
                privacyPromise(
                    "No continuous location history",
                    detail: "Lore uses location while you explore. A visit is saved only when you choose to record it.",
                    icon: "location.slash.fill"
                )
                privacyPromise(
                    "No ads or cross-app tracking",
                    detail: "Lore does not sell personal information or use third-party advertising trackers.",
                    icon: "hand.raised.fill"
                )
            } header: {
                Text("The short version")
            }

            Section {
                dataRow("Account", detail: "Email, authentication ID, and optional profile details", icon: "person.crop.circle")
                dataRow("Travel journal", detail: "Visits, notes, and photos you intentionally save", icon: "book.closed.fill")
                dataRow("Personalization", detail: "Travel lens, interests, hidden categories, and badges", icon: "slider.horizontal.3")
                dataRow("Lore+", detail: "Apple manages payment details; Lore reads purchase access", icon: "crown.fill")
            } header: {
                Text("Data tied to an account")
            } footer: {
                Text("Provider security logs and backups may persist for a limited period under their retention policies. They are not used to recreate a deleted Lore account.")
            }

            Section {
                if auth.isSignedIn {
                    Button {
                        guard let url = ProfileSupportLinks.dataAccessRequestURL(
                            accountEmail: auth.session?.user.email
                        ) else { return }
                        openURL(url) { accepted in
                            requestOpened = accepted
                        }
                    } label: {
                        privacyActionRow("Request a copy of my data", icon: "square.and.arrow.up")
                    }
                    .buttonStyle(.plain)

                    if requestOpened {
                        Label("A prepared request was opened in your mail app.", systemImage: "checkmark.circle.fill")
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.ink600)
                    }
                } else {
                    Label("Sign in to request account data", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(LoreType.body)
                        .foregroundStyle(LoreColor.ink600)
                }

                Link(destination: ProfileSupportLinks.privacy) {
                    privacyActionRow("Read the full Privacy Policy", icon: "doc.text.magnifyingglass")
                }
            } header: {
                Text("Access and transparency")
            } footer: {
                Text("The request opens an email to Lore Support from your device. Send it from your account email when possible; support may verify ownership before providing data or corrections.")
            }

            Section {
                Text("Deleting your account removes your profile, preferences, visits, private journal, photos, badges, and Lore account access. Accepted factual contributions may remain only after account identifiers and attribution are removed.")
                    .font(LoreType.body)
                    .foregroundStyle(LoreColor.ink)

                Text("Deleting Lore does not cancel an Apple subscription. Apple billing must be managed separately.")
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            } header: {
                Text("Deletion")
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(LoreColor.bone100)
        .navigationTitle("Privacy & data")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func privacyPromise(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(LoreColor.brass700)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(LoreType.body.weight(.semibold))
                    .foregroundStyle(LoreColor.ink)
                Text(detail)
                    .font(LoreType.caption)
                    .foregroundStyle(LoreColor.ink600)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private func dataRow(_ title: String, detail: String, icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(LoreColor.ink600)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(LoreType.body).foregroundStyle(LoreColor.ink)
                Text(detail).font(LoreType.caption).foregroundStyle(LoreColor.ink600)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func privacyActionRow(_ title: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
                .font(LoreType.body)
                .foregroundStyle(LoreColor.ink)
            Spacer()
            Image(systemName: "arrow.up.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(LoreColor.ink600)
        }
    }
}

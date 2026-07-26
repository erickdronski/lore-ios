import SwiftUI

struct EditProfileView: View {
    @Environment(AuthService.self) private var auth
    @Environment(\.dismiss) private var dismiss

    let profile: UserProfile

    @State private var displayName: String
    @State private var handle: String
    @State private var bio: String
    @State private var isSaving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case displayName, handle, bio
    }

    init(profile: UserProfile) {
        self.profile = profile
        _displayName = State(initialValue: profile.displayName ?? "")
        _handle = State(initialValue: profile.handle ?? "")
        _bio = State(initialValue: profile.bio ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        ProfileAvatarView(profile: profile, size: 58)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Your traveler card")
                                .font(LoreType.body.weight(.semibold))
                                .foregroundStyle(LoreColor.ink)
                            Text("This identity appears on your private profile. Public sharing always asks first.")
                                .font(LoreType.caption)
                                .foregroundStyle(LoreColor.ink600)
                        }
                    }
                    .padding(.vertical, 4)
                }

                SwiftUI.Section {
                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                        .focused($focusedField, equals: .displayName)
                        .accessibilityHint("Up to \(UserProfile.Edit.displayNameLimit) characters")

                    TextField("Username", text: $handle)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                        .focused($focusedField, equals: .handle)
                        .accessibilityHint("3 to 24 lowercase letters, numbers, or underscores")

                    VStack(alignment: .trailing, spacing: 6) {
                        TextField("A short travel bio", text: $bio, axis: .vertical)
                            .lineLimit(3...7)
                            .focused($focusedField, equals: .bio)
                        Text("\(bio.count)/\(UserProfile.Edit.bioLimit)")
                            .font(LoreType.caption)
                            .foregroundStyle(bio.count > UserProfile.Edit.bioLimit ? LoreColor.error : LoreColor.ink600)
                            .accessibilityLabel("\(bio.count) of \(UserProfile.Edit.bioLimit) bio characters")
                    }
                } header: {
                    Text("Identity")
                } footer: {
                    Text("Leave a field blank to remove it. Usernames are unique and are saved in lowercase.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .font(LoreType.caption)
                            .foregroundStyle(LoreColor.error)
                            .accessibilityLabel("Profile error. \(errorMessage)")
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(LoreColor.bone100)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        focusedField = nil
                        Task { await save() }
                    }
                    .fontWeight(.semibold)
                    .disabled(isSaving)
                }
            }
        }
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        errorMessage = nil

        let edit: UserProfile.Edit
        do {
            edit = try UserProfile.Edit(displayName: displayName, handle: handle, bio: bio)
        } catch {
            errorMessage = error.localizedDescription
            return
        }

        guard let userID = auth.session?.user.id,
              let token = await auth.validAccessToken() else {
            errorMessage = ProfileAccountClient.ClientError.signedOut.localizedDescription
            return
        }

        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await ProfileAccountClient.updateProfile(
                edit,
                userID: userID,
                accessToken: token
            )
            await auth.refreshProfile()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct ProfileAvatarView: View {
    let profile: UserProfile
    var size: CGFloat = 54

    var body: some View {
        Group {
            if let url = profile.secureAvatarURL {
                AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty:
                        ProgressView().tint(LoreColor.brass700)
                    case .failure:
                        initials
                    @unknown default:
                        initials
                    }
                }
            } else {
                initials
            }
        }
        .frame(width: size, height: size)
        .background(LoreColor.ink)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(LoreColor.brass.opacity(0.7), lineWidth: 2))
        .accessibilityHidden(true)
    }

    private var initials: some View {
        Text(profile.initials)
            .font(LoreType.display(size: size * 0.34, weight: .semibold))
            .foregroundStyle(LoreColor.bone)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

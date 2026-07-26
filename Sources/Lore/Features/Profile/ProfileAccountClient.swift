import Foundation

enum ProfileAccountClient {
    enum ClientError: LocalizedError, Equatable {
        case invalidRequest
        case signedOut
        case usernameTaken
        case rejected
        case invalidResponse

        var errorDescription: String? {
            switch self {
            case .invalidRequest:
                return "Lore couldn't prepare that request. Please try again."
            case .signedOut:
                return "Your session expired. Sign in again, then retry."
            case .usernameTaken:
                return "That username is already in use. Try another one."
            case .rejected:
                return "Lore couldn't save your profile right now. Please try again."
            case .invalidResponse:
                return "Lore saved an unexpected response. Refresh and try again."
            }
        }
    }

    static func updateProfile(
        _ edit: UserProfile.Edit,
        userID: String,
        accessToken: String,
        session: URLSession = .shared
    ) async throws -> UserProfile {
        var components = URLComponents(
            url: Config.restURL.appending(path: "user_profile"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "id", value: "eq.\(userID)")]
        guard let url = components?.url else { throw ClientError.invalidRequest }

        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("return=representation", forHTTPHeaderField: "Prefer")
        request.httpBody = try JSONEncoder().encode(edit)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClientError.invalidResponse }
        switch http.statusCode {
        case 200..<300:
            guard let profile = try JSONDecoder().decode([UserProfile].self, from: data).first else {
                throw ClientError.invalidResponse
            }
            return profile
        case 401, 403:
            throw ClientError.signedOut
        case 409:
            throw ClientError.usernameTaken
        default:
            throw ClientError.rejected
        }
    }
}

enum ProfileSupportLinks {
    static let supportEmail = "esdronski@gmail.com"
    static let privacy = Config.webURL.appending(path: "privacy")
    static let terms = Config.webURL.appending(path: "terms")
    static let support = Config.webURL.appending(path: "support")
    static let appleEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let manageSubscriptions = URL(string: "https://apps.apple.com/account/subscriptions")!

    static var versionLine: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    static func emailURL(subject: String, body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = supportEmail
        components.queryItems = [
            URLQueryItem(name: "subject", value: subject),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }

    static func dataAccessRequestURL(accountEmail: String?) -> URL? {
        let accountLine = accountEmail.map { "Account email: \($0)" } ?? "Account email:"
        return emailURL(
            subject: "Lore data access request",
            body: """
            Hello Lore Support,

            I would like a copy of the personal data associated with my Lore account.

            \(accountLine)

            Please let me know if you need anything else to verify my request.
            """
        )
    }

    static func supportRequestURL(accountEmail: String?, version: String) -> URL? {
        let accountLine = accountEmail.map { "Account email: \($0)" } ?? "Account email:"
        return emailURL(
            subject: "Lore support request",
            body: """
            Hello Lore Support,

            What I need help with:


            \(accountLine)
            Lore version: \(version)
            Device / iOS version:
            City:
            """
        )
    }
}

enum AccountDeletionConfirmation {
    static let requiredPhrase = "DELETE"

    static func isConfirmed(_ entry: String) -> Bool {
        entry.trimmingCharacters(in: .whitespacesAndNewlines) == requiredPhrase
    }
}

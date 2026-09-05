import Foundation

/// Deletion may need several bounded storage-cleanup batches. Continue with the
/// same access token: the backend revokes refresh sessions once deletion starts,
/// while this still-valid token can finish its idempotent cleanup job.
enum AccountDeletionClient {
    static func delete(
        accessToken: String,
        session: URLSession = .shared,
        maximumAttempts: Int = 20,
        retryDelay: Duration = .seconds(1),
        maximumDuration: Duration = .seconds(30)
    ) async throws -> HTTPURLResponse {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: maximumDuration)
        var pendingResponse: HTTPURLResponse?
        for attempt in 0..<max(1, maximumAttempts) {
            try Task.checkCancellation()
            if clock.now >= deadline, let pendingResponse { return pendingResponse }
            var request = URLRequest(url: Config.functionsURL.appending(path: "delete-account"))
            let remaining = clock.now.duration(to: deadline).components
            request.timeoutInterval = max(0.1, min(30, Double(remaining.seconds) + Double(remaining.attoseconds) / 1e18))
            request.httpMethod = "POST"
            request.setValue(Config.supabaseAnonKey, forHTTPHeaderField: "apikey")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = Data("{}".utf8)
            let response: URLResponse
            do {
                (_, response) = try await session.data(for: request)
            } catch {
                try Task.checkCancellation()
                // Once the server fenced the account, interrupted cleanup is
                // still pending. Keep that truthful state available to the UI.
                if let pendingResponse { return pendingResponse }
                throw error
            }
            try Task.checkCancellation()
            guard let http = response as? HTTPURLResponse else {
                throw LoreAPI.APIError.invalidResponse
            }
            guard http.statusCode == 202, attempt + 1 < maximumAttempts else { return http }
            pendingResponse = http
            guard clock.now < deadline else { return http }
            try await clock.sleep(until: min(deadline, clock.now.advanced(by: retryDelay)))
        }
        throw LoreAPI.APIError.invalidResponse
    }
}

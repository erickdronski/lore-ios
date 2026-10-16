import XCTest
@testable import Lore

@MainActor
final class AuthProfileIsolationTests: XCTestCase {
    override func tearDown() {
        AuthProfileURLProtocol.handler = nil
        SessionStore.clear()
        super.tearDown()
    }

    func testDelayedProfileCannotRepopulateSignedOutState() async {
        let auth = makeService()
        await auth.signIn(email: "a@example.test", password: "fixture-password")
        XCTAssertEqual(auth.profile?.id, "a")

        let started = expectation(description: "old profile request started")
        var pending: AuthProfileURLProtocol?
        AuthProfileURLProtocol.handler = { request, connection in
            if request.url?.lastPathComponent == "user_profile" {
                pending = connection
                started.fulfill()
            } else {
                Self.respond(to: request, using: connection)
            }
        }
        let refresh = Task { await auth.refreshProfile() }
        await fulfillment(of: [started], timeout: 2)
        await auth.signOut()
        pending?.respond(status: 200, body: #"[{"id":"a","display_name":"Old account"}]"#)
        await refresh.value

        XCTAssertNil(auth.session)
        XCTAssertNil(auth.profile)
    }

    func testDelayedProfileCannotReplaceAnotherAccountsProfile() async {
        let auth = makeService()
        await auth.signIn(email: "a@example.test", password: "fixture-password")

        let started = expectation(description: "old profile request started")
        var pending: AuthProfileURLProtocol?
        AuthProfileURLProtocol.handler = { request, connection in
            if request.url?.lastPathComponent == "user_profile",
               request.value(forHTTPHeaderField: "Authorization") == "Bearer access-a" {
                pending = connection
                started.fulfill()
            } else {
                Self.respond(to: request, using: connection)
            }
        }
        let refresh = Task { await auth.refreshProfile() }
        await fulfillment(of: [started], timeout: 2)
        await auth.signOut()
        await auth.signIn(email: "b@example.test", password: "fixture-password")
        pending?.respond(status: 200, body: #"[{"id":"a","display_name":"Old account"}]"#)
        await refresh.value

        XCTAssertEqual(auth.session?.user.id, "b")
        XCTAssertEqual(auth.profile?.id, "b")
        await auth.signOut()
    }

    func testOldUnauthorizedResponseDoesNotRefreshNewAccount() async {
        let auth = makeService()
        await auth.signIn(email: "a@example.test", password: "fixture-password")

        let started = expectation(description: "old profile request started")
        var pending: AuthProfileURLProtocol?
        var tokenRefreshes = 0
        AuthProfileURLProtocol.handler = { request, connection in
            if request.url?.query?.contains("grant_type=refresh_token") == true {
                tokenRefreshes += 1
                connection.respond(status: 401, body: "{}")
            } else if request.url?.lastPathComponent == "user_profile",
                      request.value(forHTTPHeaderField: "Authorization") == "Bearer access-a" {
                pending = connection
                started.fulfill()
            } else {
                Self.respond(to: request, using: connection)
            }
        }
        let refresh = Task { await auth.refreshProfile() }
        await fulfillment(of: [started], timeout: 2)
        await auth.signOut()
        await auth.signIn(email: "b@example.test", password: "fixture-password")
        pending?.respond(status: 401, body: "{}")
        await refresh.value

        XCTAssertEqual(tokenRefreshes, 0)
        XCTAssertEqual(auth.session?.user.id, "b")
        XCTAssertEqual(auth.profile?.id, "b")
        await auth.signOut()
    }

    private func makeService() -> AuthService {
        AuthProfileURLProtocol.handler = Self.respond
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AuthProfileURLProtocol.self]
        return AuthService(urlSession: URLSession(configuration: configuration))
    }

    private nonisolated static func respond(to request: URLRequest, using connection: AuthProfileURLProtocol) {
        switch request.url?.lastPathComponent {
        case "token":
            // URLSession may expose a body stream rather than httpBody to its
            // URLProtocol. The fixtures use one token per email account.
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let count = stream.read(&bytes, maxLength: bytes.count)
                    if count <= 0 { break }
                    body.append(contentsOf: bytes.prefix(count))
                }
            }
            let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any]
            let user = (payload?["email"] as? String)?.hasPrefix("b@") == true ? "b" : "a"
            let expires = Int(Date().timeIntervalSince1970) + 3600
            connection.respond(status: 200, body: """
            {"access_token":"access-\(user)","refresh_token":"refresh-\(user)","expires_in":3600,"expires_at":\(expires),"token_type":"bearer","user":{"id":"\(user)","email":"\(user)@example.test"}}
            """)
        case "user_profile":
            let user = request.value(forHTTPHeaderField: "Authorization") == "Bearer access-b" ? "b" : "a"
            connection.respond(status: 200, body: "[{\"id\":\"\(user)\",\"display_name\":\"Fixture\"}]")
        case "logout":
            connection.respond(status: 204, body: "")
        default:
            XCTFail("Unexpected fixture request: \(request.url?.path ?? "missing URL")")
            connection.respond(status: 500, body: "{}")
        }
    }
}

private final class AuthProfileURLProtocol: URLProtocol {
    static var handler: ((URLRequest, AuthProfileURLProtocol) -> Void)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.handler?(request, self) }
    override func stopLoading() {}

    func respond(status: Int, body: String) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

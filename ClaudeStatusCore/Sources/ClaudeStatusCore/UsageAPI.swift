import Foundation

/// Wraps the GET https://api.anthropic.com/api/oauth/usage endpoint that ships with Claude Code.
public enum UsageAPI {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// Refresh proactively if the access token expires within this many seconds.
    private static let refreshLeadTime: TimeInterval = 60

    public static func fetchUsage(session: URLSession = .shared) async throws -> UsageResponse {
        let token = try await tokenForRequest(session: session)
        do {
            return try await performFetch(token: token, session: session)
        } catch APIError.http(401) {
            // Access token may have been revoked between proactive refresh and this request.
            // Force one refresh + retry. If that also 401s, the error propagates and the
            // user sees the auth failure surface in the UI.
            let fresh = try await OAuthRefresh.refresh(session: session)
            return try await performFetch(token: fresh, session: session)
        }
    }

    private static func tokenForRequest(session: URLSession) async throws -> String {
        let creds = try Keychain.readCredentials()
        // If we have an expiry timestamp and a refresh token, proactively refresh near expiry.
        if let exp = creds.expiresAt,
           creds.refreshToken != nil,
           exp.timeIntervalSinceNow < refreshLeadTime {
            return try await OAuthRefresh.refresh(session: session)
        }
        return creds.accessToken
    }

    private static func performFetch(token: String, session: URLSession) async throws -> UsageResponse {
        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(token)",   forHTTPHeaderField: "Authorization")
        req.setValue("macOS",             forHTTPHeaderField: "anthropic-client-platform")
        req.setValue("application/json",  forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(0) }
        if http.statusCode == 429 {
            let retryAfter = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw APIError.rateLimited(retryAfter: retryAfter)
        }
        guard (200..<300).contains(http.statusCode) else { throw APIError.http(http.statusCode) }
        return try JSONDecoder().decode(UsageResponse.self, from: data)
    }
}

import Foundation

/// Wraps the GET https://api.anthropic.com/api/oauth/usage endpoint that ships with Claude Code.
public enum UsageAPI {
    public static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    public static func fetchUsage(session: URLSession = .shared) async throws -> UsageResponse {
        let token = try Keychain.readClaudeCodeToken()

        var req = URLRequest(url: endpoint)
        req.setValue("Bearer \(token)",         forHTTPHeaderField: "Authorization")
        req.setValue("macOS",                    forHTTPHeaderField: "anthropic-client-platform")
        req.setValue("application/json",         forHTTPHeaderField: "Accept")
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

import Foundation

/// Fetches usage from the dev VM's `claude-usage` proxy (msdev :7610) instead of
/// hitting api.anthropic.com directly. The proxy reads the always-fresh Claude Code
/// OAuth token on the VM and serves the /api/oauth/usage response body verbatim,
/// so this Mac needs no keychain access, no token, and no refresh loop.
public enum UsageAPI {
    /// Override with `defaults write com.samcraft.ClaudeStatus usageProxyURL <url>`
    /// (e.g. a Tailscale address when off-LAN). Delete the key to restore the default.
    public static var endpoint: URL {
        if let s = UserDefaults.standard.string(forKey: "usageProxyURL"),
           let u = URL(string: s) {
            return u
        }
        return URL(string: "http://192.168.1.24:7610/usage")!
    }

    public static func fetchUsage(session: URLSession = .shared) async throws -> UsageResponse {
        var req = URLRequest(url: endpoint)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
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

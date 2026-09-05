import Foundation

/// Fetches usage from the dev VM's `claude-usage` proxy (msdev :7610) instead of
/// hitting api.anthropic.com directly. The proxy reads the always-fresh Claude Code
/// OAuth token on the VM and serves the /api/oauth/usage response body verbatim,
/// so this Mac needs no keychain access, no token, and no refresh loop.
public enum UsageAPI {
    /// Candidate proxy endpoints, tried in order; first success wins.
    /// LAN address first (home), then the VM's Tailscale address so the app
    /// keeps working away from home whenever the VPN is connected.
    /// `defaults write com.samcraft.ClaudeStatus usageProxyURL <url>` prepends
    /// a manual override; delete the key to restore the defaults.
    public static var endpoints: [URL] {
        var list: [URL] = []
        if let s = UserDefaults.standard.string(forKey: "usageProxyURL"),
           let u = URL(string: s) {
            list.append(u)
        }
        list.append(URL(string: "http://192.168.1.24:7610/usage")!)   // msdev, LAN
        list.append(URL(string: "http://100.114.108.14:7610/usage")!) // msdev, Tailscale
        return list
    }

    public static func fetchUsage(session: URLSession = .shared) async throws -> UsageResponse {
        var lastError: Error = APIError.http(0)
        for url in endpoints {
            do {
                return try await fetch(url, session: session)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private static func fetch(_ url: URL, session: URLSession) async throws -> UsageResponse {
        var req = URLRequest(url: url)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.cachePolicy = .reloadIgnoringLocalCacheData
        req.timeoutInterval = 6

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

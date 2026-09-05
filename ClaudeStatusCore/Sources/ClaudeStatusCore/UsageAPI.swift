import Foundation

/// A usage reading plus how old the proxy said its upstream data was.
public struct FetchedUsage: Sendable {
    public let response: UsageResponse
    /// Seconds since the proxy last got a 200 from api.anthropic.com
    /// (x-cache-age-s). Large values mean the VM's reading is stale even
    /// though our HTTP fetch succeeded. nil when the header was absent.
    public let upstreamAgeS: Int?
}

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

    public static func fetchUsage(session: URLSession = .shared) async throws -> FetchedUsage {
        var lastError: Error = APIError.http(0)
        for url in endpoints {
            do {
                return try await fetchOne(url, session: session)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Single-endpoint fetch, public so the widget can loop endpoints itself
    /// and record which one failed with what.
    public static func fetchOne(_ url: URL, session: URLSession = .shared) async throws -> FetchedUsage {
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
        let response = try JSONDecoder().decode(UsageResponse.self, from: data)
        let upstreamAge = http.value(forHTTPHeaderField: "x-cache-age-s").flatMap(Int.init)
        return FetchedUsage(response: response, upstreamAgeS: upstreamAge)
    }
}

import Foundation

/// Refreshes the Claude Code OAuth credentials using the stored refresh token.
///
/// The Claude Code CLI uses Anthropic's OAuth flow with a hardcoded public client_id.
/// Access tokens expire roughly hourly; refresh tokens rotate on each successful use.
public enum OAuthRefresh {
    /// Claude Code's public OAuth client_id (hardcoded in the official CLI).
    static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    static let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!

    /// Refreshes the keychain credentials and returns the new access token.
    /// Persists the rotated tokens (and updated expiry) back to the keychain.
    @discardableResult
    public static func refresh(session: URLSession = .shared) async throws -> String {
        let creds = try Keychain.readCredentials()
        // File-based credentials are owned by Claude Code, which rotates the tokens itself.
        // We must NOT refresh them here — using the refresh token would rotate it and
        // invalidate Claude Code's own login. Just return the current (re-read) access token;
        // Claude Code keeps the file fresh as you use it.
        if creds.source == .file {
            return creds.accessToken
        }
        guard let refreshToken = creds.refreshToken else {
            throw APIError.parseFailed
        }

        var req = URLRequest(url: tokenEndpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 15

        let body: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.http(0) }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(http.statusCode)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccess = json["access_token"] as? String,
              let expiresIn = json["expires_in"] as? Int
        else {
            throw APIError.parseFailed
        }
        // Refresh tokens rotate. If the server returns a new one, use it; otherwise reuse the old.
        let newRefresh = (json["refresh_token"] as? String) ?? refreshToken
        let newExpiresAt = Date().addingTimeInterval(TimeInterval(expiresIn))

        try Keychain.writeRefreshedTokens(
            previous: creds,
            accessToken: newAccess,
            refreshToken: newRefresh,
            expiresAt: newExpiresAt
        )
        return newAccess
    }
}

import Foundation
import Security

/// Reads the OAuth credentials that the Claude Code CLI stores. Two storage backends are
/// supported, in priority order:
///   1. The macOS login keychain, service 'Claude Code-credentials' (Claude Code's default
///      on machines where it uses the keychain).
///   2. The file ~/.claude/.credentials.json (Claude Code's file-based store). The app is
///      sandboxed, so reading this path requires the read-only temporary-exception entitlement
///      for `.claude/` declared in ClaudeStatus.entitlements.
public enum Keychain {
    private static let service = "Claude Code-credentials"

    /// Where a set of credentials came from. Determines whether refreshed tokens can be
    /// persisted back: keychain creds round-trip via SecItemUpdate; file creds are treated
    /// as read-only (Claude Code owns the file and rotates the tokens itself).
    public enum Source: Sendable {
        case keychain
        case file
    }

    public struct Credentials {
        public let accessToken: String
        public let refreshToken: String?
        /// nil if the blob doesn't include an expiresAt field.
        public let expiresAt: Date?
        public let source: Source
        /// The full original JSON, used to round-trip the keychain blob without dropping
        /// any fields the CLI may have written (subscriptionType, scopes, rateLimitTier, etc.).
        fileprivate let fullJSON: [String: Any]
    }

    /// The Claude Code credentials file, resolved against the *real* home directory.
    /// A sandboxed app's NSHomeDirectory() points at its container, so we read the passwd
    /// entry to get the user's true home (~/.claude lives outside the container).
    private static var credentialsFileURL: URL {
        let home: String
        if let pw = getpwuid(getuid()), let dir = pw.pointee.pw_dir {
            home = String(cString: dir)
        } else {
            home = NSHomeDirectory()
        }
        return URL(fileURLWithPath: home).appendingPathComponent(".claude/.credentials.json")
    }

    public static func readCredentials() throws -> Credentials {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else { throw APIError.parseFailed }
            return try parse(data: data, source: .keychain)
        case errSecItemNotFound:
            // No keychain item — fall back to Claude Code's file store.
            return try readCredentialsFromFile()
        case errSecAuthFailed, errSecUserCanceled:
            throw APIError.keychainDenied
        default:
            throw APIError.keychainOther(status)
        }
    }

    /// Reads and parses ~/.claude/.credentials.json. Throws keychainNotFound if absent so the
    /// UI still shows the "Run 'claude' once to sign in" hint when neither store has a token.
    private static func readCredentialsFromFile() throws -> Credentials {
        let url = credentialsFileURL
        guard let data = try? Data(contentsOf: url) else { throw APIError.keychainNotFound }
        return try parse(data: data, source: .file)
    }

    /// Shared parser for both the keychain blob and the file. Accepts either the
    /// `{ "claudeAiOauth": { ... } }` wrapper or a bare oauth object.
    private static func parse(data: Data, source: Source) throws -> Credentials {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw APIError.parseFailed
        }
        let oauth = (json["claudeAiOauth"] as? [String: Any]) ?? json
        guard let token = oauth["accessToken"] as? String else { throw APIError.parseFailed }

        let refresh = oauth["refreshToken"] as? String
        let expiresAt: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: ms / 1000.0)
        } else if let ms = oauth["expiresAt"] as? Int {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        } else {
            expiresAt = nil
        }

        return Credentials(accessToken: token, refreshToken: refresh,
                           expiresAt: expiresAt, source: source, fullJSON: json)
    }

    /// Writes refreshed tokens back to the keychain item, preserving all other fields the
    /// Claude Code CLI may have written. Only valid for keychain-sourced credentials — file
    /// credentials are read-only here (Claude Code rotates them in place), so this is a no-op
    /// for `.file` creds.
    public static func writeRefreshedTokens(
        previous: Credentials,
        accessToken: String,
        refreshToken: String,
        expiresAt: Date
    ) throws {
        guard previous.source == .keychain else { return }

        var oauth = (previous.fullJSON["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauth["accessToken"] = accessToken
        oauth["refreshToken"] = refreshToken
        oauth["expiresAt"] = Int(expiresAt.timeIntervalSince1970 * 1000)

        var json = previous.fullJSON
        json["claudeAiOauth"] = oauth

        let data = try JSONSerialization.data(withJSONObject: json, options: [])

        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        let attrs: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attrs as CFDictionary)
        if status != errSecSuccess {
            throw APIError.keychainOther(status)
        }
    }

    /// Backwards-compatible helper that just returns the access token without checking expiry.
    /// Prefer `readCredentials()` when the caller can refresh.
    public static func readClaudeCodeToken() throws -> String {
        return try readCredentials().accessToken
    }
}

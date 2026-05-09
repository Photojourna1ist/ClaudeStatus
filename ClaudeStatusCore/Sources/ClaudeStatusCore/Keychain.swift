import Foundation
import Security

/// Reads the OAuth access token that the Claude Code CLI stores in the user's login keychain
/// under the service name 'Claude Code-credentials'.
public enum Keychain {
    public static func readClaudeCodeToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String:       kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String:  true,
            kSecMatchLimit as String:  kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess: break
        case errSecItemNotFound: throw APIError.keychainNotFound
        case errSecAuthFailed, errSecUserCanceled: throw APIError.keychainDenied
        default: throw APIError.keychainOther(status)
        }
        guard let data = item as? Data,
              let json  = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String
        else { throw APIError.parseFailed }
        return token
    }
}

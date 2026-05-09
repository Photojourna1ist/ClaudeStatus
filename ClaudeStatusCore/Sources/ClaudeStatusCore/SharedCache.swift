import Foundation

/// Cached usage response with the time it was fetched.
public struct CachedUsage: Codable, Sendable {
    public let response: UsageResponse
    public let fetchedAt: Date

    public init(response: UsageResponse, fetchedAt: Date = Date()) {
        self.response = response
        self.fetchedAt = fetchedAt
    }
}

/// App Group-backed cache. Both the app and the widget extension read/write here.
public enum SharedCache {
    public static let appGroupID = "group.com.samcraft.ClaudeStatus"
    private static let key = "cachedUsage"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static func read() -> CachedUsage? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CachedUsage.self, from: data)
    }

    public static func write(_ response: UsageResponse) {
        let cached = CachedUsage(response: response, fetchedAt: Date())
        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: key)
        }
    }
}

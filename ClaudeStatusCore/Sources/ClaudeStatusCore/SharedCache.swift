import Foundation

/// Cached usage response with the time it was fetched.
public struct CachedUsage: Codable, Sendable {
    public let response: UsageResponse
    public let fetchedAt: Date
    /// Age in seconds the proxy reported for its upstream reading at fetch time
    /// (x-cache-age-s header). nil when the header was absent (old caches too —
    /// the optional keeps previously stored JSON decodable).
    public let upstreamAgeS: Int?

    public init(response: UsageResponse, fetchedAt: Date = Date(), upstreamAgeS: Int? = nil) {
        self.response = response
        self.fetchedAt = fetchedAt
        self.upstreamAgeS = upstreamAgeS
    }
}

/// App Group-backed cache. Both the app and the widget extension read/write here.
public enum SharedCache {
    public static let appGroupID = "group.com.samcraft.ClaudeStatus"
    private static let key = "cachedUsage"
    private static let authErrorKey = "authError"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }

    public static func read() -> CachedUsage? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(CachedUsage.self, from: data)
    }

    public static func write(_ response: UsageResponse, upstreamAgeS: Int? = nil) {
        let cached = CachedUsage(response: response, fetchedAt: Date(), upstreamAgeS: upstreamAgeS)
        if let data = try? JSONEncoder().encode(cached) {
            defaults.set(data, forKey: key)
        }
    }

    /// True when the OAuth refresh/usage call last returned an auth-related
    /// status (400 from refresh, 401 from /usage). The widget reads this to
    /// surface a "sign in" prompt without waiting for the main app to launch.
    public static var authError: Bool {
        get { defaults.bool(forKey: authErrorKey) }
        set { defaults.set(newValue, forKey: authErrorKey) }
    }
}

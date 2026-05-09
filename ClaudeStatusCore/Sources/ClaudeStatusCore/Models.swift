import Foundation

/// One usage window (5-hour, 7-day, etc.) returned by the OAuth usage endpoint.
public struct UsageBucket: Codable, Sendable, Equatable {
    public let utilization: Double
    public let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    public var resetDate: Date? {
        guard let s = resetsAt else { return nil }
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }
}

/// Monthly extra-credit allotment. Separate shape — no resets_at field.
public struct ExtraUsage: Codable, Sendable, Equatable {
    public let isEnabled: Bool
    public let monthlyLimit: Double?
    public let usedCredits: Double?
    public let utilization: Double?
    public let currency: String?

    enum CodingKeys: String, CodingKey {
        case isEnabled    = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits  = "used_credits"
        case utilization
        case currency
    }
}

/// Full response from GET https://api.anthropic.com/api/oauth/usage
public struct UsageResponse: Codable, Sendable, Equatable {
    public let fiveHour: UsageBucket?
    public let sevenDay: UsageBucket?
    public let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour    = "five_hour"
        case sevenDay    = "seven_day"
        case extraUsage  = "extra_usage"
    }
}

public enum APIError: Error, CustomStringConvertible, Sendable {
    case keychainNotFound
    case keychainDenied
    case keychainOther(OSStatus)
    case parseFailed
    case http(Int)
    case rateLimited(retryAfter: TimeInterval?)

    public var description: String {
        switch self {
        case .keychainNotFound:
            return "Run 'claude' once to sign in"
        case .keychainDenied:
            return "Keychain access denied"
        case .keychainOther(let s):
            return "Keychain error \(s)"
        case .parseFailed:
            return "Could not parse response"
        case .rateLimited(let retry):
            if let retry { return "Rate-limited, retry in \(Int(retry))s" }
            return "Rate-limited"
        case .http(let code):
            return "HTTP \(code)"
        }
    }
}

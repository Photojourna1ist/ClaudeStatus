import SwiftUI

// MARK: - StatusHeader

/// The "CLAUDE STATUS" header bar used in both floating window and widget extension.
@MainActor
public struct StatusHeader: View {
    public let title: String
    public let showStatusDot: Bool
    public let isHealthy: Bool

    public init(title: String = "CLAUDE STATUS", showStatusDot: Bool = false, isHealthy: Bool = true) {
        self.title = title
        self.showStatusDot = showStatusDot
        self.isHealthy = isHealthy
    }

    public var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "hourglass")
                .font(.system(size: 9))
                .foregroundStyle(Color(white: 0.55))
            Text(title)
                .font(.system(size: 9, weight: .bold))
                .tracking(1.5)
                .foregroundStyle(Color(white: 0.55))
            Spacer()
            if showStatusDot {
                Circle()
                    .fill(isHealthy ? Color.green : Color.red)
                    .frame(width: 5, height: 5)
            }
        }
    }
}

// MARK: - UsageColumn

/// A compact column showing label + percentage + (timer or detail string) + pill bar.
/// Used for 7d / Credits side-by-side.
@MainActor
public struct UsageColumn: View {
    public let label: String
    public let utilization: Double?
    public let timer: Date?
    public let detail: String?
    public let timerFontSize: CGFloat
    public let detailFontSize: CGFloat
    public let percentFontSize: CGFloat
    public let barHeight: CGFloat

    public init(label: String,
                utilization: Double?,
                timer: Date?,
                detail: String?,
                timerFontSize: CGFloat = 18,
                detailFontSize: CGFloat = 15,
                percentFontSize: CGFloat = 12,
                barHeight: CGFloat = 3) {
        self.label = label
        self.utilization = utilization
        self.timer = timer
        self.detail = detail
        self.timerFontSize = timerFontSize
        self.detailFontSize = detailFontSize
        self.percentFontSize = percentFontSize
        self.barHeight = barHeight
    }

    public static func creditsDetail(used: Double?, limit: Double?) -> String? {
        guard let used, let limit else { return nil }
        return String(format: "$%.2f / $%.2f", used / 100, limit / 100)
    }

    public var body: some View {
        let accent = ThemeStore.readAccentColor(forUtilization: utilization)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                Spacer()
                if let u = utilization {
                    Text("\(Int(u))%")
                        .font(.system(size: percentFontSize, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            if let timer {
                Text(timer, style: .timer)
                    .font(.system(size: timerFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else if let detail {
                Text(detail)
                    .font(.system(size: detailFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            if let u = utilization {
                PillBar(utilization: u, height: barHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - UsageHero

/// The big featured tracker: large timer + thicker pill bar. Used for 5h.
@MainActor
public struct UsageHero: View {
    public let label: String
    public let utilization: Double?
    public let resetDate: Date?
    public let timerFontSize: CGFloat
    public let percentFontSize: CGFloat
    public let barHeight: CGFloat

    public init(label: String = "Current Session",
                utilization: Double?,
                resetDate: Date?,
                timerFontSize: CGFloat = 22,
                percentFontSize: CGFloat = 12,
                barHeight: CGFloat = 5) {
        self.label = label
        self.utilization = utilization
        self.resetDate = resetDate
        self.timerFontSize = timerFontSize
        self.percentFontSize = percentFontSize
        self.barHeight = barHeight
    }

    public var body: some View {
        let accent = ThemeStore.readAccentColor(forUtilization: utilization)
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color(white: 0.55))
                Spacer()
                if let u = utilization {
                    Text("\(Int(u))%")
                        .font(.system(size: percentFontSize, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            if let d = resetDate {
                Text(d, style: .timer)
                    .font(.system(size: timerFontSize, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            } else {
                Text("—:—:—")
                    .font(.system(size: timerFontSize, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent.opacity(0.4))
            }
            if let u = utilization {
                PillBar(utilization: u, height: barHeight)
            }
        }
    }
}

// MARK: - UsageRow

/// A horizontal row of one tracker. Used in the Large widget layout (3 stacked rows).
@MainActor
public struct UsageRow: View {
    public let label: String
    public let utilization: Double?
    public let resetDate: Date?
    public let primary: Bool

    public init(label: String, utilization: Double?, resetDate: Date?, primary: Bool = false) {
        self.label = label
        self.utilization = utilization
        self.resetDate = resetDate
        self.primary = primary
    }

    public var body: some View {
        let accent = ThemeStore.readAccentColor(forUtilization: utilization)
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.55))
                Spacer()
                if let u = utilization {
                    Text("\(Int(u))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            if let d = resetDate {
                Text(d, style: .timer)
                    .font(.system(size: primary ? 24 : 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if let u = utilization {
                PillBar(utilization: u, height: primary ? 4 : 3)
            }
        }
    }
}

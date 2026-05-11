import SwiftUI

// MARK: - StatusHeader

/// The "CLAUDE STATUS" header bar used in both floating window and widget extension.
@MainActor
public struct StatusHeader: View {
    public let title: String
    public let showStatusDot: Bool
    public let isHealthy: Bool
    public let onIconTap: (() -> Void)?

    public init(title: String = "CLAUDE STATUS", showStatusDot: Bool = false, isHealthy: Bool = true, onIconTap: (() -> Void)? = nil) {
        self.title = title
        self.showStatusDot = showStatusDot
        self.isHealthy = isHealthy
        self.onIconTap = onIconTap
    }

    public var body: some View {
        HStack(spacing: 6) {
            Group {
                if let onIconTap {
                    Button(action: onIconTap) {
                        Image(systemName: "hourglass")
                            .font(.system(size: 9))
                            .foregroundStyle(Color(white: 0.55))
                    }
                    .buttonStyle(.plain)
                } else {
                    Image(systemName: "hourglass")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.55))
                }
            }
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

// MARK: - UsageDonut

/// A single ring/donut showing one trackers utilization. The arc fill respects the user
/// chosen bar color mode (solid / gradient / stepped) using AngularGradient for the
/// gradient and stepped variants so the color sweeps along the arc as it grows.
@MainActor
public struct UsageDonut<Center: View>: View {
    public let utilization: Double
    public let diameter: CGFloat
    public let strokeWidth: CGFloat
    public let center: () -> Center

    public init(utilization: Double,
                diameter: CGFloat,
                strokeWidth: CGFloat = 8,
                @ViewBuilder center: @escaping () -> Center) {
        self.utilization = utilization
        self.diameter = diameter
        self.strokeWidth = strokeWidth
        self.center = center
    }

    public var body: some View {
        let frac = min(max(utilization / 100.0, 0), 1)
        let mode = ThemeStore.readBarMode()
        ZStack {
            // Track
            Circle()
                .stroke(Color.white.opacity(0.10), lineWidth: strokeWidth)
            // Foreground arc, color mode dependent
            switch mode {
            case .solid:
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(ThemeStore.readBarSolidColor(),
                            style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            case .gradient:
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(AngularGradient(
                        gradient: Gradient(stops: Color.usageGradientStops),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            case .stepped:
                Circle()
                    .trim(from: 0, to: frac)
                    .stroke(AngularGradient(
                        gradient: Gradient(stops: Color.usageSteppedStops),
                        center: .center,
                        startAngle: .degrees(0),
                        endAngle: .degrees(360)
                    ),
                    style: StrokeStyle(lineWidth: strokeWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            // Center content
            center()
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - UsageDonutHero (Design A)

@MainActor
public struct UsageDonutHero: View {
    public let fiveHourUtil: Double?
    public let fiveHourReset: Date?
    public let sevenDayUtil: Double?
    public let extraUtil: Double?
    public let extraUsed: Double?
    public let extraLimit: Double?

    public init(fiveHourUtil: Double?, fiveHourReset: Date?,
                sevenDayUtil: Double?,
                extraUtil: Double?, extraUsed: Double?, extraLimit: Double?) {
        self.fiveHourUtil = fiveHourUtil
        self.fiveHourReset = fiveHourReset
        self.sevenDayUtil = sevenDayUtil
        self.extraUtil = extraUtil
        self.extraUsed = extraUsed
        self.extraLimit = extraLimit
    }

    public var body: some View {
        let heroAccent = ThemeStore.shared.accentColor(forUtilization: fiveHourUtil)
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                StatusHeader()
                Spacer(minLength: 0)
                if let u = fiveHourUtil {
                    Text("\(Int(u))%")
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .foregroundStyle(heroAccent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                } else {
                    Text("DASH%".replacingOccurrences(of: "DASH", with: "D-"))
                        .font(.system(size: 48, weight: .semibold, design: .rounded))
                        .foregroundStyle(heroAccent.opacity(0.4))
                }
                Text("Current Session")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
                Spacer(minLength: 0)
                HStack(spacing: 10) {
                    HeroLegendItem(label: "Weekly", utilization: sevenDayUtil)
                    HeroLegendItem(label: "Extra", utilization: extraUtil)
                }
            }
            UsageDonut(utilization: fiveHourUtil ?? 0, diameter: 108, strokeWidth: 11) {
                VStack(spacing: 0) {
                    Text("RESETS IN")
                        .font(.system(size: 9, weight: .medium))
                        .tracking(1.2)
                        .foregroundStyle(Color(white: 0.45))
                    if let d = fiveHourReset {
                        Text(d, style: .timer)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(heroAccent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("—:—")
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(heroAccent.opacity(0.4))
                    }
                }
            }
            .frame(width: 108, height: 108)
        }
    }
}

@MainActor
struct HeroLegendItem: View {
    let label: String
    let utilization: Double?
    var body: some View {
        let color = ThemeStore.shared.accentColor(forUtilization: utilization)
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.6))
            if let u = utilization {
                Text("\(Int(u))%")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - UsageDonutRings (Design B)

@MainActor
public struct UsageDonutRings: View {
    public let fiveHourUtil: Double?
    public let sevenDayUtil: Double?
    public let extraUtil: Double?
    public let extraUsed: Double?
    public let extraLimit: Double?

    public init(fiveHourUtil: Double?, sevenDayUtil: Double?,
                extraUtil: Double?, extraUsed: Double?, extraLimit: Double?) {
        self.fiveHourUtil = fiveHourUtil
        self.sevenDayUtil = sevenDayUtil
        self.extraUtil = extraUtil
        self.extraUsed = extraUsed
        self.extraLimit = extraLimit
    }

    public var body: some View {
        let heroAccent = ThemeStore.shared.accentColor(forUtilization: fiveHourUtil)
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 8) {
                StatusHeader()
                Spacer(minLength: 0)
                RingLegendItem(label: "Current Session", utilization: fiveHourUtil, detail: nil)
                RingLegendItem(label: "Weekly Limit", utilization: sevenDayUtil, detail: nil)
                RingLegendItem(
                    label: "Extra Usage",
                    utilization: extraUtil,
                    detail: (extraUsed != nil && extraLimit != nil)
                        ? String(format: "$%.2f", (extraUsed ?? 0) / 100)
                        : nil
                )
                Spacer(minLength: 0)
            }
            ZStack {
                UsageDonut(utilization: fiveHourUtil ?? 0, diameter: 132, strokeWidth: 8) { EmptyView() }
                UsageDonut(utilization: sevenDayUtil ?? 0, diameter: 100, strokeWidth: 8) { EmptyView() }
                UsageDonut(utilization: extraUtil ?? 0, diameter: 68, strokeWidth: 8) { EmptyView() }
                if let u = fiveHourUtil {
                    Text("\(Int(u))%")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundStyle(heroAccent)
                }
            }
            .frame(width: 132, height: 132)
        }
    }
}

@MainActor
struct RingLegendItem: View {
    let label: String
    let utilization: Double?
    let detail: String?
    var body: some View {
        let color = ThemeStore.shared.accentColor(forUtilization: utilization)
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.6))
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            } else if let u = utilization {
                Text("\(Int(u))%")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(color)
            }
        }
    }
}

// MARK: - UsageDonutTrio (Design C)

@MainActor
public struct UsageDonutTrio: View {
    public let fiveHourUtil: Double?
    public let fiveHourReset: Date?
    public let sevenDayUtil: Double?
    public let sevenDayReset: Date?
    public let extraUtil: Double?
    public let extraUsed: Double?
    public let extraLimit: Double?

    public init(fiveHourUtil: Double?, fiveHourReset: Date?,
                sevenDayUtil: Double?, sevenDayReset: Date?,
                extraUtil: Double?, extraUsed: Double?, extraLimit: Double?) {
        self.fiveHourUtil = fiveHourUtil
        self.fiveHourReset = fiveHourReset
        self.sevenDayUtil = sevenDayUtil
        self.sevenDayReset = sevenDayReset
        self.extraUtil = extraUtil
        self.extraUsed = extraUsed
        self.extraLimit = extraLimit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            StatusHeader()
            HStack(spacing: 6) {
                TrioTile(label: "Session",
                         utilization: fiveHourUtil,
                         detailText: nil,
                         detailDate: fiveHourReset)
                TrioTile(label: "Weekly",
                         utilization: sevenDayUtil,
                         detailText: nil,
                         detailDate: sevenDayReset)
                TrioTile(label: "Extra",
                         utilization: extraUtil,
                         detailText: (extraUsed != nil && extraLimit != nil)
                             ? String(format: "$%.2f", (extraUsed ?? 0) / 100)
                             : nil,
                         detailDate: nil)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

@MainActor
struct TrioTile: View {
    let label: String
    let utilization: Double?
    let detailText: String?
    let detailDate: Date?

    var body: some View {
        let color = ThemeStore.shared.accentColor(forUtilization: utilization)
        VStack(spacing: 2) {
            UsageDonut(utilization: utilization ?? 0, diameter: 64, strokeWidth: 7) {
                if let u = utilization {
                    Text("\(Int(u))%")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(color)
                }
            }
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(Color(white: 0.55))
            if let detailText {
                Text(detailText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            } else if let detailDate {
                Text(detailDate, style: .timer)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - UsageDonutRingsWithTimer (timer in center for iOS countdown)

@MainActor
public struct UsageDonutRingsWithTimer<Center: View>: View {
    public let fiveHourUtil: Double?
    public let sevenDayUtil: Double?
    public let extraUtil: Double?
    public let ringSize: CGFloat
    public let strokeWidth: CGFloat
    public let center: () -> Center

    public init(fiveHourUtil: Double?,
                sevenDayUtil: Double?,
                extraUtil: Double?,
                ringSize: CGFloat,
                strokeWidth: CGFloat = 8,
                @ViewBuilder center: @escaping () -> Center) {
        self.fiveHourUtil = fiveHourUtil
        self.sevenDayUtil = sevenDayUtil
        self.extraUtil = extraUtil
        self.ringSize = ringSize
        self.strokeWidth = strokeWidth
        self.center = center
    }

    public var body: some View {
        ZStack {
            UsageDonut(utilization: fiveHourUtil ?? 0, diameter: ringSize, strokeWidth: strokeWidth) { EmptyView() }
            UsageDonut(utilization: sevenDayUtil ?? 0, diameter: ringSize - (strokeWidth * 4), strokeWidth: strokeWidth) { EmptyView() }
            UsageDonut(utilization: extraUtil ?? 0, diameter: ringSize - (strokeWidth * 8), strokeWidth: strokeWidth) { EmptyView() }
            center()
        }
        .frame(width: ringSize, height: ringSize)
    }
}

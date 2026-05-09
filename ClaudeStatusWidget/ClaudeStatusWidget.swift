import WidgetKit
import SwiftUI
import ClaudeStatusCore

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let usage: UsageResponse?
    let lastFetch: Date?
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), usage: nil, lastFetch: nil)
    }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let cached = SharedCache.read()
        completion(UsageEntry(date: Date(), usage: cached?.response, lastFetch: cached?.fetchedAt))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let cached = SharedCache.read()
        let now = Date()
        let entry = UsageEntry(date: now, usage: cached?.response, lastFetch: cached?.fetchedAt)
        let next = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget

struct ClaudeStatusWidget: Widget {
    let kind: String = "ClaudeStatusWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            ClaudeStatusWidgetEntryView(entry: entry)
                .containerBackground(ThemeStore.readBackground(), for: .widget)
        }
        .configurationDisplayName("Claude Status")
        .description("Time until your Claude usage limits reset.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Container

struct ClaudeStatusWidgetEntryView: View {
    var entry: UsageEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        switch family {
        case .systemSmall:  WidgetSmallView(entry: entry)
        case .systemMedium: WidgetMediumView(entry: entry)
        case .systemLarge:  WidgetLargeView(entry: entry)
        default:            WidgetSmallView(entry: entry)
        }
    }
}

private let labelGray = Color(white: 0.55)

// MARK: - Small

struct WidgetSmallView: View {
    var entry: UsageEntry
    var body: some View {
        let accent = ThemeStore.readAccentColor(forUtilization: entry.usage?.fiveHour?.utilization)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                    .font(.system(size: 10))
                    .foregroundStyle(accent.opacity(0.7))
                Text("Current Session")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(labelGray)
                Spacer()
                if let u = entry.usage?.fiveHour {
                    Text("\(Int(u.utilization))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accent)
                }
            }
            if let d = entry.usage?.fiveHour?.resetDate {
                Text(d, style: .timer)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("X:X:X".replacingOccurrences(of: "X", with: "—"))
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(accent.opacity(0.4))
            }
            if let u = entry.usage?.fiveHour {
                PillBar(utilization: u.utilization, height: 3)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Medium  (top row: 7d + Credits, bottom: 5h hero)

struct WidgetMediumView: View {
    var entry: UsageEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusHeader()

            HStack(alignment: .top, spacing: 10) {
                UsageColumn(
                    label: "Weekly Limit",
                    utilization: entry.usage?.sevenDay?.utilization,
                    timer: entry.usage?.sevenDay?.resetDate,
                    detail: nil,
                    timerFontSize: 16,
                    detailFontSize: 14,
                    percentFontSize: 11
                )
                if let extra = entry.usage?.extraUsage, extra.isEnabled, let util = extra.utilization {
                    Divider().frame(height: 44)
                    UsageColumn(
                        label: "Extra Usage",
                        utilization: util,
                        timer: nil,
                        detail: UsageColumn.creditsDetail(used: extra.usedCredits, limit: extra.monthlyLimit),
                        timerFontSize: 16,
                        detailFontSize: 14,
                        percentFontSize: 11
                    )
                }
            }

            UsageHero(
                utilization: entry.usage?.fiveHour?.utilization,
                resetDate: entry.usage?.fiveHour?.resetDate,
                timerFontSize: 22
            )

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Large  (3 stacked rows with bigger primary timers)

struct WidgetLargeView: View {
    var entry: UsageEntry
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatusHeader()
            UsageRow(label: "Current Session",
                     utilization: entry.usage?.fiveHour?.utilization,
                     resetDate: entry.usage?.fiveHour?.resetDate,
                     primary: true)
            UsageRow(label: "Weekly Limit",
                     utilization: entry.usage?.sevenDay?.utilization,
                     resetDate: entry.usage?.sevenDay?.resetDate,
                     primary: true)
            if let extra = entry.usage?.extraUsage, extra.isEnabled, let util = extra.utilization {
                let creditsAccent = ThemeStore.readAccentColor(forUtilization: util)
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Extra Usage")
                            .font(.system(size: 10))
                            .foregroundStyle(Color(white: 0.55))
                        Spacer()
                        Text("\(Int(util))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(creditsAccent)
                    }
                    if let used = extra.usedCredits, let limit = extra.monthlyLimit {
                        Text(String(format: "$%.2f / $%.2f", used / 100, limit / 100))
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(creditsAccent)
                    }
                    PillBar(utilization: util, height: 4)
                }
            }
            Spacer(minLength: 0)
            if let last = entry.lastFetch {
                Text("Updated \(last, style: .relative) ago")
                    .font(.system(size: 8))
                    .foregroundStyle(Color(white: 0.4))
            }
        }
    }
}


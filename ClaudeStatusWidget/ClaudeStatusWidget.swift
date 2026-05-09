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
        // Ask the system to refresh in 15 min. It may grant more or less.
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
                .containerBackground(.black, for: .widget)
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

// MARK: - Small

struct WidgetSmallView: View {
    var entry: UsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange.opacity(0.7))
                Text("5h")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let u = entry.usage?.fiveHour {
                    Text("\(Int(u.utilization))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            if let d = entry.usage?.fiveHour?.resetDate {
                Text(d, style: .timer)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("--:--")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.orange.opacity(0.4))
            }
            if let u = entry.usage?.fiveHour {
                PillBar(utilization: u.utilization, height: 3)
            }
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Medium

struct WidgetMediumView: View {
    var entry: UsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("CLAUDE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("5h window")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let f = entry.usage?.fiveHour {
                        Text("\(Int(f.utilization))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                }
                if let d = entry.usage?.fiveHour?.resetDate {
                    Text(d, style: .timer)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                if let f = entry.usage?.fiveHour {
                    PillBar(utilization: f.utilization, height: 4)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("7d total")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let s = entry.usage?.sevenDay {
                        Text("\(Int(s.utilization))%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundStyle(.orange)
                    }
                }
                if let s = entry.usage?.sevenDay {
                    PillBar(utilization: s.utilization, height: 3)
                }
            }

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Large

struct WidgetLargeView: View {
    var entry: UsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                Text("CLAUDE STATUS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundStyle(.secondary)
                Spacer()
            }

            WidgetUsageRow(
                label: "5-hour window",
                utilization: entry.usage?.fiveHour?.utilization,
                resetDate: entry.usage?.fiveHour?.resetDate,
                primary: true
            )

            WidgetUsageRow(
                label: "7-day (all models)",
                utilization: entry.usage?.sevenDay?.utilization,
                resetDate: entry.usage?.sevenDay?.resetDate,
                primary: false
            )

            if let extra = entry.usage?.extraUsage, extra.isEnabled, let util = extra.utilization {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Extra credits")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(util))%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    PillBar(utilization: util, height: 4)
                }
            }

            Spacer(minLength: 0)

            if let last = entry.lastFetch {
                Text("Updated \(last, style: .relative) ago")
                    .font(.system(size: 8))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

struct WidgetUsageRow: View {
    let label: String
    let utilization: Double?
    let resetDate: Date?
    let primary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                Spacer()
                if let u = utilization {
                    Text("\(Int(u))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                }
            }
            if let d = resetDate {
                Text(d, style: .timer)
                    .font(.system(size: primary ? 18 : 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
            if let u = utilization {
                PillBar(utilization: u, height: primary ? 4 : 3)
            }
        }
    }
}

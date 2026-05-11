import WidgetKit
import SwiftUI
import ClaudeStatusCore

// MARK: - Timeline

struct iOSWidgetEntry: TimelineEntry {
    let date: Date
    let resetDate: Date?
    let utilization: Double?
}

struct iOSWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> iOSWidgetEntry {
        iOSWidgetEntry(date: Date(),
                       resetDate: Date().addingTimeInterval(3 * 3600 + 47 * 60),
                       utilization: 64)
    }
    func getSnapshot(in context: Context, completion: @escaping (iOSWidgetEntry) -> Void) {
        let snap = ResetTimeSync.read()
        completion(iOSWidgetEntry(date: Date(), resetDate: snap.resetDate, utilization: snap.utilization))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<iOSWidgetEntry>) -> Void) {
        let snap = ResetTimeSync.read()
        let now = Date()
        let entry = iOSWidgetEntry(date: now, resetDate: snap.resetDate, utilization: snap.utilization)
        // Ask the system to refresh every 15 minutes so we pick up any new resetDate from iCloud.
        let next = now.addingTimeInterval(15 * 60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Widget configuration

struct ClaudeStatusiOSWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeStatusiOSWidget", provider: iOSWidgetProvider()) { entry in
            ClaudeStatusiOSWidgetView(entry: entry)
                .containerBackground(ThemeStore.readBackgroundStyle(), for: .widget)
        }
        .configurationDisplayName("Claude Status")
        .description("Countdown to your next 5-hour session reset.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct ClaudeStatusiOSWidgetView: View {
    let entry: iOSWidgetEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        switch family {
        case .systemSmall:  SmalliOSWidget(entry: entry)
        case .systemMedium: MediumiOSWidget(entry: entry)
        default:            SmalliOSWidget(entry: entry)
        }
    }
}

// MARK: - Small widget

struct SmalliOSWidget: View {
    let entry: iOSWidgetEntry

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Image(systemName: "hourglass")
                    .font(.system(size: 9))
                    .foregroundStyle(Color(white: 0.55))
                Text("SESSION")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Color(white: 0.55))
                Spacer()
            }
            ZStack {
                UsageDonut(utilization: 100, diameter: 92, strokeWidth: 7) { EmptyView() }
                    .opacity(0.12)
                UsageDonut(utilization: entry.utilization ?? 0, diameter: 92, strokeWidth: 7) { EmptyView() }
                centerContent
            }
            .frame(maxHeight: .infinity)
        }
    }

    @ViewBuilder var centerContent: some View {
        let accent = ThemeStore.readAccentColor(forUtilization: entry.utilization)
        VStack(spacing: 0) {
            if let d = entry.resetDate {
                Text(d, style: .timer)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
            }
            if let u = entry.utilization {
                Text("\(Int(u))%")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(accent.opacity(0.7))
            }
        }
    }
}

// MARK: - Medium widget

struct MediumiOSWidget: View {
    let entry: iOSWidgetEntry

    var body: some View {
        let accent = ThemeStore.readAccentColor(forUtilization: entry.utilization)
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 9))
                        .foregroundStyle(Color(white: 0.55))
                    Text("CLAUDE STATUS")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.5)
                        .foregroundStyle(Color(white: 0.55))
                }
                Spacer(minLength: 0)
                Text("Current Session")
                    .font(.system(size: 11))
                    .foregroundStyle(Color(white: 0.55))
                if let d = entry.resetDate {
                    Text(d, style: .timer)
                        .font(.system(size: 26, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(accent)
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                if let u = entry.utilization {
                    Text("\(Int(u))% used")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(accent.opacity(0.7))
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            ZStack {
                UsageDonut(utilization: entry.utilization ?? 0, diameter: 108, strokeWidth: 9) { EmptyView() }
            }
        }
    }
}

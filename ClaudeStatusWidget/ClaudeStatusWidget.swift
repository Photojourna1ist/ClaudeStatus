import WidgetKit
import SwiftUI
import ClaudeStatusCore

// MARK: - Timeline

struct UsageEntry: TimelineEntry {
    let date: Date
    let usage: UsageResponse?
    let lastFetch: Date?
    let upstreamAgeS: Int?
    let authError: Bool

    /// Effective age of the data in minutes when it's old enough to warn about
    /// (> 15 min), else nil. Counts both how long ago WE fetched and how stale
    /// the proxy said its upstream reading was — so a dead app, a dead VM, or a
    /// dead token upstream all surface instead of silently showing old numbers.
    var staleMinutes: Int? {
        guard let lastFetch else { return nil }
        let effective = date.timeIntervalSince(lastFetch) + TimeInterval(upstreamAgeS ?? 0)
        return effective > 15 * 60 ? Int(effective / 60) : nil
    }
}

struct UsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), usage: nil, lastFetch: nil, upstreamAgeS: nil, authError: false)
    }
    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        let cached = SharedCache.read()
        completion(UsageEntry(date: Date(), usage: cached?.response, lastFetch: cached?.fetchedAt,
                              upstreamAgeS: cached?.upstreamAgeS, authError: SharedCache.authError))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let cached = SharedCache.read()
        let age = cached.map { Date().timeIntervalSince($0.fetchedAt) } ?? .infinity
        // Breadcrumbs (remote-diagnosable): when getTimeline last ran + which path.
        SharedCache.defaults.set(Date(), forKey: "widgetTimelineAt")
        if age <= 120 {
            // The app is alive and keeping the cache fresh — just render it.
            SharedCache.defaults.set("cache-fresh", forKey: "widgetPath")
            complete(with: cached, completion: completion)
        } else {
            // Cache is stale (app crashed, quit, or never launched). The proxy
            // needs no auth, so the widget can fetch for itself. Loop endpoints
            // here (not via fetchUsage) so the breadcrumb records EVERY
            // endpoint's outcome, not just the last error.
            Task {
                var lines: [String] = []
                var ok = false
                for url in UsageAPI.endpoints {
                    do {
                        let fetched = try await UsageAPI.fetchOne(url)
                        SharedCache.write(fetched.response, upstreamAgeS: fetched.upstreamAgeS)
                        lines.append("\(url.host ?? "?") OK")
                        ok = true
                        break
                    } catch {
                        let e = error as NSError
                        lines.append("\(url.host ?? "?") \(e.domain)#\(e.code)")
                    }
                }
                SharedCache.defaults.set((ok ? "self-fetch-ok | " : "self-fetch-fail | ")
                                         + lines.joined(separator: " ; "), forKey: "widgetPath")
                complete(with: SharedCache.read(), completion: completion)
            }
        }
    }
    private func complete(with cached: CachedUsage?, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        let now = Date()
        let entry = UsageEntry(date: now, usage: cached?.response, lastFetch: cached?.fetchedAt,
                               upstreamAgeS: cached?.upstreamAgeS, authError: SharedCache.authError)
        // 5 min keeps the widget self-sufficient when the app is gone; while the
        // app runs it reloads timelines on every fetch anyway.
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(5 * 60))))
    }
}

/// URL the whole widget opens when auth is dead — main app handles it.
let reauthURL = URL(string: "claudestatus://reauth")!

struct WidgetAuthExpiredView: View {
    @Environment(\.widgetFamily) var family
    var body: some View {
        let small = family == .systemSmall
        VStack(alignment: .leading, spacing: small ? 4 : 6) {
            HStack(spacing: 4) {
                Image(systemName: "key.slash.fill")
                    .font(.system(size: small ? 11 : 12, weight: .semibold))
                Text("Sign in")
                    .font(.system(size: small ? 10 : 11, weight: .bold))
                    .tracking(0.5)
                Spacer()
            }
            .foregroundStyle(Color(red: 0.97, green: 0.55, blue: 0.55))
            Text(small ? "Auth expired" : "ClaudeStatus can't refresh")
                .font(.system(size: small ? 13 : 16, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            Text("Tap to fix")
                .font(.system(size: small ? 9 : 10, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Widget

struct ClaudeStatusWidget: Widget {
    let kind: String = "ClaudeStatusWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            ClaudeStatusWidgetEntryView(entry: entry)
                .containerBackground(ThemeStore.readBackgroundStyle(), for: .widget)
                .widgetURL(entry.authError ? reauthURL : nil)
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
        ZStack(alignment: .bottomTrailing) {
            Group {
                if entry.authError {
                    WidgetAuthExpiredView()
                } else {
                    switch family {
                    case .systemSmall:  WidgetSmallView(entry: entry)
                    case .systemMedium: WidgetMediumView(entry: entry)
                    case .systemLarge:  WidgetLargeView(entry: entry)
                    default:            WidgetSmallView(entry: entry)
                    }
                }
            }
            if let mins = entry.staleMinutes {
                HStack(spacing: 2) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 7, weight: .bold))
                    Text(mins < 120 ? "\(mins)m old" : "\(mins / 60)h old")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.orange)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(.orange.opacity(0.18)))
            }
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


// MARK: - Hero Donut Widget

struct ClaudeStatusHeroDonutWidget: Widget {
    let kind: String = "ClaudeStatusHeroDonutWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            Group {
                if entry.authError {
                    WidgetAuthExpiredView()
                } else {
                    UsageDonutHero(
                        fiveHourUtil: entry.usage?.fiveHour?.utilization,
                        fiveHourReset: entry.usage?.fiveHour?.resetDate,
                        sevenDayUtil: entry.usage?.sevenDay?.utilization,
                        extraUtil: entry.usage?.extraUsage?.utilization,
                        extraUsed: entry.usage?.extraUsage?.usedCredits,
                        extraLimit: entry.usage?.extraUsage?.monthlyLimit
                    )
                }
            }
            .containerBackground(ThemeStore.readBackgroundStyle(), for: .widget)
            .widgetURL(entry.authError ? reauthURL : nil)
        }
        .configurationDisplayName("Claude Status: Hero Donut")
        .description("Big current-session percentage with a donut chart and color-dot legend.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Rings Widget

struct ClaudeStatusRingsWidget: Widget {
    let kind: String = "ClaudeStatusRingsWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            Group {
                if entry.authError {
                    WidgetAuthExpiredView()
                } else {
                    UsageDonutRings(
                        fiveHourUtil: entry.usage?.fiveHour?.utilization,
                        sevenDayUtil: entry.usage?.sevenDay?.utilization,
                        extraUtil: entry.usage?.extraUsage?.utilization,
                        extraUsed: entry.usage?.extraUsage?.usedCredits,
                        extraLimit: entry.usage?.extraUsage?.monthlyLimit
                    )
                }
            }
            .containerBackground(ThemeStore.readBackgroundStyle(), for: .widget)
            .widgetURL(entry.authError ? reauthURL : nil)
        }
        .configurationDisplayName("Claude Status: Concentric Rings")
        .description("Three nested ring arcs, one per tracker, with the most urgent percentage in the center.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - Trio Widget

struct ClaudeStatusTrioWidget: Widget {
    let kind: String = "ClaudeStatusTrioWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: UsageProvider()) { entry in
            Group {
                if entry.authError {
                    WidgetAuthExpiredView()
                } else {
                    UsageDonutTrio(
                        fiveHourUtil: entry.usage?.fiveHour?.utilization,
                        fiveHourReset: entry.usage?.fiveHour?.resetDate,
                        sevenDayUtil: entry.usage?.sevenDay?.utilization,
                        sevenDayReset: entry.usage?.sevenDay?.resetDate,
                        extraUtil: entry.usage?.extraUsage?.utilization,
                        extraUsed: entry.usage?.extraUsage?.usedCredits,
                        extraLimit: entry.usage?.extraUsage?.monthlyLimit
                    )
                }
            }
            .containerBackground(ThemeStore.readBackgroundStyle(), for: .widget)
            .widgetURL(entry.authError ? reauthURL : nil)
        }
        .configurationDisplayName("Claude Status: Trio Donuts")
        .description("Three small donuts side-by-side, one per tracker.")
        .supportedFamilies([.systemMedium])
    }
}

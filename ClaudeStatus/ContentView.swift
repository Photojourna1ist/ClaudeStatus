import SwiftUI
import AppKit
import Combine
import Sparkle
import ClaudeStatusCore


// MARK: - Updater bridge

@MainActor
enum UpdaterBridge {
    static func checkForUpdates() {
        guard let delegate = NSApp.delegate as? AppDelegate else { return }
        delegate.updaterController.checkForUpdates(nil)
    }
}

// MARK: - Size

enum WidgetSize: String, CaseIterable, Codable {
    case small, medium, large

    var dimensions: CGSize {
        switch self {
        case .small:  return CGSize(width: 160, height: 80)
        case .medium: return CGSize(width: 220, height: 150)
        case .large:  return CGSize(width: 280, height: 240)
        }
    }
}

// MARK: - Store

@MainActor
final class UsageStore: ObservableObject {
    @Published var fiveHour: UsageBucket?
    @Published var sevenDay: UsageBucket?
    @Published var extraUsage: ExtraUsage?
    @Published var errorMessage: String?
    @Published var lastFetch: Date?
    @Published var isLoading: Bool = false

    private var refreshTask: Task<Void, Never>?
    private var currentInterval: TimeInterval = 60   // seconds between fetches
    private let baseInterval: TimeInterval = 60
    private let maxInterval: TimeInterval = 900      // 15 min cap

    func start() {
        // Hydrate immediately from cache so we have something on screen
        if let cached = SharedCache.read() {
            apply(cached.response)
            lastFetch = cached.fetchedAt
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            await self?.loop()
        }
    }

    func refreshNow() {
        Task { @MainActor in await self.refresh() }
    }

    private func loop() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(currentInterval))
        }
    }

    private func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let response = try await UsageAPI.fetchUsage()
            apply(response)
            errorMessage = nil
            lastFetch = Date()
            currentInterval = baseInterval
            SharedCache.write(response)
        } catch let api as APIError {
            errorMessage = api.description
            if case .rateLimited(let retry) = api, let retry, retry > 0 {
                currentInterval = min(max(retry, baseInterval), maxInterval)
            } else {
                currentInterval = min(currentInterval * 2, maxInterval)
            }
        } catch {
            errorMessage = error.localizedDescription
            currentInterval = min(currentInterval * 2, maxInterval)
        }
    }

    private func apply(_ r: UsageResponse) {
        fiveHour = r.fiveHour
        sevenDay = r.sevenDay
        extraUsage = r.extraUsage
    }
}

// MARK: - Root

struct RootView: View {
    @ObservedObject var store: UsageStore
    @AppStorage("widgetSize") private var sizeRaw: String = WidgetSize.medium.rawValue

    private var size: WidgetSize { WidgetSize(rawValue: sizeRaw) ?? .medium }

    var body: some View {
        WidgetView(store: store, size: size)
            .frame(width: size.dimensions.width, height: size.dimensions.height)
            .contextMenu {
                Menu("Size") {
                    ForEach(WidgetSize.allCases, id: \.self) { s in
                        Button {
                            sizeRaw = s.rawValue
                        } label: {
                            HStack {
                                Text(s.rawValue.capitalized)
                                if s == size { Image(systemName: "checkmark") }
                            }
                        }
                    }
                }
                Divider()
                Button("Refresh now") { store.refreshNow() }
                Divider()
                Button("Check for Updates…") { UpdaterBridge.checkForUpdates() }
                Divider()
                Button("Quit") { NSApp.terminate(nil) }
            }
    }
}

// MARK: - Widget container

struct WidgetView: View {
    @ObservedObject var store: UsageStore
    let size: WidgetSize

    var body: some View {
        Group {
            switch size {
            case .small:  SmallView(store: store)
            case .medium: MediumView(store: store)
            case .large:  LargeView(store: store)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius:14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius:14, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.25), lineWidth: 0.5)
        )
    }
}

// MARK: - Small

struct SmallView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "hourglass")
                    .font(.system(size: 10))
                    .foregroundColor(.orange.opacity(0.7))
                Text("5h")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                if let f = store.fiveHour {
                    Text("\(Int(f.utilization))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
            if let d = store.fiveHour?.resetDate {
                Text(d, style: .timer)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.orange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("\u{2014}:\u{2014}:\u{2014}")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.orange.opacity(0.4))
            }
            if let f = store.fiveHour {
                PillBar(utilization: f.utilization, height: 3)
            }
        }
    }
}

// MARK: - Medium

struct MediumView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.55))
                Text("CLAUDE")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                Circle()
                    .fill(store.errorMessage == nil ? Color.green : Color.red)
                    .frame(width: 5, height: 5)
            }

            // 5h
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("5h window")
                        .font(.system(size: 10))
                        .foregroundColor(Color(white: 0.55))
                    Spacer()
                    if let f = store.fiveHour {
                        Text("\(Int(f.utilization))%")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                }
                if let d = store.fiveHour?.resetDate {
                    Text(d, style: .timer)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else {
                    Text("\u{2014}:\u{2014}:\u{2014}")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .foregroundColor(.orange.opacity(0.4))
                }
                if let f = store.fiveHour {
                    PillBar(utilization: f.utilization, height: 4)
                }
            }

            // 7d compact
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("7d total")
                        .font(.system(size: 9))
                        .foregroundColor(Color(white: 0.55))
                    Spacer()
                    if let s = store.sevenDay {
                        Text("\(Int(s.utilization))%")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                    }
                }
                if let s = store.sevenDay {
                    PillBar(utilization: s.utilization, height: 3)
                }
            }

            if let err = store.errorMessage {
                Text(err)
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
    }
}

// MARK: - Large

struct LargeView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 6) {
                Image(systemName: "hourglass")
                    .font(.system(size: 9))
                    .foregroundColor(Color(white: 0.55))
                Text("CLAUDE STATUS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.5)
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                Circle()
                    .fill(store.errorMessage == nil ? Color.green : Color.red)
                    .frame(width: 5, height: 5)
            }

            UsageRow(
                label: "5-hour window",
                utilization: store.fiveHour?.utilization,
                resetDate: store.fiveHour?.resetDate,
                primary: true
            )

            UsageRow(
                label: "7-day (all models)",
                utilization: store.sevenDay?.utilization,
                resetDate: store.sevenDay?.resetDate,
                primary: false
            )

            if let extra = store.extraUsage, extra.isEnabled, let util = extra.utilization {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Extra credits (monthly)")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.55))
                        Spacer()
                        Text("\(Int(util))%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.orange)
                    }
                    PillBar(utilization: util, height: 4)
                    if let used = extra.usedCredits, let limit = extra.monthlyLimit {
                        Text("$\(Int(used)) / $\(Int(limit))")
                            .font(.system(size: 8))
                            .foregroundColor(Color(white: 0.4))
                    }
                }
            }

            if let err = store.errorMessage {
                Text(err)
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
        }
    }
}

struct UsageRow: View {
    let label: String
    let utilization: Double?
    let resetDate: Date?
    let primary: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                    .font(.system(size: 10))
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                if let u = utilization {
                    Text("\(Int(u))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.orange)
                }
            }
            if let d = resetDate {
                Text(d, style: .timer)
                    .font(.system(size: primary ? 18 : 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(.orange)
                    .lineLimit(1)
            }
            if let u = utilization {
                PillBar(utilization: u, height: primary ? 4 : 3)
            }
        }
    }
}

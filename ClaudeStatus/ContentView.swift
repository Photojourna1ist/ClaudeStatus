import SwiftUI
import AppKit
import Combine
import Sparkle
import WidgetKit
import ServiceManagement
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
    case small, medium, wide, large

    var dimensions: CGSize {
        switch self {
        case .small:  return CGSize(width: 160, height: 80)
        case .medium: return CGSize(width: 220, height: 150)
        case .wide:   return CGSize(width: 348, height: 164)
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
    @Published var activityLog: [ActivityEntry] = []

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

    private func log(_ kind: ActivityEntry.Kind, _ message: String) {
        activityLog.append(ActivityEntry(timestamp: Date(), kind: kind, message: message))
        if activityLog.count > 100 { activityLog.removeFirst(activityLog.count - 100) }
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
            log(.success, "Fetched OK")
        } catch let api as APIError {
            errorMessage = api.description
            if case .rateLimited(let retry) = api, let retry, retry > 0 {
                currentInterval = min(max(retry, baseInterval), maxInterval)
                log(.warning, api.description)
            } else {
                currentInterval = min(currentInterval * 2, maxInterval)
                log(.error, api.description)
            }
        } catch {
            errorMessage = error.localizedDescription
            currentInterval = min(currentInterval * 2, maxInterval)
            log(.error, error.localizedDescription)
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
                Button("Reset Window Position") {
                    (NSApp.delegate as? AppDelegate)?.resetWindowPosition()
                }
                Divider()
                Button("Settings…") { SettingsWindowController.shared.show() }
                Divider()
                Button(LaunchAtLogin.preferenceIsOn ? "✓ Launch at Login" : "Launch at Login") {
                    LaunchAtLogin.setEnabled(!LaunchAtLogin.preferenceIsOn)
                }
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
            case .wide:   WideView(store: store)
            case .large:  LargeView(store: store)
            }
        }
        .padding(EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12))
        .background(ThemeStore.shared.background)
        .clipShape(RoundedRectangle(cornerRadius:14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius:14, style: .continuous)
                .strokeBorder(ThemeStore.shared.accent.opacity(0.25), lineWidth: 0.5)
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
                    .foregroundColor(ThemeStore.shared.accent.opacity(0.7))
                Text("Current Session")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .foregroundColor(Color(white: 0.55))
                Spacer()
                if let f = store.fiveHour {
                    Text("\(Int(f.utilization))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeStore.shared.accent)
                }
            }
            if let d = store.fiveHour?.resetDate {
                Text(d, style: .timer)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(ThemeStore.shared.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Text("\u{2014}:\u{2014}:\u{2014}")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(ThemeStore.shared.accent.opacity(0.4))
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

            MediumTrackerRow(
                label: "Current Session",
                utilization: store.fiveHour?.utilization,
                resetDate: store.fiveHour?.resetDate
            )

            MediumTrackerRow(
                label: "Weekly Limit",
                utilization: store.sevenDay?.utilization,
                resetDate: store.sevenDay?.resetDate
            )

            if let extra = store.extraUsage, extra.isEnabled, let util = extra.utilization {
                MediumCreditsRow(
                    utilization: util,
                    used: extra.usedCredits,
                    limit: extra.monthlyLimit
                )
            }

            if let err = store.errorMessage {
                Text(err)
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

struct MediumTrackerRow: View {
    let label: String
    let utilization: Double?
    let resetDate: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(white: 0.55))
                if let d = resetDate {
                    Text(d, style: .timer)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(ThemeStore.shared.accent)
                        .lineLimit(1)
                } else {
                    Text("—:—:—")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundColor(ThemeStore.shared.accent.opacity(0.4))
                }
                Spacer()
                if let u = utilization {
                    Text("\(Int(u))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(ThemeStore.shared.accent)
                }
            }
            if let u = utilization {
                PillBar(utilization: u, height: 3)
            }
        }
    }
}

struct MediumCreditsRow: View {
    let utilization: Double
    let used: Double?
    let limit: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("Extra Usage")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(white: 0.55))
                if let used, let limit {
                    Text(String(format: "$%.2f / $%.2f", used / 100, limit / 100))
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(ThemeStore.shared.accent)
                }
                Spacer()
                Text("\(Int(utilization))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(ThemeStore.shared.accent)
            }
            PillBar(utilization: utilization, height: 3)
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
                label: "Current Session",
                utilization: store.fiveHour?.utilization,
                resetDate: store.fiveHour?.resetDate,
                primary: true
            )

            UsageRow(
                label: "Weekly Limit",
                utilization: store.sevenDay?.utilization,
                resetDate: store.sevenDay?.resetDate,
                primary: false
            )

            if let extra = store.extraUsage, extra.isEnabled, let util = extra.utilization {
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Extra Usage")
                            .font(.system(size: 10))
                            .foregroundColor(Color(white: 0.55))
                        Spacer()
                        Text("\(Int(util))%")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(ThemeStore.shared.accent)
                    }
                    PillBar(utilization: util, height: 4)
                    if let used = extra.usedCredits, let limit = extra.monthlyLimit {
                        Text(String(format: "$%.2f / $%.2f", used / 100, limit / 100))
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
                        .foregroundColor(ThemeStore.shared.accent)
                }
            }
            if let d = resetDate {
                Text(d, style: .timer)
                    .font(.system(size: primary ? 18 : 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundColor(ThemeStore.shared.accent)
                    .lineLimit(1)
            }
            if let u = utilization {
                PillBar(utilization: u, height: primary ? 4 : 3)
            }
        }
    }
}

// MARK: - Wide  (top: 7d + Credits, bottom: 5h hero)

struct WideView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var theme = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            StatusHeader(showStatusDot: true, isHealthy: store.errorMessage == nil)

            HStack(alignment: .top, spacing: 10) {
                UsageColumn(
                    label: "Weekly Limit",
                    utilization: store.sevenDay?.utilization,
                    timer: store.sevenDay?.resetDate,
                    detail: nil
                )
                if let extra = store.extraUsage, extra.isEnabled, let util = extra.utilization {
                    Divider().frame(height: 44)
                    UsageColumn(
                        label: "Extra Usage",
                        utilization: util,
                        timer: nil,
                        detail: UsageColumn.creditsDetail(used: extra.usedCredits, limit: extra.monthlyLimit)
                    )
                }
            }

            UsageHero(
                utilization: store.fiveHour?.utilization,
                resetDate: store.fiveHour?.resetDate
            )

            if let err = store.errorMessage {
                Text(err)
                    .font(.system(size: 9))
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}

// MARK: - Launch at Login

@MainActor
enum LaunchAtLogin {
    static let key = "launchAtLogin"

    static var preferenceIsOn: Bool {
        UserDefaults.standard.bool(forKey: key)
    }

    static func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: key)
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            NSLog("LaunchAtLogin error: \(error)")
        }
    }

    static func applyCurrentPreference() {
        setEnabled(preferenceIsOn)
    }
}

// MARK: - Activity log

struct ActivityEntry: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let kind: Kind
    let message: String

    enum Kind { case success, warning, error }

    var icon: String {
        switch kind {
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.octagon.fill"
        }
    }

    var iconColor: Color {
        switch kind {
        case .success: return .green
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

// MARK: - Settings window controller

@MainActor
final class SettingsWindowController: NSObject {
    static let shared = SettingsWindowController()
    private var windowController: NSWindowController?
    weak var store: UsageStore?

    func show() {
        if let win = windowController?.window {
            win.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard let store else { return }

        let root = SettingsRootView(store: store)
        let host = NSHostingController(rootView: root)
        let win = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        win.title = "ClaudeStatus"
        win.contentViewController = host
        win.center()
        win.isReleasedWhenClosed = false

        let wc = NSWindowController(window: win)
        windowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Settings root (tab view)

struct SettingsRootView: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        TabView {
            GeneralSettingsTab(store: store)
                .tabItem { Label("Settings", systemImage: "gearshape") }

            ActivityLogTab(store: store)
                .tabItem { Label("Log", systemImage: "list.bullet.rectangle") }
        }
        .padding()
        .frame(width: 500, height: 560)
    }
}

// MARK: - General settings tab

struct GeneralSettingsTab: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var theme = ThemeStore.shared
    @AppStorage("widgetSize") private var sizeRaw: String = WidgetSize.medium.rawValue
    @State private var launchAtLogin: Bool = LaunchAtLogin.preferenceIsOn

    private var versionString: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        return "\(v) (build \(b))"
    }

    var body: some View {
        Form {
            Section {
                Picker("Widget size", selection: $sizeRaw) {
                    ForEach(WidgetSize.allCases, id: \.self) { s in
                        Text(s.rawValue.capitalized).tag(s.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Display")
            } footer: {
                Text("Right-click the widget to switch sizes quickly without opening Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Behavior") {
                Toggle("Launch at Login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { newValue in
                        launchAtLogin = newValue
                        LaunchAtLogin.setEnabled(newValue)
                    }
                ))

                HStack {
                    Text("Refresh now")
                    Spacer()
                    Button {
                        store.refreshNow()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                }

                if let last = store.lastFetch {
                    LabeledContent("Last update") {
                        Text(last, style: .relative).foregroundStyle(.secondary) + Text(" ago").foregroundStyle(.secondary)
                    }
                }
            }

            Section("Updates") {
                LabeledContent("Version", value: versionString)
                Button("Check for Updates…") {
                    UpdaterBridge.checkForUpdates()
                }
            }

            Section("Customization") {
                ColorPicker("Background", selection: Binding(
                    get: { theme.background },
                    set: { theme.backgroundHex = $0.hexString; WidgetCenter.shared.reloadAllTimelines() }
                ), supportsOpacity: false)

                Picker("Numbers & timers", selection: Binding(
                    get: { theme.accentMode },
                    set: { theme.accentMode = $0; WidgetCenter.shared.reloadAllTimelines() }
                )) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if theme.accentMode == .solid {
                    ColorPicker("Accent color", selection: Binding(
                        get: { theme.accent },
                        set: { theme.accentHex = $0.hexString; WidgetCenter.shared.reloadAllTimelines() }
                    ), supportsOpacity: false)
                }

                Picker("Pill bars", selection: Binding(
                    get: { theme.barMode },
                    set: { theme.barMode = $0; WidgetCenter.shared.reloadAllTimelines() }
                )) {
                    ForEach(ColorMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                if theme.barMode == .solid {
                    ColorPicker("Pill bar color", selection: Binding(
                        get: { Color(hexOrFallback: theme.barHex.isEmpty ? theme.accentHex : theme.barHex, fallback: ThemeDefaults.accentColor) },
                        set: { theme.barHex = $0.hexString; WidgetCenter.shared.reloadAllTimelines() }
                    ), supportsOpacity: false)
                }

                Button("Reset to defaults") {
                    theme.resetToDefaults()
                    WidgetCenter.shared.reloadAllTimelines()
                }
            }

            Section("About") {
                Link(destination: URL(string: "https://github.com/Photojourna1ist/ClaudeStatus")!) {
                    Label("Source on GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                }
                Link(destination: URL(string: "https://docs.claude.com/en/docs/claude-code/overview")!) {
                    Label("About Claude Code", systemImage: "book")
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Activity log tab

struct ActivityLogTab: View {
    @ObservedObject var store: UsageStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Activity Log")
                    .font(.headline)
                Spacer()
                if !store.activityLog.isEmpty {
                    Button("Clear") {
                        store.activityLog.removeAll()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 4)

            if store.activityLog.isEmpty {
                Spacer()
                VStack(spacing: 6) {
                    Image(systemName: "tray")
                        .font(.system(size: 28))
                        .foregroundStyle(.tertiary)
                    Text("No activity yet")
                        .foregroundStyle(.secondary)
                    Text("Fetches will appear here as they happen.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                List(store.activityLog.reversed()) { entry in
                    LogRow(entry: entry)
                }
                .listStyle(.plain)
            }
        }
    }
}

struct LogRow: View {
    let entry: ActivityEntry

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: entry.icon)
                .foregroundStyle(entry.iconColor)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.message)
                    .font(.system(size: 12, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}

import SwiftUI
import AppKit
import Sparkle
import WidgetKit
import ServiceManagement
import ClaudeStatusCore

@main
struct ClaudeStatusApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Settings scene with EmptyView satisfies the App protocol's Scene
        // requirement. We never actually open Settings — the floating panel
        // is created in the AppDelegate instead.
        Settings { EmptyView() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var panel: FloatingPanel!
    let store = UsageStore()

    // Sparkle updater. Auto-checks for updates per its default cadence (~24h).
    lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // No Dock icon

        // Handle claudestatus://reauth from the widget extension.
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        let root = RootView(store: store)
        let hosting = NSHostingController(rootView: root)
        hosting.sizingOptions = [.preferredContentSize] // Window auto-fits content

        panel = FloatingPanel()
        panel.contentViewController = hosting

        positionPanel(useSaved: true)

        // Start hidden - user shows via menu bar icon
        // Set up a menu-bar status item so the user can hide/show the panel
        // and quit the app cleanly. Without this, an LSUIElement app has no UI surface
        // when the panel is closed.
        setupStatusItem()


        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel, queue: .main
        ) { [weak self] _ in
            guard let p = self?.panel else { return }
            UserDefaults.standard.set(NSStringFromRect(p.frame), forKey: "windowFrame")
        }

        // Touch the updater so its first scheduled check is queued.
        _ = updaterController

        LaunchAtLogin.applyCurrentPreference()

        store.start()

        // Reload any placed widgets so they pick up the latest build/theme.
        WidgetCenter.shared.reloadAllTimelines()
        SettingsWindowController.shared.store = store
    }

    /// Primary screen has its frame origin at (0,0) on macOS — that is the display with the menu bar.
    /// NSScreen.main is unreliable during applicationDidFinishLaunching.
    private var primaryScreen: NSScreen? {
        NSScreen.screens.first(where: { $0.frame.origin == .zero }) ?? NSScreen.main
    }

    /// Position the floating panel. If useSaved and the saved origin is on a currently-visible
    /// screen, restore it. Otherwise place it top-right of the primary screen.
    func positionPanel(useSaved: Bool) {
        if useSaved, let frameStr = UserDefaults.standard.string(forKey: "windowFrame") {
            let saved = NSRectFromString(frameStr)
            let onScreen = NSScreen.screens.contains { $0.visibleFrame.contains(saved.origin) }
            if onScreen {
                panel.setFrameOrigin(saved.origin)
                return
            }
        }
        if let screen = primaryScreen {
            let f = screen.visibleFrame
            let size = panel.frame.size
            let x = f.maxX - size.width - 20
            let y = f.maxY - size.height - 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    /// Forget any saved position and snap to top-right of the primary screen.
    func resetWindowPosition() {
        UserDefaults.standard.removeObject(forKey: "windowFrame")
        positionPanel(useSaved: false)
        panel.makeKeyAndOrderFront(nil)
    }

    // MARK: - Menu-bar status item

    var statusItem: NSStatusItem?

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        // The button's content (live "NN%  H:MM:SS" text, or the fallback icon) is set
        // by updateStatusTitle(), driven by a 1-second timer started below.
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "Show Floating Window", action: #selector(toggleFloatingWindow(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Refresh Now", action: #selector(menuRefreshNow(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(menuOpenSettings(_:)), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Check for Updates…", action: #selector(menuCheckForUpdates(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit ClaudeStatus", action: #selector(menuQuit(_:)), keyEquivalent: "q"))
        item.menu = menu
        statusItem = item

        // Drive the menu-bar title from live usage and tick the countdown every second.
        updateStatusTitle()
        statusUpdateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            // Scheduled timers fire on the main run loop, so it's safe to hop onto the
            // main actor to touch the (main-actor-isolated) store and status item.
            MainActor.assumeIsolated { self?.updateStatusTitle() }
        }
    }

    // MARK: - Live menu-bar title

    private var statusUpdateTimer: Timer?

    /// Renders the menu-bar item as "NN%  H:MM:SS" for the 5-hour session, colored on the
    /// stepped usage scale (blue <50, yellow <70, orange <90, red ≥90). Falls back to the
    /// purple "C" icon when there's no data yet or auth has expired, so the item stays clickable.
    private func updateStatusTitle() {
        guard let button = statusItem?.button else { return }

        guard !store.authError, let bucket = store.fiveHour else {
            showStatusIcon(on: button)
            return
        }

        let util = bucket.utilization
        let pct = "\(Int(util.rounded()))%"
        let countdown = Self.countdownString(to: bucket.resetDate)
        let title = countdown.isEmpty ? pct : "\(pct)  \(countdown)"

        let attrs: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor(Color.usageStepped(at: util)),
            .font: NSFont.monospacedDigitSystemFont(
                ofSize: NSFont.systemFontSize(for: .small), weight: .semibold)
        ]
        button.image = nil
        button.attributedTitle = NSAttributedString(string: title, attributes: attrs)
    }

    /// Fallback purple "C" disc for the no-data / auth-expired states.
    private func showStatusIcon(on button: NSStatusBarButton) {
        button.attributedTitle = NSAttributedString(string: "")
        button.title = ""
        if button.image == nil {
            let purple = NSColor(red: 0.56, green: 0.40, blue: 0.95, alpha: 1.0)
            let config = NSImage.SymbolConfiguration(paletteColors: [.white, purple])
            let img = NSImage(systemSymbolName: "c.circle.fill", accessibilityDescription: "Claude Status")?
                .withSymbolConfiguration(config)
            img?.isTemplate = false
            button.image = img
        }
    }

    /// Compact countdown to `date`: "H:MM:SS" when ≥1h, else "M:SS". Empty when no date.
    private static func countdownString(to date: Date?) -> String {
        guard let date else { return "" }
        let remaining = Int(date.timeIntervalSinceNow.rounded())
        if remaining <= 0 { return "0:00" }
        let h = remaining / 3600
        let m = (remaining % 3600) / 60
        let s = remaining % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s)
                     : String(format: "%d:%02d", m, s)
    }

    @objc private func toggleFloatingWindow(_ sender: Any?) {
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            positionPanel(useSaved: true)
            panel.makeKeyAndOrderFront(nil)
            store.refreshNow()  // fresh data the moment the user shows the panel
        }
    }

    @objc private func menuRefreshNow(_ sender: Any?) {
        store.refreshNow()
    }

    @objc private func menuOpenSettings(_ sender: Any?) {
        SettingsWindowController.shared.show()
    }

    @objc private func menuCheckForUpdates(_ sender: Any?) {
        updaterController.checkForUpdates(nil)
    }

    @objc private func menuQuit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    @objc func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent reply: NSAppleEventDescriptor) {
        guard let raw = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
              let url = URL(string: raw) else { return }
        if url.scheme == "claudestatus" && url.host == "reauth" {
            AuthFlow.startReauth()
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        if let item = menu.item(at: 0) {
            item.title = panel.isVisible ? "Hide Floating Window" : "Show Floating Window"
        }
        // Opening the menu = active engagement; refresh now so the user sees fresh data
        // immediately if they pick Show Floating Window.
        store.refreshNow()
    }

    /// Programmatically pops up the menu attached to the menu-bar status item.
    /// Used when the user taps the hourglass inside the floating window header.
    func popUpStatusMenu() {
        guard let item = statusItem, let button = item.button, let menu = item.menu else { return }
        // popUpMenu(_:) shows the menu under the status item button itself.
        button.performClick(nil)
    }
}

final class FloatingPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 220, height: 150),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .utilityWindow
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

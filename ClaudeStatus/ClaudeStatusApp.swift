import SwiftUI
import AppKit
import Sparkle
import WidgetKit
import ServiceManagement

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
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "hourglass", accessibilityDescription: "Claude Status")
        }
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

import SwiftUI
import AppKit
import Sparkle

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

final class AppDelegate: NSObject, NSApplicationDelegate {
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

        // Restore saved position, or place top-right
        if let frameStr = UserDefaults.standard.string(forKey: "windowFrame") {
            panel.setFrameOrigin(NSRectFromString(frameStr).origin)
        } else if let screen = NSScreen.main {
            let f = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: f.maxX - 240, y: f.maxY - 180))
        }

        panel.makeKeyAndOrderFront(nil)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: panel, queue: .main
        ) { [weak self] _ in
            guard let p = self?.panel else { return }
            UserDefaults.standard.set(NSStringFromRect(p.frame), forKey: "windowFrame")
        }

        // Touch the updater so its first scheduled check is queued.
        _ = updaterController

        store.start()
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

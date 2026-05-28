import AppKit

@MainActor
enum AuthFlow {
    private static let claudeCliPaths = [
        "/opt/homebrew/bin/claude",
        "/usr/local/bin/claude",
        NSHomeDirectory() + "/.local/bin/claude",
    ]

    /// Kick off a Claude Code re-auth flow visible to the user.
    /// Prefers spawning the CLI in Terminal; falls back to launching Claude.app.
    static func startReauth() {
        if let cli = locateCli() {
            launchInTerminal(cli)
            return
        }
        launchClaudeAppFallback()
    }

    private static func locateCli() -> String? {
        let fm = FileManager.default
        return claudeCliPaths.first(where: { fm.isExecutableFile(atPath: $0) })
    }

    /// Open Terminal and run `claude auth login --claudeai` so the user can
    /// complete the browser-based OAuth flow.
    private static func launchInTerminal(_ cliPath: String) {
        let cmd = "\(cliPath) auth login --claudeai"
        let escaped = cmd.replacingOccurrences(of: "\"", with: "\\\"")
        let script = """
        tell application "Terminal"
            activate
            do script "\(escaped)"
        end tell
        """
        var error: NSDictionary?
        if let apple = NSAppleScript(source: script) {
            apple.executeAndReturnError(&error)
        }
    }

    /// If the CLI is not installed, surface Claude.app so the user can sign
    /// in there (it writes to the same `Claude Code-credentials` keychain item).
    private static func launchClaudeAppFallback() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.anthropic.claudefordesktop") {
            NSWorkspace.shared.open(url)
            return
        }
        let appURL = URL(fileURLWithPath: "/Applications/Claude.app")
        if FileManager.default.fileExists(atPath: appURL.path) {
            NSWorkspace.shared.open(appURL)
            return
        }
        if let signIn = URL(string: "https://claude.ai/login") {
            NSWorkspace.shared.open(signIn)
        }
    }
}

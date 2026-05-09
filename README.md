# ClaudeStatus

A floating-window macOS app and WidgetKit widget that show your Claude usage limits in real time — 5-hour rolling window, 7-day total, and extra credits.

Reads your Claude Code OAuth token from your Keychain (the same token Claude Code uses), polls Anthropic's usage endpoint with rate-limit-aware backoff, and shares cached results with the widget extension via App Groups.

## Requirements

- macOS 14 (Sonoma) or later
- [Claude Code](https://claude.ai/code) installed and signed in (the app reads its OAuth token)

## Install

Download the latest release from the [Releases page](https://github.com/Photojourna1ist/ClaudeStatus/releases). After the first launch the app auto-updates via [Sparkle](https://sparkle-project.org).

### First-time install: Gatekeeper warning

ClaudeStatus is currently signed with a Personal Team certificate, not a paid Apple Developer ID. The first time you open it, macOS will say something like *“Apple cannot verify the developer of “ClaudeStatus.app””* and refuse to launch it. To bypass this:

1. Move `ClaudeStatus.app` to your `/Applications` folder.
2. **Right-click** (or Control-click) the app icon and choose **Open**.
3. In the dialog that appears, click **Open** again.

You only have to do this once. After that, double-clicking works normally and Sparkle will handle future updates without requiring this step.

If you prefer the command line, you can clear the quarantine attribute instead:

```bash
xattr -cr /Applications/ClaudeStatus.app
```

## Build from source

Open `ClaudeStatus.xcodeproj` in Xcode 26 or newer and hit Run.

## License

Personal project — no license attached yet.

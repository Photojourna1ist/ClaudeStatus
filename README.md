# ClaudeStatus

A floating-window macOS app and WidgetKit widget that show your Claude usage limits in real time — 5-hour rolling window, 7-day total, and extra credits.

Reads your Claude Code OAuth token from your Keychain (the same token Claude Code uses), polls Anthropic's usage endpoint with rate-limit-aware backoff, and shares cached results with the widget extension via App Groups.

## Requirements

- macOS 14 (Sonoma) or later
- [Claude Code](https://claude.ai/code) installed and signed in (the app reads its OAuth token)

## Install

Download the latest release from the [Releases page](https://github.com/Photojourna1ist/ClaudeStatus/releases). The app auto-updates via [Sparkle](https://sparkle-project.org).

## Build from source

Open `ClaudeStatus.xcodeproj` in Xcode 26 or newer and hit Run.

## License

Personal project — no license attached yet.

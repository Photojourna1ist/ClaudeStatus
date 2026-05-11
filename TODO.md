# ClaudeStatus — TODO

## Pending
- [ ] Replace macOS widget app icon (currently hourglass) with the iOS bullseye design (concentric rings, red/blue/yellow/orange). The PNG already exists at: `ClaudeStatusiOS/Assets.xcassets/AppIcon.appiconset/icon-1024.png`. Adapt to the macOS AppIcon catalog format and reapply across widget surfaces.
- [ ] Verify iOS widget on Today View shows real reset data from Mac via iCloud KV sync
- [ ] Test notification fires when 5h session resets (with chosen sound)
- [ ] Investigate the mystery files (NotificationManager.swift, SettingsView.swift, ResetDateProvider.swift) that appeared at 21:49 / 21:50 on 2026-05-10 with shell-escape bugs — likely another agent watching the directory

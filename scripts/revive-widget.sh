#!/usr/bin/env bash
# Revive a gray/frozen placed ClaudeStatus widget.
# Run this ONLY on a settled system (no install/registration churn in the last
# few minutes) — that's the condition under which it reliably works.
set -euo pipefail
EXT="/Applications/ClaudeStatus.app/Contents/PlugIns/ClaudeStatusWidgetExtension.appex"
pluginkit -r "$EXT" 2>/dev/null || true
pluginkit -a "$EXT"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/ClaudeStatus.app"
killall chronod NotificationCenter WallpaperAgent 2>/dev/null || true
echo "Daemons bounced. Give it ~30s, then check the widget with your eyes —"
echo "a running extension process does NOT prove it renders. If still gray:"
echo "remove the widget and re-add it from Edit Widgets."

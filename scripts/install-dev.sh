#!/usr/bin/env bash
# Build ClaudeStatus, install to /Applications, and refresh WidgetKit safely.\n# Usage: install-dev.sh [--kick]   (--kick also bounces widget daemons at the end)
#
# ⚠️ Widget-safety rules learned 2026-09-05 (every violation = placed desktop
# widget goes gray/frozen until manually revived):
#   1. NEVER rm -rf + cp the bundle — rsync IN PLACE (preserves the inode).
#   2. NEVER pluginkit -r (unregister) — only -a. Unregistering invalidates the
#      record placed widgets resolve through.
#   3. Bounce the widget daemons LAST, after the new registration has settled
#      and the app is launched and fetching. Bouncing them 2s after lsregister
#      makes the fresh daemons bind to the stale record → frozen gray widget.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/8] Clean..."
xcodebuild -project ClaudeStatus.xcodeproj -scheme ClaudeStatus -configuration Debug -destination "platform=macOS" clean 2>&1 | tail -1

echo "[2/8] Build..."
xcodebuild -project ClaudeStatus.xcodeproj -scheme ClaudeStatus -configuration Debug -destination "platform=macOS" build 2>&1 | tail -1

echo "[3/8] Quit app..."
osascript -e "tell application \"ClaudeStatus\" to quit" 2>/dev/null || true
pkill -f "ClaudeStatus.app/Contents/MacOS/ClaudeStatus" 2>/dev/null || true
sleep 1

echo "[4/8] Sync build into /Applications (in place)..."
DEV_APP=$(find ~/Library/Developer/Xcode/DerivedData/ClaudeStatus-*/Build/Products/Debug -maxdepth 1 -name "ClaudeStatus.app" -print -quit)
echo "      from: $DEV_APP"
if [ -d "/Applications/ClaudeStatus.app" ]; then
  rsync -a --delete "$DEV_APP/" "/Applications/ClaudeStatus.app/"
else
  cp -R "$DEV_APP" "/Applications/ClaudeStatus.app"
fi

echo "[5/8] Register (additive only — no unregister)..."
EXT="/Applications/ClaudeStatus.app/Contents/PlugIns/ClaudeStatusWidgetExtension.appex"
pluginkit -a "$EXT"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/ClaudeStatus.app"
touch "/Applications/ClaudeStatus.app"  # invalidate icon cache

echo "[6/8] Launch app..."
LAUNCHED_AT=$(date +%s)
open "/Applications/ClaudeStatus.app"

echo "[7/8] Verify the app fetched fresh usage..."
PLIST="$HOME/Library/Group Containers/group.com.samcraft.ClaudeStatus/Library/Preferences/group.com.samcraft.ClaudeStatus.plist"
verify_fetch() {
  # Wait until cachedUsage.fetchedAt (Apple epoch) is newer than launch time.
  local deadline=$(( $(date +%s) + 40 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    local fetched
    fetched=$(plutil -extract cachedUsage raw -o - "$PLIST" 2>/dev/null | base64 -d 2>/dev/null \
      | python3 -c 'import json,sys; print(int(json.load(sys.stdin)["fetchedAt"] + 978307200))' 2>/dev/null || echo 0)
    if [ "${fetched:-0}" -ge "$LAUNCHED_AT" ]; then return 0; fi
    sleep 5
  done
  return 1
}
if verify_fetch; then
  echo "      OK — cache is fresh."
else
  # First launch after an install sometimes doesn't fetch/flush; one relaunch fixes it.
  echo "      no fresh fetch yet — relaunching once..."
  osascript -e "tell application \"ClaudeStatus\" to quit" 2>/dev/null || true
  sleep 2
  LAUNCHED_AT=$(date +%s)
  open "/Applications/ClaudeStatus.app"
  if verify_fetch; then
    echo "      OK after relaunch — cache is fresh."
  else
    echo "      FAILED: no fresh fetch within timeout. Check the proxy (http://192.168.1.24:7610/health) and the app."
    exit 1
  fi
fi

if [ "${1:-}" = "--kick" ]; then
  echo "[8/8] --kick: settling, then bouncing widget daemons..."
  sleep 10
  "$(dirname "$0")/revive-widget.sh"
else
  echo "[8/8] Widget daemons NOT touched (the safe default — placed widgets"
  echo "      pick up the new build on their next timeline reload, which the"
  echo "      app triggers within 30s). If the widget looks frozen a few"
  echo "      minutes from now, run scripts/revive-widget.sh separately."
fi

echo "Done."

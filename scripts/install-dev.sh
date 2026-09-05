#!/usr/bin/env bash
# Build ClaudeStatus, install to /Applications, and refresh WidgetKit safely.\n# Usage: install-dev.sh [--kick]   (--kick also bounces widget daemons at the end)
#
# ⚠️ Widget facts proven 2026-09-05 (via the widgetTimelineAt breadcrumb):
#   1. EVERY deploy detaches placed widgets — chronod stops calling
#      getTimeline entirely and the widget freezes gray on its last snapshot.
#      A deploy therefore MUST end with a daemon bounce (revive-widget.sh).
#   2. The bounce only works AFTER the churn settles — bouncing 2s after
#      lsregister rebinds the daemons to stale state (all-day gray loop).
#      Hence the sleep before step 8, and never bounce mid-install.
#   3. rsync IN PLACE, never rm -rf + cp — keep the bundle inode stable.
#   4. Verify rendering, not processes: a running appex proves nothing; only
#      a fresh widgetTimelineAt breadcrumb (or human eyes) proves the widget
#      is alive.
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

echo "[8/8] Reattach placed widgets..."
# Proven 2026-09-05: a deploy reliably STOPS chronod servicing placed widgets
# (zero getTimeline calls afterward → widget freezes gray on its last
# snapshot). The fix is a daemon bounce shortly AFTER the churn settles;
# bouncing mid-churn (the old 2s-after-lsregister ordering) rebinds daemons to
# stale state and is exactly what kept graying the widget all day.
sleep 60
"$(dirname "$0")/revive-widget.sh" >/dev/null 2>&1 || true

# The widget provider writes a breadcrumb (widgetTimelineAt) on every
# getTimeline call, and the app reloads timelines every 30s — so a live
# placed widget must produce a fresh breadcrumb within ~2 min of the bounce.
echo "      waiting for the widget to prove it renders (breadcrumb)..."
BOUNCED_AT=$(date +%s)
WDEADLINE=$(( BOUNCED_AT + 150 ))
while [ "$(date +%s)" -lt "$WDEADLINE" ]; do
  TS=$(plutil -extract widgetTimelineAt raw -o - "$PLIST" 2>/dev/null || true)
  if [ -n "${TS:-}" ]; then
    TS_EPOCH=$(python3 -c "import datetime,sys; print(int(datetime.datetime.fromisoformat(sys.argv[1].replace('Z','+00:00')).timestamp()))" "$TS" 2>/dev/null || echo 0)
    if [ "${TS_EPOCH:-0}" -ge "$BOUNCED_AT" ]; then
      echo "      OK — widget requested a timeline after the bounce; it's alive."
      echo "Done. Data verified, widget verified."
      exit 0
    fi
  fi
  sleep 10
done
echo "      WARNING: no widget timeline request since the bounce."
echo "      If a widget is placed, run scripts/revive-widget.sh again in a"
echo "      minute, or remove + re-add the widget. (No placed widget on this"
echo "      Mac = this warning is expected and harmless.)"
echo "Done. Data verified; widget NOT confirmed."

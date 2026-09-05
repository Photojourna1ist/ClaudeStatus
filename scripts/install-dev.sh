#!/usr/bin/env bash
# Build ClaudeStatus, install to /Applications, and force WidgetKit to re-register.
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

echo "[4/8] Sync build into /Applications..."
DEV_APP=$(find ~/Library/Developer/Xcode/DerivedData/ClaudeStatus-*/Build/Products/Debug -maxdepth 1 -name "ClaudeStatus.app" -print -quit)
echo "      from: $DEV_APP"
if [ -d "/Applications/ClaudeStatus.app" ]; then
  # Sync IN PLACE — never rm -rf + cp. Deleting the bundle directory destroys
  # the inode that placed desktop widgets are bound to, orphaning them: they
  # freeze on their last rendered snapshot, grayed out, until removed and
  # re-added by hand (bitten 2026-09-05). rsync into the existing directory
  # keeps the inode, so live widgets survive the upgrade.
  rsync -a --delete "$DEV_APP/" "/Applications/ClaudeStatus.app/"
else
  cp -R "$DEV_APP" "/Applications/ClaudeStatus.app"
fi

echo "[5/8] Re-register widget extension..."
EXT="/Applications/ClaudeStatus.app/Contents/PlugIns/ClaudeStatusWidgetExtension.appex"
pluginkit -r "$EXT" 2>/dev/null || true
pluginkit -a "$EXT"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/ClaudeStatus.app"
touch "/Applications/ClaudeStatus.app"  # invalidate icon cache

echo "[6/8] Kick widget cache daemons..."
killall chronod 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true
killall WallpaperAgent 2>/dev/null || true
killall Wallpaper 2>/dev/null || true
killall ControlCenter 2>/dev/null || true
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
sleep 2

echo "[7/8] Launch app..."
LAUNCHED_AT=$(date +%s)
open "/Applications/ClaudeStatus.app"

echo "[8/8] Verify the app fetched fresh usage..."
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
  echo "      OK — cache is fresh; widgets have live data."
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

echo "Done. Installed, verified fetching, widgets preserved."

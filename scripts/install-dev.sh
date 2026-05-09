#!/usr/bin/env bash
# Build ClaudeStatus, install to /Applications, and force WidgetKit to re-register.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "[1/7] Clean..."
xcodebuild -project ClaudeStatus.xcodeproj -scheme ClaudeStatus -configuration Debug -destination "platform=macOS" clean 2>&1 | tail -1

echo "[2/7] Build..."
xcodebuild -project ClaudeStatus.xcodeproj -scheme ClaudeStatus -configuration Debug -destination "platform=macOS" build 2>&1 | tail -1

echo "[3/7] Quit app..."
osascript -e "tell application \"ClaudeStatus\" to quit" 2>/dev/null || true
pkill -f "ClaudeStatus.app/Contents/MacOS/ClaudeStatus" 2>/dev/null || true
sleep 1

echo "[4/7] Copy build to /Applications..."
DEV_APP=$(find ~/Library/Developer/Xcode/DerivedData/ClaudeStatus-*/Build/Products/Debug -maxdepth 1 -name "ClaudeStatus.app" -print -quit)
echo "      from: $DEV_APP"
rm -rf "/Applications/ClaudeStatus.app"
cp -R "$DEV_APP" "/Applications/ClaudeStatus.app"

echo "[5/7] Re-register widget extension..."
EXT="/Applications/ClaudeStatus.app/Contents/PlugIns/ClaudeStatusWidgetExtension.appex"
pluginkit -r "$EXT" 2>/dev/null || true
pluginkit -a "$EXT"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/ClaudeStatus.app"
touch "/Applications/ClaudeStatus.app"  # invalidate icon cache

echo "[6/7] Kick widget cache daemons..."
killall chronod 2>/dev/null || true
killall NotificationCenter 2>/dev/null || true
killall WallpaperAgent 2>/dev/null || true
killall Wallpaper 2>/dev/null || true
killall ControlCenter 2>/dev/null || true
killall Dock 2>/dev/null || true
killall Finder 2>/dev/null || true
sleep 2

echo "[7/7] Launch app..."
open "/Applications/ClaudeStatus.app"

echo "Done. App will trigger WidgetCenter.reloadAllTimelines() on launch."

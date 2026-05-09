#!/usr/bin/env bash
# Builds, signs, and publishes a new ClaudeStatus release.
# Usage: ./scripts/release.sh                    (uses current MARKETING_VERSION)
#        ./scripts/release.sh 1.0.1               (bumps to specified version first)

set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
TOOLS="$ROOT/.tools/sparkle/bin"

if [ ! -x "$TOOLS/generate_appcast" ]; then
  echo "Sparkle tools missing at $TOOLS — re-fetching"
  mkdir -p "$ROOT/.tools"
  URL=$(curl -fsSL https://api.github.com/repos/sparkle-project/Sparkle/releases/latest \
    | python3 -c 'import sys,json; d=json.load(sys.stdin); [print(a["browser_download_url"]) for a in d["assets"] if a["name"].endswith(".tar.xz")]' \
    | head -1)
  curl -fsSL -o "$ROOT/.tools/sparkle.tar.xz" "$URL"
  rm -rf "$ROOT/.tools/sparkle"
  mkdir -p "$ROOT/.tools/sparkle"
  tar -xf "$ROOT/.tools/sparkle.tar.xz" -C "$ROOT/.tools/sparkle"
fi

# Optional version bump
if [ "${1:-}" != "" ]; then
  NEW_VERSION="$1"
  echo "Bumping MARKETING_VERSION to $NEW_VERSION"
  python3 - "$NEW_VERSION" <<'PYEOF'
import sys, re, pathlib
v = sys.argv[1]
p = pathlib.Path('ClaudeStatus.xcodeproj/project.pbxproj')
s = p.read_text()
s = re.sub(r'MARKETING_VERSION = [^;]+;', f'MARKETING_VERSION = {v};', s)
# Bump CURRENT_PROJECT_VERSION too (monotonic build number)
def bump(m):
    return f'CURRENT_PROJECT_VERSION = {int(m.group(1))+1};'
s = re.sub(r'CURRENT_PROJECT_VERSION = (\d+);', bump, s)
p.write_text(s)
PYEOF
fi

# Read current version
VERSION=$(xcodebuild -project ClaudeStatus.xcodeproj -showBuildSettings -target ClaudeStatus 2>/dev/null \
  | awk '/MARKETING_VERSION/ {print $3; exit}')
BUILD=$(xcodebuild -project ClaudeStatus.xcodeproj -showBuildSettings -target ClaudeStatus 2>/dev/null \
  | awk '/CURRENT_PROJECT_VERSION/ {print $3; exit}')

echo "Building ClaudeStatus $VERSION (build $BUILD)"

# Archive
ARCHIVE="$(mktemp -d)/ClaudeStatus.xcarchive"
xcodebuild -project ClaudeStatus.xcodeproj \
  -scheme ClaudeStatus \
  -configuration Release \
  -archivePath "$ARCHIVE" \
  archive | tail -5

APP_IN_ARCHIVE="$ARCHIVE/Products/Applications/ClaudeStatus.app"
if [ ! -d "$APP_IN_ARCHIVE" ]; then
  echo "Archive failed — no .app at $APP_IN_ARCHIVE"
  exit 1
fi

# Stage app and zip into docs/
STAGE="$(mktemp -d)"
cp -R "$APP_IN_ARCHIVE" "$STAGE/"
ZIP_NAME="ClaudeStatus-$VERSION.zip"
ZIP_PATH="$ROOT/docs/$ZIP_NAME"
rm -f "$ZIP_PATH"
( cd "$STAGE" && ditto -c -k --keepParent ClaudeStatus.app "$ZIP_PATH" )

ZIP_SIZE=$(stat -f%z "$ZIP_PATH")
echo "Built $ZIP_NAME ($ZIP_SIZE bytes)"

# Generate appcast.xml. Sparkle reads .zip files in the dir, looks up version
# from each app's Info.plist, signs each with the private key in your Keychain,
# and writes a complete appcast.
"$TOOLS/generate_appcast" "$ROOT/docs" \
  --download-url-prefix "https://photojourna1ist.github.io/ClaudeStatus/" \
  --link "https://github.com/Photojourna1ist/ClaudeStatus"

echo 'appcast.xml regenerated'

# Commit and push (only if there are changes)
git add docs/ ClaudeStatus.xcodeproj/project.pbxproj
if git diff --cached --quiet; then
  echo 'No changes to commit'
else
  git commit -m "Release v$VERSION (build $BUILD)"
  git tag -f "v$VERSION"
  git push origin main
  git push origin -f "v$VERSION"
fi

echo "Done. Once GitHub Pages refreshes (~1 min), the appcast will be at:"
echo "  https://photojourna1ist.github.io/ClaudeStatus/appcast.xml"

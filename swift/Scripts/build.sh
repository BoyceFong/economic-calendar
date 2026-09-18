#!/bin/bash
# Build EconomicCalendar.app from the Swift package.
#
# Usage:
#   Scripts/build.sh                 # build dist/EconomicCalendar.app (release)
#   Scripts/build.sh --debug         # debug build
#   Scripts/build.sh --open          # build + launch the .app
#   Scripts/build.sh --install       # build + install to /Applications (fallback ~/Applications) + launch
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SWIFT_DIR="$(dirname "$SCRIPT_DIR")"          # swift/
REPO_ROOT="$(dirname "$SWIFT_DIR")"

# xcode-select points at Command Line Tools; Liquid Glass needs the Xcode 26 SDK.
export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"

CONFIG="release"
OPEN=0
INSTALL=0
for arg in "$@"; do
  case "$arg" in
    --debug)  CONFIG="debug" ;;
    --open)   OPEN=1 ;;
    --install) INSTALL=1 ;;
    *) echo "Unknown option: $arg"; exit 1 ;;
  esac
done

cd "$SWIFT_DIR"
echo "==> swift build -c $CONFIG"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_DIR="$SWIFT_DIR/dist/EconomicCalendar.app"

echo "==> Assembling $APP_DIR"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$BIN_PATH/EconomicCalendar" "$APP_DIR/Contents/MacOS/EconomicCalendar"
cp "$SWIFT_DIR/Support/Info.plist" "$APP_DIR/Contents/Info.plist"

# SPM resource bundle (ExtractCalendar.js) + app icon.
for bundle in "$BIN_PATH"/*.bundle; do
  [ -e "$bundle" ] && cp -R "$bundle" "$APP_DIR/Contents/Resources/"
done
cp "$SWIFT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

echo "==> Ad-hoc codesign"
codesign --force --sign - "$APP_DIR"

if [ "$INSTALL" = "1" ]; then
  pkill -x EconomicCalendar 2>/dev/null || true
  TARGET="/Applications"
  if [ ! -w "$TARGET" ]; then TARGET="$HOME/Applications"; fi
  echo "==> Installing to $TARGET"
  rm -rf "$TARGET/EconomicCalendar.app"
  cp -R "$APP_DIR" "$TARGET/EconomicCalendar.app"
  xattr -cr "$TARGET/EconomicCalendar.app"
  open "$TARGET/EconomicCalendar.app"
elif [ "$OPEN" = "1" ]; then
  open "$APP_DIR"
fi

echo "==> Done: $APP_DIR"

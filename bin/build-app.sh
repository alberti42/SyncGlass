#!/bin/sh
# Build build/SyncGlass.app, a universal binary (arm64 + x86_64), with the login
# helper embedded in Contents/Library/LoginItems.
#
# Signing: set SIGN_IDENTITY to a "Developer ID Application" identity (see
# `security find-identity -v -p codesigning`), e.g.
#   SIGN_IDENTITY="Developer ID Application: Andrea Alberti (9V3X7C8VCK)" bin/build-app.sh
# The app is then signed with the hardened runtime and a secure timestamp, as
# notarization requires. Without SIGN_IDENTITY it is signed ad hoc, which is
# enough to run it on this Mac.
#
# Set ARCHS=native to build only for this Mac's architecture (faster).
set -eu
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:--}"
case "${ARCHS:-universal}" in
    native) ARCH_FLAGS="" ;;
    *)      ARCH_FLAGS="--arch arm64 --arch x86_64" ;;
esac

# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS --product SyncGlass
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS --product LoginHelper
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCH_FLAGS --show-bin-path)"

APP=build/SyncGlass.app
HELPER="$APP/Contents/Library/LoginItems/SyncGlassLoginHelper.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$HELPER/Contents/MacOS"

cp "$BIN/SyncGlass" "$APP/Contents/MacOS/SyncGlass"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/LoginHelper" "$HELPER/Contents/MacOS/SyncGlassLoginHelper"
cp Resources/LoginHelper-Info.plist "$HELPER/Contents/Info.plist"

# Compile the Icon Composer file into Assets.car and AppIcon.icns. Info.plist
# names the icon in CFBundleIconName and CFBundleIconFile, so the partial plist
# that actool writes is not used.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist build/AppIcon-partial.plist >/dev/null

# A secure timestamp needs Apple's timestamp server; ad-hoc signatures cannot have one.
if [ "$IDENTITY" = "-" ]; then TIMESTAMP="--timestamp=none"; else TIMESTAMP="--timestamp"; fi

# Sign inside out: the helper first, then the app that contains it.
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$HELPER"
codesign --force --options runtime "$TIMESTAMP" --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"
lipo -archs "$APP/Contents/MacOS/SyncGlass"

echo "Built $APP (signed with: $IDENTITY)"

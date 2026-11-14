#!/bin/sh
# Build build/SyncGlass.app, a universal binary (arm64 + x86_64), with the login
# helper embedded in Contents/Library/LoginItems and Sparkle.framework in
# Contents/Frameworks.
#
# Signing: set SIGN_IDENTITY to a "Developer ID Application" identity (see
# `security find-identity -v -p codesigning`), e.g.
#   SIGN_IDENTITY="Developer ID Application: Andrea Alberti (9V3X7C8VCK)" bin/build-app.sh
# The app is then signed with the hardened runtime and a secure timestamp, as
# notarization requires. Without SIGN_IDENTITY it is signed ad hoc, without the
# hardened runtime, which is enough to run it on this Mac.
#
# Set ARCHS=native to build only for this Mac's architecture (faster).
set -eu
cd "$(dirname "$0")/.."

IDENTITY="${SIGN_IDENTITY:--}"
case "${ARCHS:-universal}" in
    native) ARCH_FLAGS="" ;;
    *)      ARCH_FLAGS="--arch arm64 --arch x86_64" ;;
esac

# The SDK version recorded in the binary decides the look: AppKit and SwiftUI
# use Liquid Glass only for apps linked against the macOS 26 SDK or later, and
# show the pre-26 design otherwise. SwiftPM links with `clang --sysroot`, which
# records the deployment target (15.0) as the SDK version; `-isysroot` makes
# clang read the real version from the SDK.
SDK="$(xcrun --sdk macosx --show-sdk-path)"
SDK_FLAGS="-Xswiftc -Xclang-linker -Xswiftc -isysroot -Xswiftc -Xclang-linker -Xswiftc $SDK"

# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS $SDK_FLAGS --product SyncGlass
# shellcheck disable=SC2086
swift build -c release $ARCH_FLAGS $SDK_FLAGS --product LoginHelper
# shellcheck disable=SC2086
BIN="$(swift build -c release $ARCH_FLAGS $SDK_FLAGS --show-bin-path)"

# Stop if the binary would get the pre-26 look.
for sdk in $(vtool -show-build "$BIN/SyncGlass" | awk '$1 == "sdk" { print $2 }'); do
    if [ "${sdk%%.*}" -lt 26 ]; then
        echo "error: $BIN/SyncGlass records SDK $sdk; it must be 26 or later for Liquid Glass" >&2
        exit 1
    fi
done

APP=build/SyncGlass.app
HELPER="$APP/Contents/Library/LoginItems/SyncGlassLoginHelper.app"
rm -rf "$APP"
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$HELPER/Contents/MacOS"

cp "$BIN/SyncGlass" "$APP/Contents/MacOS/SyncGlass"
# ditto keeps the symbolic links inside the framework.
ditto "$BIN/Sparkle.framework" "$SPARKLE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN/LoginHelper" "$HELPER/Contents/MacOS/SyncGlassLoginHelper"
cp Resources/LoginHelper-Info.plist "$HELPER/Contents/Info.plist"

# Compile the Icon Composer file into Assets.car and AppIcon.icns. Info.plist
# names the icon in CFBundleIconName and CFBundleIconFile, so the partial plist
# that actool writes is not used.
xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 15.0 --app-icon AppIcon \
    --output-partial-info-plist build/AppIcon-partial.plist >/dev/null

# A secure timestamp needs Apple's timestamp server; ad-hoc signatures cannot have one.
# The hardened runtime is for notarization only: it turns on library validation,
# which on macOS 27 refuses to load the ad-hoc-signed Sparkle into an ad-hoc app
# ("different Team IDs"), so ad-hoc builds go without it.
if [ "$IDENTITY" = "-" ]; then
    TIMESTAMP="--timestamp=none"; RUNTIME=""
else
    TIMESTAMP="--timestamp"; RUNTIME="--options runtime"
fi

# Sign inside out: Sparkle's helpers, Sparkle, the login helper, then the app
# that contains them. The order and the flags follow Sparkle's documentation
# ("Code Signing", sparkle-project.org/documentation/sandboxing).
SIGN="codesign --force $RUNTIME $TIMESTAMP --sign"
$SIGN "$IDENTITY" "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
$SIGN "$IDENTITY" --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
$SIGN "$IDENTITY" "$SPARKLE/Versions/B/Autoupdate"
$SIGN "$IDENTITY" "$SPARKLE/Versions/B/Updater.app"
$SIGN "$IDENTITY" "$SPARKLE"
# shellcheck disable=SC2086
codesign --force $RUNTIME "$TIMESTAMP" --sign "$IDENTITY" "$HELPER"
# shellcheck disable=SC2086
codesign --force $RUNTIME "$TIMESTAMP" --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"
lipo -archs "$APP/Contents/MacOS/SyncGlass"

echo "Built $APP (signed with: $IDENTITY)"

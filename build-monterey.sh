#!/bin/bash
# SPDX-License-Identifier: GPL-3.0-or-later
#
# build-monterey.sh: builds the UNOFFICIAL macOS 12 (Monterey) port of
# Vorssaint Utils as "Unupunct MacTab" (bundle id local.unupunct.mactab).
#
# It does NOT replace upstream's build.sh and does not touch it. Run it ON the
# Mac that will run the app; it refuses to claim anything it did not do.
#
#   ./build-monterey.sh              preflight, compile, bundle, ad-hoc sign, verify, zip
#   ./build-monterey.sh --test       also compile and run the unit tests (see below)
#   ./build-monterey.sh --opt -O     optimised build (default -Onone, much faster to compile)
#   ./build-monterey.sh --reuse      reuse build/Vorssaint if it exists (skip the app compile)
#
# Output: build/Unupunct MacTab.app, build/UnupunctMacTab-<version>-<arch>.zip and ...-macOS12.dmg,
#         full log in build/build-monterey.log. Exit status is non-zero on any failure.
#
# Requirements (checked below): macOS 12+, Command Line Tools or Xcode with Swift 5.7+,
# a macOS SDK that has the macOS 12 symbols (13.1 is what the port was developed with).

set -u -o pipefail
cd "$(dirname "$0")"

OPT="-Onone"; RUN_TESTS=0; REUSE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --test) RUN_TESTS=1 ;;
        --reuse) REUSE=1 ;;
        --opt) shift; OPT="${1:-}" ;;
        -h|--help) sed -n 2,24p "$0"; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

mkdir -p build
LOG="build/build-monterey.log"
exec > >(tee "$LOG") 2>&1

APP_NAME="Unupunct MacTab"
EXECUTABLE="UnupunctMacTab"
BUNDLE_ID="local.unupunct.mactab"
MIN_OS="12.3"
ARCH="$(uname -m)"
TARGET="${ARCH}-apple-macosx${MIN_OS}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist 2>/dev/null || echo 0)"
UPSTREAM_VERSION="$VERSION"
VERSION="${UPSTREAM_VERSION}-monterey.1"   # this port's own version, on top of the upstream release it is based on
STAGE="build/${APP_NAME}.app"
ZIP="build/${EXECUTABLE}-${VERSION}-${ARCH}.zip"

fail() { echo "✗ $*" >&2; exit 1; }
step() { echo; echo "▸ $*"; }

# ---------------------------------------------------------------- preflight
step "Preflight"
[ "$(uname -s)" = "Darwin" ] || fail "this script builds a macOS app and must run on macOS"
OS_VERSION="$(sw_vers -productVersion)"
OS_MAJOR="${OS_VERSION%%.*}"
echo "  macOS            : $OS_VERSION ($(sw_vers -buildVersion))"
[ "$OS_MAJOR" -ge 12 ] || fail "macOS 12 or newer is required (found $OS_VERSION)"
echo "  architecture     : $ARCH"
case "$ARCH" in
    x86_64|arm64) ;;
    *) fail "unsupported architecture $ARCH" ;;
esac
command -v swiftc >/dev/null 2>&1 || fail "swiftc not found: install the Command Line Tools (xcode-select --install) or Xcode"
SWIFT_VERSION="$(swiftc --version 2>&1 | head -1)"
echo "  compiler         : $SWIFT_VERSION"
SDK="$(xcrun --show-sdk-path 2>/dev/null)" || fail "no macOS SDK (xcrun --show-sdk-path failed)"
SDK_VERSION="$(xcrun --show-sdk-version 2>/dev/null || echo unknown)"
echo "  SDK              : $SDK (version $SDK_VERSION)"
if [ -d /Applications/Xcode.app ]; then
    echo "  Xcode            : $(xcodebuild -version 2>/dev/null | head -1)"
else
    echo "  Xcode            : not installed (Command Line Tools only; no actool, no asset catalog)"
fi
for tool in iconutil codesign ditto /usr/libexec/PlistBuddy; do
    command -v "$tool" >/dev/null 2>&1 || [ -x "$tool" ] || fail "required tool missing: $tool"
done
[ -f Sources/Vorssaint/Support/MontereyCompat.swift ] || fail "run this from the repository root of the monterey-port branch"
echo "  deployment target: macOS $MIN_OS ($TARGET)"
echo "  universal binary : NO. Built for $ARCH only; the other architecture is neither built nor tested here."
echo "  optimisation     : $OPT"

BRIDGE=(-import-objc-header Sources/MontereyCompat/Bridging.h)
INCLUDES=(-I Sources/VMStatisticsCompat -I Sources/HIDEventSystem)
COMMON=(-target "$TARGET" -sdk "$SDK")
SOLVER=(-Xfrontend -solver-expression-time-threshold=3000 -Xfrontend -solver-memory-threshold -Xfrontend 4000000000)

# ------------------------------------------------------------------ compile
if [ "$REUSE" = "1" ] && [ -x "build/Vorssaint" ]; then
    step "Reusing existing build/Vorssaint (--reuse)"
else
    step "Compiling the app ($(find Sources/Vorssaint -name '*.swift' | wc -l | tr -d ' ') Swift files)"
    swiftc $OPT -j "$(sysctl -n hw.logicalcpu)" -enable-batch-mode -module-name Vorssaint \
        "${COMMON[@]}" "${BRIDGE[@]}" "${INCLUDES[@]}" "${SOLVER[@]}" \
        $(find Sources/Vorssaint -name '*.swift' | sort) -o build/Vorssaint || fail "app compile failed"
fi
[ -x build/Vorssaint ] || fail "build/Vorssaint was not produced"

step "Compiling the Now Playing adapter"
swiftc -O "${COMMON[@]}" -emit-library -module-name VorssaintNowPlaying \
    Sources/NowPlayingAdapter/NowPlayingAdapter.swift \
    Sources/NowPlayingAdapter/NowPlayingQueue.swift \
    Sources/NowPlayingAdapter/NowPlayingSelection.swift \
    Sources/Vorssaint/Services/Notch/NotchPlaybackSource.swift \
    Sources/Vorssaint/Services/Notch/NotchPlaybackCommand.swift \
    -o build/libVorssaintNowPlaying.dylib || fail "adapter compile failed"

step "Compiling the fan-control helper (verification only: it is NOT bundled, see MONTEREY-COMPATIBILITY.md)"
swiftc -O "${COMMON[@]}" "${BRIDGE[@]}" "${INCLUDES[@]}" \
    Sources/Vorssaint/Services/FanControl/FanControlSupport.swift \
    Sources/Vorssaint/Services/FanControl/FanControlXPC.swift \
    Sources/Vorssaint/Services/SystemMonitor/SMCClient.swift \
    Sources/Vorssaint/Services/Metrics/TemperatureSensorSelector.swift \
    Sources/Vorssaint/Services/FanControl/FanControlHardware.swift \
    Sources/FanControlHelper/main.swift -o build/fan-helper || fail "fan helper compile failed"
./build/fan-helper --selftest || fail "fan helper self-test failed"

# -------------------------------------------------------------------- icons
step "Generating this fork's own icon set"
swift Tools/MakeMontereyIcon.swift build/brand || fail "icon generation failed"

# ------------------------------------------------------------------- bundle
step "Assembling $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources" "$STAGE/Contents/Frameworks"
cp build/Vorssaint "$STAGE/Contents/MacOS/$EXECUTABLE"
cp build/libVorssaintNowPlaying.dylib "$STAGE/Contents/Frameworks/libVorssaintNowPlaying.dylib"
cp Resources/now-playing.pl Resources/agent-prices.json "$STAGE/Contents/Resources/"
cp CHANGELOG.md "$STAGE/Contents/Resources/CHANGELOG.md"
cp build/brand/AppIcon.icns build/brand/MenuBarIcon.png "build/brand/MenuBarIcon@2x.png" build/brand/BrandMark.png \
    "$STAGE/Contents/Resources/"
if [ -d Resources/Gifs ]; then
    mkdir -p "$STAGE/Contents/Resources/Gifs"
    cp Resources/Gifs/*.gif "$STAGE/Contents/Resources/Gifs/"
fi
for lproj in Resources/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$STAGE/Contents/Resources/"
done
printf 'APPL????' > "$STAGE/Contents/PkgInfo"

PLIST="$STAGE/Contents/Info.plist"
cp Resources/Info.plist "$PLIST"
PB=/usr/libexec/PlistBuddy
"$PB" -c "Set :CFBundleIdentifier $BUNDLE_ID" "$PLIST"
"$PB" -c "Set :CFBundleName $APP_NAME" "$PLIST"
"$PB" -c "Set :CFBundleDisplayName $APP_NAME" "$PLIST"
"$PB" -c "Set :CFBundleExecutable $EXECUTABLE" "$PLIST"
"$PB" -c "Set :LSMinimumSystemVersion $MIN_OS" "$PLIST"
"$PB" -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
"$PB" -c "Delete :CFBundleIconName" "$PLIST" 2>/dev/null || true   # no asset catalog without actool
"$PB" -c "Set :NSHumanReadableCopyright © Vorssaint contributors, GPL-3.0-or-later. Unofficial macOS 12 port." "$PLIST"
# macOS 12 reads NSCalendarsUsageDescription; NSCalendarsFullAccessUsageDescription is the macOS 14 key.
CAL="$("$PB" -c 'Print :NSCalendarsFullAccessUsageDescription' "$PLIST" 2>/dev/null || true)"
"$PB" -c "Add :NSCalendarsUsageDescription string $CAL" "$PLIST"
# Own name in every permission prompt and localisation; the upstream name is not used by this fork.
sed -i '' "s/Vorssaint/$APP_NAME/g" "$PLIST"
find "$STAGE/Contents/Resources" -name '*.strings' -exec sed -i '' "s/Vorssaint/$APP_NAME/g" {} + 2>/dev/null || true
plutil -lint "$PLIST" || fail "Info.plist is not valid"

# --------------------------------------------------------------------- sign
step "Signing (ad-hoc: this fork has no Developer ID; macOS will ask you to approve it on first launch)"
xattr -cr "$STAGE" 2>/dev/null || true
codesign --force --sign - "$STAGE/Contents/Frameworks/libVorssaintNowPlaying.dylib" || fail "signing the adapter failed"
# The entitlements file may have CRLF line endings, which codesign's parser rejects.
tr -d '' < Resources/Vorssaint.entitlements > build/entitlements.plist
plutil -lint build/entitlements.plist >/dev/null || fail "entitlements are not valid"
codesign --force --sign - --entitlements build/entitlements.plist "$STAGE" || fail "signing the app failed"
codesign --verify --deep --strict "$STAGE" || fail "signature verification failed"

# ------------------------------------------------------------------- verify
step "Verifying the bundle"
MINOS="$(vtool -show-build "$STAGE/Contents/MacOS/$EXECUTABLE" 2>/dev/null | awk '/minos/ {print $2}' | head -1)"
echo "  executable       : $(file -b "$STAGE/Contents/MacOS/$EXECUTABLE")"
echo "  minimum macOS    : ${MINOS:-unknown} (Info.plist says $("$PB" -c 'Print :LSMinimumSystemVersion' "$PLIST"))"
echo "  bundle identifier: $("$PB" -c 'Print :CFBundleIdentifier' "$PLIST")"
[ "$MINOS" = "$MIN_OS" ] || fail "executable minimum OS ($MINOS) is not $MIN_OS"
echo "  frameworks linked: $(otool -L "$STAGE/Contents/MacOS/$EXECUTABLE" | tail -n +2 | wc -l | tr -d ' ') libraries"

# -------------------------------------------------------------------- tests
if [ "$RUN_TESTS" = "1" ]; then
    step "Unit tests"
    if [ -x ./build-monterey-tests.sh ]; then
        ./build-monterey-tests.sh || fail "unit tests failed"
    else
        fail "--test needs build-monterey-tests.sh, which is missing"
    fi
fi

# ---------------------------------------------------------------------- zip
step "Packaging"
rm -f "$ZIP"
ditto -c -k --keepParent "$STAGE" "$ZIP" || fail "zip failed"
DMG="build/${EXECUTABLE}-${VERSION}-${ARCH}-macOS12.dmg"
rm -f "$DMG"; rm -rf build/dmg-root; mkdir -p build/dmg-root
cp -R "$STAGE" build/dmg-root/
ln -s /Applications build/dmg-root/Applications
hdiutil create -quiet -volname "$APP_NAME" -srcfolder build/dmg-root -ov -format UDZO "$DMG" || fail "dmg creation failed"
hdiutil verify -quiet "$DMG" || fail "dmg verification failed"
rm -rf build/dmg-root
echo "  dmg : $PWD/$DMG ($(du -h "$DMG" | cut -f1))"
echo "  app : $PWD/$STAGE"
echo "  zip : $PWD/$ZIP ($(du -h "$ZIP" | cut -f1))"
echo "  log : $PWD/$LOG"
echo
echo "✓ Built for $ARCH, macOS $MIN_OS+. NOT yet verified by running: launch it and check MONTEREY-COMPATIBILITY.md."

#!/bin/zsh
# Builds Glance.app into ./build.
#   --run      relaunches it afterwards, with the welcome tour
#   --release  leaves out where it was built from (so no Rebuild menu item), for release.sh
set -euo pipefail
cd "$(dirname "$0")"

RUN=false RELEASE=false
for arg in "$@"; do
    case "$arg" in
        --run) RUN=true ;;
        --release) RELEASE=true ;;
        *) echo "Unknown option: $arg" >&2; exit 64 ;;
    esac
done

swift build -c release

APP=build/Glance.app
PLIST="$APP/Contents/Info.plist"
FRAMEWORKS="$APP/Contents/Frameworks"
SHARE="$APP/Contents/PlugIns/GlanceShare.appex"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$FRAMEWORKS" "$SHARE/Contents/MacOS"
cp .build/release/Glance "$APP/Contents/MacOS/Glance"
# The Now Playing helper, which the app loads into /usr/bin/perl.
cp .build/release/libGlanceNowPlaying.dylib "$FRAMEWORKS/"
# Sparkle, for Check for Updates…. Glance isn't sandboxed, so it needs none of Sparkle's XPC services.
ditto .build/release/Sparkle.framework "$FRAMEWORKS/Sparkle.framework"
rm -rf "$FRAMEWORKS/Sparkle.framework/Versions/B/XPCServices" "$FRAMEWORKS/Sparkle.framework/XPCServices"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/Glance"
cp Resources/Info.plist "$PLIST"
# Glance Tray in the Share menu, an app extension, at the app's own version.
cp .build/release/GlanceShare "$SHARE/Contents/MacOS/GlanceShare"
cp Resources/GlanceShare-Info.plist "$SHARE/Contents/Info.plist"
for key in CFBundleShortVersionString CFBundleVersion; do
    /usr/libexec/PlistBuddy -c "Set :$key $(/usr/libexec/PlistBuddy -c "Print :$key" "$PLIST")" "$SHARE/Contents/Info.plist"
done
if ! $RELEASE; then
    # Lets the running app find its way back here for the Rebuild menu item.
    /usr/libexec/PlistBuddy -c "Add :GlanceSourceDirectory string $PWD" "$PLIST"
    /usr/libexec/PlistBuddy -c "Add :GlanceBuildDate string $(date '+%b %-d at %H:%M:%S')" "$PLIST"
fi

# Sign with the Apple Development identity when there is one: unlike an ad-hoc signature it
# stays the same across builds, so macOS remembers permissions such as controlling Spotify.
# Inside out: Sparkle's helpers, Sparkle, the Now Playing helper, the Share extension in its
# sandbox, then the app around them.
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 -o '"Apple Development[^"]*"' | tr -d '"' || true)
sign() { codesign --force --sign "${IDENTITY:--}" "$@" >/dev/null 2>&1; }
SPARKLE="$FRAMEWORKS/Sparkle.framework/Versions/B"
sign "$SPARKLE/Autoupdate"
sign "$SPARKLE/Updater.app"
sign "$FRAMEWORKS/Sparkle.framework"
sign "$FRAMEWORKS/libGlanceNowPlaying.dylib"
sign --entitlements Resources/GlanceShare.entitlements "$SHARE"
sign "$APP"
echo "Built $APP"

if $RUN; then
    # -a: also match ancestors, since Rebuild runs this script as a child of Glance itself.
    pkill -a -x Glance 2>/dev/null || true
    # Wait for the old copy to exit, or `open` just re-activates it.
    while pgrep -a -x Glance >/dev/null; do sleep 0.1; done
    # Launch Services can still be letting go of the old copy; try once more after a moment.
    # --onboarding: the welcome tour opens with each new build.
    open "$APP" --args --onboarding || { sleep 1; open "$APP" --args --onboarding; }
fi

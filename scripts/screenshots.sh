#!/bin/zsh
# App Store screenshots: builds the Debug app once, then launches it with `-dgScreenshots
# -dgScreenshotScreen <name>` for every shot in docs/appstore/screenshots.md and captures the
# simulator, in light and dark mode, for the iPhone and the watch. Raw frames only — no device
# bezels or caption overlays; the captions live in $OUT/captions.md.
#
#   scripts/screenshots.sh [--skip-build] [--only iphone|watch] [--appearance light|dark]
#
# Env: IPHONE_UDID, WATCH_UDID, OUT (output root), DERIVED (derived data path).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IPHONE_UDID="${IPHONE_UDID:-4748921C-4155-4CDC-BD8F-EEFCC9719CB1}"   # iPhone 17 Pro Max, iOS 27
WATCH_UDID="${WATCH_UDID:-297DE1E6-04CE-4BD1-B911-01B7179DDBA5}"     # Apple Watch SE 44 mm
OUT="${OUT:-$ROOT/build/appstore}"
DERIVED="${DERIVED:-$ROOT/build/DerivedData-screenshots}"
BUNDLE="dev.abdirahmanmohamed.dagym"
WATCH_BUNDLE="$BUNDLE.watchkitapp"
SETTLE="${SETTLE:-6}"   # seconds to let a screen load and animate in before the capture

SKIP_BUILD=0; ONLY=""; APPEARANCES=(light dark)
while [[ $# -gt 0 ]]; do
    case "$1" in
        --skip-build) SKIP_BUILD=1 ;;
        --only) ONLY="$2"; shift ;;
        --appearance) APPEARANCES=("$2"); shift ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
    shift
done

# name:screen — order is the App Store display order from the plan, extras after.
IPHONE_SHOTS=(
    01-workout:workout
    02-rest:rest
    03-progress-charts:progress
    04-exercise-chart:chart
    05-records:records
    06-consistency:consistency
    07-recovery:recovery
    08-routines:routines
    09-routine-builder:builder
    10-exercise-detail:exerciseDetail
    11-settings-data:settingsData
    12-home:home
    13-summary:summary
    14-milestones:milestones
    15-body:body
    16-library:library
    17-coach:coach
)
WATCH_SHOTS=(
    01-home:home
    02-working:working
    03-rest:rest-full
    04-pr:pr
    05-summary:summary
    06-voice:voice
    07-complications:complications
    08-home-rest:home-rest
    09-settings:settings
)

build() {
    echo "== Building Debug for the iPhone simulator"
    xcodebuild -project "$ROOT/DaGym.xcodeproj" -scheme DaGym -configuration Debug \
        -destination "id=$IPHONE_UDID" -derivedDataPath "$DERIVED" build -quiet
}

boot() {
    local udid="$1"
    xcrun simctl boot "$udid" 2>/dev/null || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
}

clean_status_bar() {
    xcrun simctl status_bar "$1" override --time 9:41 --batteryState charged --batteryLevel 100 \
        --wifiBars 3 --cellularBars 4 2>/dev/null || true
}

# capture <udid> <bundle> <png> <launch args...>
capture() {
    local udid="$1" bundle="$2" png="$3"; shift 3
    xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
    xcrun simctl launch "$udid" "$bundle" "$@" >/dev/null
    sleep "$SETTLE"
    xcrun simctl io "$udid" screenshot "$png" >/dev/null 2>&1
    xcrun simctl terminate "$udid" "$bundle" 2>/dev/null || true
    echo "   $(basename "$png")"
}

shoot_iphone() {
    local app="$DERIVED/Build/Products/Debug-iphonesimulator/DaGym.app"
    boot "$IPHONE_UDID"
    xcrun simctl install "$IPHONE_UDID" "$app"
    clean_status_bar "$IPHONE_UDID"
    for appearance in "${APPEARANCES[@]}"; do
        xcrun simctl ui "$IPHONE_UDID" appearance "$appearance"
        local dir="$OUT/iphone/$appearance"; mkdir -p "$dir"
        echo "== iPhone · $appearance → $dir"
        for shot in "${IPHONE_SHOTS[@]}"; do
            capture "$IPHONE_UDID" "$BUNDLE" "$dir/${shot%%:*}.png" \
                -dgScreenshots -dgScreenshotScreen "${shot##*:}"
        done
    done
}

shoot_watch() {
    local app="$DERIVED/Build/Products/Debug-iphonesimulator/DaGym.app/Watch/DaGymWatch.app"
    boot "$WATCH_UDID"
    xcrun simctl install "$WATCH_UDID" "$app"
    clean_status_bar "$WATCH_UDID"
    # watchOS is always dark; one set.
    local dir="$OUT/watch"; mkdir -p "$dir"
    echo "== Watch → $dir"
    for shot in "${WATCH_SHOTS[@]}"; do
        capture "$WATCH_UDID" "$WATCH_BUNDLE" "$dir/${shot%%:*}.png" \
            -dgWatchSample -dgWatchScreen "${shot##*:}"
    done
}

mkdir -p "$OUT"
[[ $SKIP_BUILD -eq 1 ]] || build
[[ "$ONLY" == "watch" ]] || shoot_iphone
[[ "$ONLY" == "iphone" ]] || shoot_watch
echo "== Done. Pixel sizes:"
for f in "$OUT/iphone/${APPEARANCES[1]}/01-workout.png" "$OUT/watch/01-home.png"; do
    [[ -f "$f" ]] || continue
    printf '   %s: %s\n' "$f" "$(sips -g pixelWidth -g pixelHeight "$f" | awk '/pixel/ {printf "%s ", $2}')"
done

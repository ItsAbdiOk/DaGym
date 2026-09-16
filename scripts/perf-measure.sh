#!/bin/sh
# Cold/warm launch timing, idle RSS, rest-timer CPU, Library RSS, and .app size for DaGym.
# Installs a fresh Debug build on the resolved simulator, seeds onboarding so no permission
# sheet interferes, and measures without touching anything the user actually cares about.
#
#   scripts/perf-measure.sh [--label <name>] [--derived-data <path>] [--skip-build] [--out <json>]
#
#   --label <name>         tag stored in the JSON and used as the default output filename
#                           (default: today's date, e.g. 2026-09-16)
#   --derived-data <path>  DerivedData dir for the build (default: build/DerivedData-perf,
#                           gitignored — see .gitignore's `build/` line)
#   --skip-build            reuse an existing build at
#                           <derived-data>/Build/Products/Debug-iphonesimulator/DaGym.app
#                           instead of building it here
#   --out <json>            where to write the result (default: build/perf/<label>.json)
#
# Simulator resolution matches scripts/verify.sh (scripts/lib/sim.sh's newest-iPhone-Pro pick,
# honouring the DAGYM_IPHONE_SIM override for when another job already owns that simulator).
# Only ever installs/uninstalls on the resolved simulator — never touches one it did not pick,
# and never uninstalls anything else from it.
#
# Prints the JSON to stdout as well as writing it to --out.
set -eu
cd "$(dirname "$0")/.."
. scripts/lib/sim.sh

LABEL=$(date +%Y-%m-%d)
DERIVED_DATA="build/DerivedData-perf"
SKIP_BUILD=0
OUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --label) LABEL="$2"; shift ;;
        --derived-data) DERIVED_DATA="$2"; shift ;;
        --skip-build) SKIP_BUILD=1 ;;
        --out) OUT="$2"; shift ;;
        *)
            echo "usage: scripts/perf-measure.sh [--label <name>] [--derived-data <path>] [--skip-build] [--out <json>]" >&2
            exit 2
            ;;
    esac
    shift
done

[ -n "$OUT" ] || OUT="build/perf/$LABEL.json"
mkdir -p "$(dirname "$OUT")"

# The app target's PRODUCT_BUNDLE_IDENTIFIER is the first one in project.yml — the tests,
# UI-tests and widgets targets each declare their own further down the file.
BUNDLE=$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER:' project.yml | sed 's/^[^:]*: *//' | tr -d ' "')
[ -n "$BUNDLE" ] || BUNDLE=dev.abdirahmanmohamed.dagym  # project.yml layout changed; keep going

SIM_INFO=$(sim_resolve_iphone_pro) || { echo "no iPhone …Pro simulator available" >&2; exit 1; }
SIM=$(sim_name "$SIM_INFO")
UDID=$(sim_udid "$SIM_INFO")
echo "  $SIM ($UDID)"

TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dagym-perf.XXXXXX")
cleanup() {
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT INT TERM

if [ "$SKIP_BUILD" = 0 ]; then
    echo "▶ build (Debug)"
    xcodebuild build -project DaGym.xcodeproj -scheme DaGym -configuration Debug \
        -destination "id=$UDID" -derivedDataPath "$DERIVED_DATA" -quiet 2>&1 | grep -E "error:" || true
fi
APP=$(find "$DERIVED_DATA/Build/Products/Debug-iphonesimulator" -maxdepth 1 -name "DaGym.app" 2>/dev/null | head -1)
[ -n "$APP" ] && [ -d "$APP" ] || {
    echo "no built app at $DERIVED_DATA/Build/Products/Debug-iphonesimulator/DaGym.app (build it, or drop --skip-build)" >&2
    exit 1
}
APP_SIZE_KB=$(du -sk "$APP" | cut -f1)

xcrun simctl bootstatus "$UDID" -b >/dev/null
xcrun simctl uninstall "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
xcrun simctl install "$UDID" "$APP"
xcrun simctl spawn "$UDID" defaults write "$BUNDLE" hasCompletedOnboarding -bool YES

# Prints one cold launch's first-frame ms (DaGym/App/LaunchTiming.swift, `-dgLaunchTiming`);
# waits up to 60 s for Documents/launch-timing.json. Leaves the PID in $TMP_DIR/pid so callers
# right after it can sample RSS/CPU on the launch they just timed.
launch_ms() {
    xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
    sleep 1
    CONT=$(xcrun simctl get_app_container "$UDID" "$BUNDLE" data)
    rm -f "$CONT/Documents/launch-timing.json"
    PID=$(xcrun simctl launch "$UDID" "$BUNDLE" -dgLaunchTiming | awk -F': ' '{print $2}')
    echo "$PID" > "$TMP_DIR/pid"
    i=0
    while [ ! -f "$CONT/Documents/launch-timing.json" ] && [ "$i" -lt 120 ]; do
        sleep 0.5
        i=$((i + 1))
    done
    python3 -c "import json; print(round(json.load(open('$CONT/Documents/launch-timing.json'))['firstFrameMillis']))" 2>/dev/null || echo -1
}

echo "▶ fresh-install cold launch"
FRESH_MS=$(launch_ms)

sleep 6
PID=$(cat "$TMP_DIR/pid")
HOME_IDLE_RSS_KB=$(ps -o rss= -p "$PID" | tr -d ' ')

echo "▶ warm cold launches (x3)"
W1=$(launch_ms); W2=$(launch_ms); W3=$(launch_ms)
WARM_MEDIAN=$(printf '%s\n%s\n%s\n' "$W1" "$W2" "$W3" | sort -n | sed -n 2p)

echo "▶ rest-timer screen CPU"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
sleep 1
PID=$(xcrun simctl launch "$UDID" "$BUNDLE" -dgScreenshots -dgScreenshotScreen rest | awk -F': ' '{print $2}')
echo "$PID" > "$TMP_DIR/pid"
sleep 5
REST_CPU=$(top -l 7 -s 2 -pid "$PID" -stats cpu | tail -6 | awk '{s += $1} END {printf "%.1f", s / NR}')

echo "▶ library screen RSS"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
sleep 1
PID=$(xcrun simctl launch "$UDID" "$BUNDLE" -dgScreenshots -dgScreenshotScreen library | awk -F': ' '{print $2}')
echo "$PID" > "$TMP_DIR/pid"
sleep 6
LIBRARY_RSS_KB=$(ps -o rss= -p "$PID" | tr -d ' ')

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true

cat > "$OUT" <<JSON
{
  "label": "$LABEL",
  "recordedAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "simulator": "$SIM",
  "appSizeKB": $APP_SIZE_KB,
  "freshInstallLaunchMs": $FRESH_MS,
  "warmLaunchMs": [$W1, $W2, $W3],
  "warmLaunchMedianMs": $WARM_MEDIAN,
  "homeIdleRSSKB": $HOME_IDLE_RSS_KB,
  "restScreenCPUAvg": $REST_CPU,
  "libraryRSSKB": $LIBRARY_RSS_KB
}
JSON
cat "$OUT"

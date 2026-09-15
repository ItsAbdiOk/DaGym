#!/bin/sh
# Deploy DaGym's CloudKit schema from a Debug build in one command.
#
#   scripts/cloudkit-schema.sh                 dry run: init Development, show the diff, exit 0
#   scripts/cloudkit-schema.sh --deploy        …then hand off to the console and verify
#
# What it does:
#   1. builds Debug for the simulator, launches with -dgInitCloudKitSchema
#      (`CloudKitSchemaInitializer`), which pushes every synced record type
#      and field into the Development schema and writes Documents/schema-init.json
#   2. exports Development and Production with `xcrun cktool`
#   3. prints the diff (added/removed record types and fields)
#   4. with --deploy, waits for the console's Deploy Schema Changes and re-checks
#
# Options:
#   --deploy           console hand-off + verification (default is a dry run)
#   --allow-removals   proceed even when the diff removes a type or field
#                      (a removed field breaks sync for every older build)
#   --skip-init        skip the build/launch; only export, diff, import
#   --device <udid>    simulator to use (default: iPhone 16 Pro, iOS 27)
#   --phone            use the paired iPhone via devicectl instead of a simulator
#
# Exit codes:
#   0  success (dry run shown, or deploy verified)
#   1  precondition failed (no cktool, no management token, bad option)
#   2  schema initialisation on the device failed (see the printed error;
#      "no iCloud account" means: sign the simulator into iCloud once in Settings)
#   3  diff removes something and --allow-removals was not given
#   4  import ran but Production still differs from Development
#
# First-time setup (never paste the token into a shell history):
#   xcrun cktool save-token --type management
#   (token from https://icloud.developer.apple.com/dashboard → Manage Tokens)
set -eu
cd "$(dirname "$0")/.."

TEAM_ID=5AF2LBU5A3
CONTAINER_ID=iCloud.dev.abdirahmanmohamed.dagym
BUNDLE_ID=dev.abdirahmanmohamed.dagym
DEFAULT_DEVICE=4109ECC0-2528-4A1B-A75D-2023BE51DF41   # iPhone 16 Pro (iOS 27)
DERIVED=/tmp/dagym-schema-build
SCRATCH=scratch/cloudkit
MARKER=Documents/schema-init.json
POLL_SECONDS=180

DEPLOY=0
ALLOW_REMOVALS=0
SKIP_INIT=0
PHONE=0
DEVICE="$DEFAULT_DEVICE"

usage() { sed -n '2,32p' "$0" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
    case "$1" in
        --deploy) DEPLOY=1 ;;
        --allow-removals) ALLOW_REMOVALS=1 ;;
        --skip-init) SKIP_INIT=1 ;;
        --phone) PHONE=1 ;;
        --device) shift; [ $# -gt 0 ] || { echo "error: --device needs a udid" >&2; exit 1; }; DEVICE="$1" ;;
        -h|--help) usage; exit 0 ;;
        *) echo "error: unknown option $1" >&2; usage >&2; exit 1 ;;
    esac
    shift
done

# --- 1. preconditions --------------------------------------------------------
if ! xcrun --find cktool >/dev/null 2>&1; then
    echo "error: xcrun cktool not found — install Xcode 13 or newer." >&2
    exit 1
fi
# `get-teams` is the cheapest authorised call; its output is never printed (it is
# harmless, but nothing that could carry a token should reach a log).
if ! xcrun cktool get-teams >/dev/null 2>&1; then
    cat >&2 <<'MSG'
error: no CloudKit management token is saved for cktool.

Create one at https://icloud.developer.apple.com/dashboard (Manage Tokens →
Management Token), then save it to the keychain with the interactive prompt —
do NOT pass it on the command line:

    xcrun cktool save-token --type management

and run this script again.
MSG
    exit 1
fi

mkdir -p "$SCRATCH"

# --- 2. initialise the Development schema from the app ------------------------
init_schema() {
    echo "▶ building Debug (DerivedData: $DERIVED)"
    if [ "$PHONE" = 1 ]; then
        DESTINATION="platform=iOS,id=$DEVICE"
    else
        DESTINATION="platform=iOS Simulator,id=$DEVICE"
    fi
    xcodebuild -project DaGym.xcodeproj -scheme DaGym -configuration Debug \
        -destination "$DESTINATION" -derivedDataPath "$DERIVED" \
        -allowProvisioningUpdates -quiet build
    APP=$(find "$DERIVED/Build/Products" -maxdepth 3 -name "DaGym.app" | head -1)
    [ -n "$APP" ] || { echo "error: build succeeded but no DaGym.app was produced." >&2; exit 1; }

    if [ "$PHONE" = 1 ]; then
        echo "▶ installing on phone $DEVICE"
        xcrun devicectl device install app --device "$DEVICE" "$APP" >/dev/null
        xcrun devicectl device process launch --device "$DEVICE" --terminate-existing \
            "$BUNDLE_ID" -dgInitCloudKitSchema >/dev/null
    else
        echo "▶ booting simulator $DEVICE"
        xcrun simctl boot "$DEVICE" >/dev/null 2>&1 || true
        xcrun simctl bootstatus "$DEVICE" -b >/dev/null 2>&1 || true
        xcrun simctl terminate "$DEVICE" "$BUNDLE_ID" >/dev/null 2>&1 || true
        # A stale marker from a previous run must never be mistaken for this run's.
        CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)
        [ -z "$CONTAINER" ] || rm -f "$CONTAINER/$MARKER"
        echo "▶ installing and launching with -dgInitCloudKitSchema"
        xcrun simctl install "$DEVICE" "$APP"
        xcrun simctl launch "$DEVICE" "$BUNDLE_ID" -dgInitCloudKitSchema >/dev/null
    fi

    echo "▶ waiting for $MARKER (up to ${POLL_SECONDS}s)"
    RESULT="$SCRATCH/schema-init.json"
    rm -f "$RESULT"
    ELAPSED=0
    while [ "$ELAPSED" -lt "$POLL_SECONDS" ]; do
        if [ "$PHONE" = 1 ]; then
            xcrun devicectl device copy from --device "$DEVICE" --domain-type appDataContainer \
                --domain-identifier "$BUNDLE_ID" --source "$MARKER" --destination "$RESULT" \
                >/dev/null 2>&1 || true
        else
            CONTAINER=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE_ID" data 2>/dev/null || true)
            [ -n "$CONTAINER" ] && [ -f "$CONTAINER/$MARKER" ] && cp "$CONTAINER/$MARKER" "$RESULT" || true
        fi
        [ -f "$RESULT" ] && break
        sleep 3
        ELAPSED=$((ELAPSED + 3))
    done
    [ -f "$RESULT" ] || {
        echo "error: the app never wrote $MARKER within ${POLL_SECONDS}s." >&2
        echo "Is it stuck on a system prompt? Check the device screen." >&2
        exit 2
    }

    INIT_OK=$(python3 -c 'import json,sys; print("1" if json.load(open(sys.argv[1])).get("ok") else "0")' "$RESULT")
    INIT_ERROR=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("error") or "")' "$RESULT")
    if [ "$INIT_OK" != 1 ]; then
        echo "error: schema initialisation failed on the device: $INIT_ERROR" >&2
        case "$INIT_ERROR" in
            *"no iCloud account"*)
                echo "Sign the simulator/phone into iCloud once (Settings → Sign in) and re-run." >&2 ;;
        esac
        exit 2
    fi
    RECORD_TYPES=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("recordTypes", 0))' "$RESULT")
    echo "✓ Development schema initialised ($RECORD_TYPES record types)"
}
[ "$SKIP_INIT" = 1 ] || init_schema

# --- 3. export both environments ---------------------------------------------
export_schema() {
    xcrun cktool export-schema --team-id "$TEAM_ID" --container-id "$CONTAINER_ID" \
        --environment "$1" --output-file "$2" >/dev/null
}
DEV="$SCRATCH/development.ckdb"
PROD_BEFORE="$SCRATCH/production-before.ckdb"
echo "▶ exporting Development → $DEV"
export_schema development "$DEV"
echo "▶ exporting Production → $PROD_BEFORE"
export_schema production "$PROD_BEFORE"

# --- 4. diff -----------------------------------------------------------------
# Summarise from the .ckdb text: `RECORD TYPE Name (` opens a type, indented
# `field TYPE` lines belong to the current type. Prints added/removed lines and
# exits 1 when anything is removed.
summarise() {
    python3 - "$1" "$2" <<'PY'
import re, sys

def parse(path):
    types, current = {}, None
    for raw in open(path):
        line = raw.rstrip()
        m = re.match(r'\s*RECORD TYPE\s+(\S+)', line)
        if m:
            current = m.group(1); types[current] = set(); continue
        m = re.match(r'\s+(\w+)\s+\S+', line)
        if m and current and not line.strip().startswith(('GRANT', ')', '(')):
            types[current].add(m.group(1))
    return types

before, after = parse(sys.argv[1]), parse(sys.argv[2])
added = removed = 0
for name in sorted(set(before) | set(after)):
    if name not in before:
        print(f"  + record type {name} ({len(after[name])} fields)"); added += 1; continue
    if name not in after:
        print(f"  - record type {name}"); removed += 1; continue
    for f in sorted(after[name] - before[name]):
        print(f"  + {name}.{f}"); added += 1
    for f in sorted(before[name] - after[name]):
        print(f"  - {name}.{f}"); removed += 1
if not added and not removed:
    print("  (no changes)")
print(f"  {added} added, {removed} removed")
sys.exit(1 if removed else 0)
PY
}

echo "▶ diff Production → Development"
if diff -u "$PROD_BEFORE" "$DEV" > "$SCRATCH/schema.diff"; then
    echo "  Production already matches Development — nothing to deploy."
    exit 0
fi
cat "$SCRATCH/schema.diff"
echo
echo "Summary:"
if ! summarise "$PROD_BEFORE" "$DEV"; then
    if [ "$ALLOW_REMOVALS" != 1 ]; then
        echo "error: the diff REMOVES a record type or field. Older builds still write it and" >&2
        echo "their sync would break. Re-run with --allow-removals if that is really intended." >&2
        exit 3
    fi
    echo "  (removals allowed by --allow-removals)"
fi

# --- 5. deploy ---------------------------------------------------------------
# cktool can import into Development only: Production answers "endpoint not applicable in
# the environment 'production'" (Apple keeps that behind the console's "Deploy Schema
# Changes" button). So --deploy verifies the state and hands over the one remaining click.
if [ "$DEPLOY" != 1 ]; then
    echo
    echo "Dry run. Development is initialised; the diff above is what the console will deploy."
    echo "Re-run with --deploy for the console hand-off and post-deploy verification."
    exit 0
fi

echo
echo "▶ deploy: open the CloudKit Console → $CONTAINER_ID → Development → Schema →"
echo "  \"Deploy Schema Changes…\" — the diff it shows must match the summary above"
echo "  (see the counts above). Confirm it there, then press Return here to verify."
# shellcheck disable=SC2034
read -r _confirm
PROD_AFTER="$SCRATCH/production-after.ckdb"
export_schema production "$PROD_AFTER"
if diff -u "$DEV" "$PROD_AFTER" > "$SCRATCH/schema-after.diff"; then
    echo "✓ Production now matches Development."
else
    echo "error: Production still differs from Development:" >&2
    cat "$SCRATCH/schema-after.diff" >&2
    exit 4
fi

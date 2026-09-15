#!/bin/sh
# One command that proves the app is healthy: lint, GymCore unit tests, app database tests,
# the simulator UI smoke test, and the watch test bundle. Used by the pre-push hook and
# before every device install.
#
#   scripts/verify.sh [--coverage] [--skip-lint]
#
#   --coverage   gather code coverage for the xcodebuild runs (off by default: it instruments
#                every target and slows both the build and the tests, and nothing reads the
#                report on a normal push — open the .xcresult in Xcode when you want it)
#   --skip-lint  the pre-push hook lints (and checks tool versions) before calling this, so it
#                passes this to avoid running SwiftLint twice per push
set -eu
cd "$(dirname "$0")/.."
. scripts/lib/sim.sh

COVERAGE=NO
LINT=1
for arg in "$@"; do
    case "$arg" in
        --coverage) COVERAGE=YES ;;
        --skip-lint) LINT=0 ;;
        *) echo "usage: scripts/verify.sh [--coverage] [--skip-lint]" >&2; exit 2 ;;
    esac
done

# Per-run log directory: several gates can run at once on this machine (parallel sessions),
# and fixed /tmp paths made one run's failure grep print another run's errors.
LOG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/dagym-verify.XXXXXX")
echo "logs: $LOG_DIR"

if [ "$LINT" = 1 ]; then
    echo "▶ lint"
    swiftlint lint --strict --quiet
fi

# GymCore is only compiled here (it is no longer in the DaGym scheme's test action, so the
# xcodebuild below links the already-built product instead of compiling it a second time).
# The app builds with SWIFT_TREAT_WARNINGS_AS_ERRORS; -warnings-as-errors keeps a GymCore
# warning failing in this 30 s step rather than minutes later in the xcodebuild one.
echo "▶ GymCore tests"
(cd GymCore && swift test --quiet -Xswiftc -warnings-as-errors)

# The single failure grep — the hook relays this script's output verbatim rather than keeping
# its own copy of the pattern.
FAIL_PATTERN="✘|error:|Expectation failed|Test Case .* failed|failed \(|hung"

# $1 = label, $2 = scheme, $3 = destination udid, $4 = log name, $5… = -only-testing:… flags
run_xctest() {
    label=$1; scheme=$2; udid=$3; log="$LOG_DIR/$4.log"; shift 4
    echo "▶ $label ($scheme on $udid)"
    xcodebuild test -project DaGym.xcodeproj -scheme "$scheme" \
        -destination "id=$udid" -enableCodeCoverage "$COVERAGE" "$@" > "$log" 2>&1 \
        || { grep -E "$FAIL_PATTERN" "$log" | head -30 >&2; echo "log: $log" >&2; exit 1; }
    grep -E "Test run with|Executed [1-9]" "$log" | tail -3
    # A failed grep inside the pipeline above doesn't trip `set -e`, and "Executed 0 tests" (a
    # renamed target, a broken -only-testing filter, a bundle that failed to load) passes it
    # silently — this is the actual proof step; a green run with no tests proves nothing.
    grep -qE "Executed [1-9][0-9]* tests?|Test run with [1-9]" "$log" \
        || { echo "$label: no tests were actually executed (log: $log)" >&2; exit 1; }
}

SIM_INFO=$(sim_resolve_iphone_pro) || { echo "no iPhone …Pro simulator available" >&2; exit 1; }
SIM=$(sim_name "$SIM_INFO")
UDID=$(sim_udid "$SIM_INFO")

# A hosted unit-test run that follows a UI-test run on the same simulator reliably hangs
# "before establishing connection"; a fresh boot avoids it (~15 s). Same UDID resolved above, so
# the reboot and the test run can never target different devices.
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
# The onboarding walkthrough drives the real Health permission sheet and notification alert;
# once granted they never show again on that simulator, so a second run takes a different
# path (and waits 8 s for a sheet that never comes). Reset so every run is the first run.
xcrun simctl privacy "$UDID" reset all dev.abdirahmanmohamed.dagym >/dev/null 2>&1 || true
# Both iOS bundles in ONE invocation: each xcodebuild re-checks the whole build graph and
# re-installs the host, so a second invocation cost ~30–60 s for nothing.
echo "  $SIM"
run_xctest "app + database tests, UI smoke test" DaGym "$UDID" ios \
    -only-testing:DaGymTests -only-testing:DaGymUITests

# Watch bundle (prescription parity, wrist-finish persistence, haptic/crown tables). The watch
# app already *built* above (embedded in DaGym), so this only catches behaviour breaks.
WATCH_INFO=$(sim_resolve_watch) || { echo "no Apple Watch simulator available" >&2; exit 1; }
echo "  $(sim_name "$WATCH_INFO")"
run_xctest "watch tests" DaGymWatch "$(sim_udid "$WATCH_INFO")" watch -only-testing:DaGymWatchTests
echo "✓ all green"

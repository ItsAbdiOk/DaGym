#!/bin/sh
# One command that proves the app is healthy: lint, GymCore unit tests, app
# database tests, and the simulator UI smoke test. Used by the pre-push hook
# and before every device install.
set -eu
cd "$(dirname "$0")/.."

echo "▶ lint"
swiftlint lint --strict --quiet

echo "▶ GymCore tests"
(cd GymCore && swift test --quiet)

# Resolve name AND UDID together, from one JSON listing, on the newest runtime that has an
# "iPhone … Pro" device — two separate greps (one for the name, one for the UDID) can disagree
# (T5): a "Pro Max"-only machine loses the name match entirely, and a machine with the same
# device name under two runtimes can boot one while `xcodebuild` resolves to the other.
SIM_INFO=$(xcrun simctl list devices available -j | python3 -c '
import json, re, sys
data = json.load(sys.stdin)

def runtime_version(key):
    m = re.search(r"iOS-(\d+)-(\d+)", key)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)

def model_number(name):
    m = re.search(r"iPhone (\d+) Pro", name)
    return int(m.group(1)) if m else -1

best = None
for runtime, devices in data["devices"].items():
    for device in devices:
        name = device.get("name", "")
        if name.startswith("iPhone") and "Pro" in name and device.get("isAvailable", True):
            key = (runtime_version(runtime), model_number(name))
            if best is None or key > best[0]:
                best = (key, name, device["udid"])
if best:
    print(best[1])
    print(best[2])
')
SIM=$(printf "%s\n" "$SIM_INFO" | sed -n 1p)
UDID=$(printf "%s\n" "$SIM_INFO" | sed -n 2p)
[ -n "$UDID" ] || { echo "no iPhone …Pro simulator available" >&2; exit 1; }

run_xctest() {
    # $1 = label, $2 = -only-testing target. Separate invocations: a long UI run can leave the
    # simulator in a state where the next test host hangs "before establishing connection".
    echo "▶ $1 on $SIM ($UDID)"
    xcodebuild test -project DaGym.xcodeproj -scheme DaGym \
        -destination "id=$UDID" \
        -only-testing:"$2" > "/tmp/dagym-verify-$2.log" 2>&1 \
        || { grep -E "✘|error:|Expectation failed|Test Case .* failed|failed \(|hung" "/tmp/dagym-verify-$2.log" | head -30 >&2; echo "log: /tmp/dagym-verify-$2.log" >&2; exit 1; }
    grep -E "Test run with|Executed [1-9]" "/tmp/dagym-verify-$2.log" | tail -2
    # A failed grep inside the pipeline above doesn't trip `set -e`, and "Executed 0 tests" (a
    # renamed target, a broken -only-testing filter, a bundle that failed to load) passes it
    # silently — this is the actual proof step; a green run with no tests proves nothing.
    grep -qE "Executed [1-9][0-9]* tests?|Test run with [1-9]" "/tmp/dagym-verify-$2.log" \
        || { echo "$1: no tests were actually executed (log: /tmp/dagym-verify-$2.log)" >&2; exit 1; }
}
# A hosted unit-test run that follows a UI-test run on the same simulator reliably hangs
# "before establishing connection"; a fresh boot avoids it (~15 s). Same UDID resolved above, so
# the reboot and the test run can never target different devices.
xcrun simctl shutdown "$UDID" >/dev/null 2>&1 || true
xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || true
run_xctest "app + database tests" DaGymTests
run_xctest "UI smoke test" DaGymUITests
echo "✓ all green"

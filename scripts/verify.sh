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

SIM=$(xcrun simctl list devices available | grep -oE 'iPhone [0-9]+ Pro' | sort -V | tail -1)
[ -n "$SIM" ] || { echo "no iPhone simulator available" >&2; exit 1; }

run_xctest() {
    # $1 = label, $2 = -only-testing target. Separate invocations: a long UI run can leave the
    # simulator in a state where the next test host hangs "before establishing connection".
    echo "▶ $1 on $SIM"
    xcodebuild test -project DaGym.xcodeproj -scheme DaGym \
        -destination "platform=iOS Simulator,name=$SIM" \
        -only-testing:"$2" > "/tmp/dagym-verify-$2.log" 2>&1 \
        || { grep -E "✘|error:|Expectation failed|Test Case .* failed|failed \(|hung" "/tmp/dagym-verify-$2.log" | head -30 >&2; echo "log: /tmp/dagym-verify-$2.log" >&2; exit 1; }
    grep -E "Test run with|Executed [1-9]" "/tmp/dagym-verify-$2.log" | tail -2
}
run_xctest "app + database tests" DaGymTests
run_xctest "UI smoke test" DaGymUITests
echo "✓ all green"

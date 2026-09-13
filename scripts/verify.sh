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

echo "▶ app tests + UI smoke test on $SIM"
xcodebuild test -project DaGym.xcodeproj -scheme DaGym \
    -destination "platform=iOS Simulator,name=$SIM" \
    -only-testing:DaGymTests -only-testing:DaGymUITests \
    > /tmp/dagym-verify.log 2>&1 \
    || { grep -E "✘|error:|Expectation failed|Test Case .* failed|failed \(" /tmp/dagym-verify.log | head -30 >&2; echo "log: /tmp/dagym-verify.log" >&2; exit 1; }
grep -E "Test run with|Executed" /tmp/dagym-verify.log | tail -4
echo "✓ all green"

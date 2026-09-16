#!/bin/sh
# Compares two scripts/perf-measure.sh outputs and prints a delta table.
#
#   scripts/perf-compare.sh <baseline.json> <after.json>
#
# Exits 1 if warmLaunchMedianMs regresses more than WARM_LAUNCH_REGRESSION_PCT, or
# homeIdleRSSKB regresses more than HOME_RSS_REGRESSION_PCT (both below — tune here, not by
# passing flags).
set -eu

WARM_LAUNCH_REGRESSION_PCT=15
HOME_RSS_REGRESSION_PCT=10

[ $# -eq 2 ] || { echo "usage: scripts/perf-compare.sh <baseline.json> <after.json>" >&2; exit 2; }
BASELINE="$1"
AFTER="$2"
[ -f "$BASELINE" ] || { echo "no such file: $BASELINE" >&2; exit 2; }
[ -f "$AFTER" ] || { echo "no such file: $AFTER" >&2; exit 2; }

export WARM_LAUNCH_REGRESSION_PCT HOME_RSS_REGRESSION_PCT
python3 - "$BASELINE" "$AFTER" <<'PY'
import json
import os
import sys

baseline = json.load(open(sys.argv[1]))
after = json.load(open(sys.argv[2]))
warm_pct = float(os.environ["WARM_LAUNCH_REGRESSION_PCT"])
rss_pct = float(os.environ["HOME_RSS_REGRESSION_PCT"])

# (json key, printed label, unit)
METRICS = [
    ("freshInstallLaunchMs", "fresh install launch", "ms"),
    ("warmLaunchMedianMs", "warm launch median", "ms"),
    ("homeIdleRSSKB", "home idle RSS", "KB"),
    ("restScreenCPUAvg", "rest-timer CPU", "%"),
    ("libraryRSSKB", "library RSS", "KB"),
    ("appSizeKB", "app size", "KB"),
]

print("{:<22}{:>12}{:>12}{:>12}{:>9}".format("metric", "baseline", "after", "delta", "%"))
regressions = []
for key, label, unit in METRICS:
    if key not in baseline or key not in after:
        continue
    b, a = baseline[key], after[key]
    delta = a - b
    pct = (delta / b * 100) if b else 0.0
    print("{:<22}{:>9} {:<3}{:>9} {:<3}{:>+9.1f}{:>+8.1f}%".format(label, b, unit, a, unit, delta, pct))
    if key == "warmLaunchMedianMs" and pct > warm_pct:
        regressions.append("warm launch median regressed {:.1f}% (> {:.0f}%)".format(pct, warm_pct))
    if key == "homeIdleRSSKB" and pct > rss_pct:
        regressions.append("home idle RSS regressed {:.1f}% (> {:.0f}%)".format(pct, rss_pct))

if regressions:
    print()
    for r in regressions:
        print("REGRESSION: " + r)
    sys.exit(1)
PY

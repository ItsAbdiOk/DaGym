#!/bin/sh
# Simulator resolution shared by verify.sh, cloudkit-schema.sh and screenshots.sh. Sourced,
# not executed; POSIX sh so both the sh scripts and the zsh one can use it.
#
# Every function resolves name AND UDID together from ONE `simctl list -j` call, on a single
# runtime — two separate greps (one for the name, one for the UDID) can disagree (T5): a
# "Pro Max"-only machine loses the name match entirely, and a machine with the same device
# name under two runtimes can boot one while `xcodebuild` resolves to the other. Hard-coded
# UDIDs are worse: they die on the next `simctl delete unavailable`, Xcode upgrade, or Mac.
#
#   sim_resolve_iphone_pro            newest iOS runtime, highest-numbered "iPhone N Pro"
#   sim_resolve_by_name  <name> [platform]   exact device name, newest runtime of that platform
#                                     (platform: iOS (default) | watchOS)
#   sim_resolve_watch    [name]       exact name if given, else newest watchOS runtime,
#                                     preferring the 44 mm SE ("Apple Watch SE … (44mm)")
#
# Each prints two lines — name, then UDID — and returns 1 (printing nothing) when no device
# matches. Read them with `sim_name`/`sim_udid`:
#
#   INFO=$(sim_resolve_iphone_pro) || { echo "no iPhone …Pro simulator" >&2; exit 1; }
#   SIM=$(sim_name "$INFO"); UDID=$(sim_udid "$INFO")

sim_name() { printf "%s\n" "$1" | sed -n 1p; }
sim_udid() { printf "%s\n" "$1" | sed -n 2p; }

# $1 = mode (pro | name | watch), $2 = name (name/watch modes), $3 = platform (name mode)
_sim_resolve() {
    xcrun simctl list devices available -j | python3 -c '
import json, re, sys

mode, want_name, platform = sys.argv[1], sys.argv[2], sys.argv[3]
data = json.load(sys.stdin)

def runtime_version(key, plat):
    m = re.search(plat + r"-(\d+)-(\d+)", key)
    return (int(m.group(1)), int(m.group(2))) if m else None

def pro_model(name):
    # "iPhone 17 Pro", "iPhone 17 Pro Max" and custom names like "iPhone 17 Pro iOS27" all count.
    m = re.search(r"iPhone (\d+) Pro", name)
    return int(m.group(1)) if m else -1

best = None
for runtime, devices in data["devices"].items():
    version = runtime_version(runtime, platform)
    if version is None:
        continue
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device.get("name", "")
        if mode == "pro":
            if not name.startswith("iPhone") or pro_model(name) < 0:
                continue
            key = (version, pro_model(name))
        elif mode == "name":
            if name != want_name:
                continue
            key = (version,)
        else:  # watch
            if want_name:
                if name != want_name:
                    continue
                key = (version,)
            else:
                if not name.startswith("Apple Watch"):
                    continue
                # Prefer the 44 mm SE (the screenshot/spec device), then any 44 mm, then any watch.
                key = (version, "SE" in name and "44mm" in name, "44mm" in name)
        if best is None or key > best[0]:
            best = (key, name, device["udid"])
if best is None:
    sys.exit(1)
print(best[1])
print(best[2])
' "$1" "${2:-}" "${3:-iOS}"
}

# DAGYM_IPHONE_SIM=<exact device name> overrides the automatic pick — for when another job on
# the machine already owns the newest Pro simulator and two test hosts would collide on it.
sim_resolve_iphone_pro() {
    if [ -n "${DAGYM_IPHONE_SIM:-}" ]; then
        _sim_resolve name "$DAGYM_IPHONE_SIM" iOS
    else
        _sim_resolve pro "" iOS
    fi
}
sim_resolve_by_name() { _sim_resolve name "$1" "${2:-iOS}"; }
sim_resolve_watch() { _sim_resolve watch "${1:-}" watchOS; }

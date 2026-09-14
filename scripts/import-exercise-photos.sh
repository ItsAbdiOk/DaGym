#!/bin/bash
# Regenerates DaGym/Resources/ExercisePhotos/*.heic and DaGym/Data/ExercisePhotoCatalog.swift.
#
# Usage:
#   scripts/import-exercise-photos.sh <path-to-free-exercise-db>
#
# <path-to-free-exercise-db> is the root of a clone of yuhonas/free-exercise-db: it must contain
# exercises/<ID>/0.jpg (start position) and exercises/<ID>/1.jpg (end position). That repository
# is released under the Unlicense (public domain) — no attribution is legally required, but we
# credit it anyway in DaGym/Resources/Acknowledgements.md. Only the photographs are read; none of
# that project's code is used, and the source tree is never modified.
#
# Our seed IDs (DaGym/Resources/Seed/exercises.json) *are* free-exercise-db directory names, so
# the match is exact — no fuzzy matching. Everything that matches gets two photos; everything
# else keeps whatever it has today (illustrated vector art, or the SF Symbol fallback).
#
# The photos ship as plain bundle resource files inside a *folder reference*
# (DaGym/Resources/ExercisePhotos), loaded by path at runtime — deliberately NOT an .xcassets
# catalogue: Xcode rasterises catalogue members at multiple scales and Assets.car explodes.
#
# Re-runnable and idempotent: an existing .heic that is newer than its source .jpg is left alone,
# and .heic files whose exercise is no longer matched are pruned.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <path-to-free-exercise-db>" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source_root="$(cd "$1" && pwd)"

if [[ ! -d "$source_root/exercises" ]]; then
    echo "error: $source_root has no exercises/ directory — is that a free-exercise-db clone?" >&2
    exit 1
fi

seed_json="$repo_root/DaGym/Resources/Seed/exercises.json"
out_dir="$repo_root/DaGym/Resources/ExercisePhotos"
catalog_swift="$repo_root/DaGym/Data/ExercisePhotoCatalog.swift"

# Longest edge in points after downscaling, and the HEIC quality. 800/50 measures at ~22 KB per
# image (down from ~50 KB of source JPEG) with no visible loss at the 240 pt hero size.
max_edge=800
quality=50

mkdir -p "$out_dir"

work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

# 1. Exact-match our seed IDs against free-exercise-db directories that have both frames.
#    Matching is against the listed directory *names*, not against os.path.isfile: macOS's
#    case-insensitive filesystem would otherwise quietly match two IDs that differ in case
#    (Mountain_climbers vs Mountain_Climbers), and produce a result the case-sensitive iOS
#    bundle would not reproduce. Those near-misses are reported, not silently included.
python3 - "$seed_json" "$source_root" > "$work_dir/matched.txt" <<'PY'
import json, os, sys

seed_path, source_root = sys.argv[1], sys.argv[2]
exercises_root = os.path.join(source_root, "exercises")
names = set(os.listdir(exercises_root))
by_lowercase = {name.lower(): name for name in names}

seen, matched, case_only = set(), [], []
for exercise in json.load(open(seed_path))["exercises"]:
    seed_id = exercise["id"]
    if seed_id in seen:
        continue
    seen.add(seed_id)
    if seed_id not in names:
        if seed_id.lower() in by_lowercase:
            case_only.append((seed_id, by_lowercase[seed_id.lower()]))
        continue
    directory = os.path.join(exercises_root, seed_id)
    if all(os.path.isfile(os.path.join(directory, f"{frame}.jpg")) for frame in (0, 1)):
        matched.append(seed_id)
matched.sort()
print("\n".join(matched))
print(f"seed exercises: {len(seen)}, matched with both frames: {len(matched)}", file=sys.stderr)
for seed_id, directory in case_only:
    print(f"note: '{seed_id}' matches '{directory}' only case-insensitively — not imported", file=sys.stderr)
PY

matched_count=$(wc -l < "$work_dir/matched.txt" | tr -d ' ')
if [[ "$matched_count" -eq 0 ]]; then
    echo "error: no seed ID matched a free-exercise-db directory — wrong source path?" >&2
    exit 1
fi

# 2. Transcode. A NUL-separated (source, destination) stream — paths contain spaces, so newline
#    or tab separation is not safe — fed to four sips at a time. This is the only slow part:
#    roughly a minute of four-core CPU for a cold 1,382-image run, seconds for a re-run.
: > "$work_dir/jobs.bin"
job_count=0
while IFS= read -r seed_id; do
    for frame in 0 1; do
        src="$source_root/exercises/$seed_id/$frame.jpg"
        dst="$out_dir/$seed_id-$frame.heic"
        if [[ ! -s "$dst" || "$src" -nt "$dst" ]]; then
            printf '%s\0%s\0' "$src" "$dst" >> "$work_dir/jobs.bin"
            job_count=$((job_count + 1))
        fi
    done
done < "$work_dir/matched.txt"

echo "transcoding $job_count image(s) (already up to date: $((matched_count * 2 - job_count)))" >&2
if [[ "$job_count" -gt 0 ]]; then
    # shellcheck disable=SC2016
    xargs -0 -P 4 -n 2 sh -c \
        'sips -s format heic -s formatOptions '"$quality"' -Z '"$max_edge"' "$0" --out "$1" >/dev/null' \
        < "$work_dir/jobs.bin" \
        || { echo "error: sips failed" >&2; exit 1; }
fi

# 3. Prune photos whose exercise is no longer matched (a renamed or removed seed entry).
python3 - "$work_dir/matched.txt" "$out_dir" <<'PY'
import os, sys

matched = {line.strip() for line in open(sys.argv[1]) if line.strip()}
out_dir = sys.argv[2]
expected = {f"{seed_id}-{frame}.heic" for seed_id in matched for frame in (0, 1)}
removed = 0
for name in os.listdir(out_dir):
    if name.endswith(".heic") and name not in expected:
        os.remove(os.path.join(out_dir, name))
        removed += 1
if removed:
    print(f"pruned {removed} stale photo(s)", file=sys.stderr)
PY

# 4. Emit the Swift lookup. The IDs are packed several-per-line into one string literal so the
#    generated file stays inside SwiftLint's 400-line / 110-column limits and type-checks
#    instantly — a 691-entry collection literal would do neither.
python3 - "$work_dir/matched.txt" "$catalog_swift" <<'PY'
import os, sys

matched = [line.strip() for line in open(sys.argv[1]) if line.strip()]
out_path = sys.argv[2]

lines, current = [], ""
for seed_id in matched:
    candidate = seed_id if not current else f"{current}|{seed_id}"
    if len(candidate) > 96 and current:
        lines.append(current)
        current = seed_id
    else:
        current = candidate
if current:
    lines.append(current)
packed = "\n".join(f"    {line}" for line in lines)

header = f"""// Generated by scripts/import-exercise-photos.sh — do not edit by hand.
// Maps a seeded exercise's `seedID` to the two photographs (start and end position) bundled for
// it in DaGym/Resources/ExercisePhotos. Photographs: free-exercise-db (yuhonas/free-exercise-db),
// Unlicense / public domain — see DaGym/Resources/Acknowledgements.md. No attribution required.

import Foundation

/// Looks up the two-frame photographs for a seeded exercise, when we have any.
/// {len(matched)} of our seeded exercises match a free-exercise-db directory exactly; the rest
/// return `nil` and callers (`ExercisePhotoView`) fall back to the illustrated vector art or the
/// existing glyph.
///
/// Deliberately not an asset catalogue: these ship as plain files in a folder reference and are
/// loaded by path (see `ExercisePhotoStore`), because an .xcassets membership makes Xcode
/// rasterise every member at several scales and balloons `Assets.car`.
enum ExercisePhotoCatalog {{
    /// The bundle subdirectory the photos live in, relative to the app bundle root.
    static let bundleSubdirectory = "ExercisePhotos"

    /// Every seedID we ship photographs for.
    static let seedIDs: Set<String> = Set(
        packedSeedIDs.split(whereSeparator: {{ $0 == "|" || $0 == "\\n" }}).map(String.init)
    )

    /// The two photo resource names for `seedID` — start position first, end position second —
    /// or `nil` when this exercise has no photographs. Each name resolves to
    /// `<name>.heic` inside `bundleSubdirectory`.
    static func photoNames(for seedID: String) -> (start: String, end: String)? {{
        guard seedIDs.contains(seedID) else {{ return nil }}
        return ("\\(seedID)-0", "\\(seedID)-1")
    }}

    /// Existence check, mirroring `ExerciseArtCatalog.frames(for:)` so call sites read alike.
    static func hasPhotos(for seedID: String) -> Bool {{
        seedIDs.contains(seedID)
    }}

    /// seedIDs, `|`-separated and wrapped — one literal rather than a {len(matched)}-element
    /// collection literal, which would blow the file-length limit and the type-checker's budget.
    private static let packedSeedIDs = \"\"\"
{packed}
    \"\"\"
}}
"""

os.makedirs(os.path.dirname(out_path), exist_ok=True)
with open(out_path, "w") as handle:
    handle.write(header)
print(f"wrote {out_path} ({len(matched)} exercises)", file=sys.stderr)
PY

total_bytes=$(find "$out_dir" -name '*.heic' -exec stat -f %z {} + | awk '{s+=$1} END {print s}')
photo_count=$(find "$out_dir" -name '*.heic' | wc -l | tr -d ' ')
echo "✓ $photo_count photos in $out_dir — $((total_bytes / 1024 / 1024)) MB total, $((total_bytes / photo_count / 1024)) KB average"

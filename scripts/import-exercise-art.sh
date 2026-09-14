#!/bin/bash
# Regenerates DaGym/Resources/ExerciseArtPaths.zlib and DaGym/Data/ExerciseArtCatalog.swift.
#
# Usage:
#   scripts/import-exercise-art.sh <path-to-workout-guide-package>
#
# <path-to-workout-guide-package> is the root of the cloned workout-guide artwork package: it
# must contain manifest.json and assets/<slug>/frame-{1,2,3}.svg. Artwork is CC BY-SA 4.0 (Bryl
# Lim, derived from Everkinetic) — see DaGym/Resources/ATTRIBUTION-ExerciseArt.txt. Only the
# artwork and manifest metadata are read; none of that package's code is used.
#
# Re-runnable and idempotent: safe to run again after the source package updates, or after our
# own exercise seed (DaGym/Resources/Seed/exercises.json) gains or renames exercises.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <path-to-workout-guide-package>" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
source_path="$(cd "$1" && pwd)"

build_dir="$(mktemp -d)"
trap 'rm -rf "$build_dir"' EXIT

swiftc -O \
    "$script_dir/import-exercise-art.swift" \
    "$repo_root/GymCore/Sources/GymCore/Import/ImportAliases.swift" \
    -o "$build_dir/import-exercise-art"

"$build_dir/import-exercise-art" "$source_path"

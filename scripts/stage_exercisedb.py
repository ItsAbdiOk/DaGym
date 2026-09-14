#!/usr/bin/env python3
"""Stage the ExerciseDB metadata (as republished by hasaneyldrm/exercises-dataset) into our
seed JSON shape, WITHOUT touching the shipping seed.

This is an evaluation staging script, not a merge tool. It never writes to
DaGym/Resources/Seed. Output always goes to docs/reviews/exercisedb-staged/exercises.json
(gitignored, see docs/reviews/exercisedb.md for the full licence + quality writeup).

Usage:
    python3 scripts/stage_exercisedb.py /path/to/exercises-dataset

Idempotent: re-running with the same input produces byte-identical output (records are
sorted by id, no timestamps of our own are written).

IMPORTANT — licence: hasaneyldrm/exercises-dataset claims MIT for the non-media data, but
that dataset *is* ExerciseDB's metadata, and ExerciseDB's operator (AscendAPI) disputes
third-party republication rights. Do not point DaGym/Resources/Seed at this output, do not
ship it, and do not flip any flag that loads it, until the owner has read
docs/reviews/exercisedb.md and made a licensing call. This script exists so the *shape* of
an eventual import can be reviewed, not to green-light the import.

Name matching against our seed deliberately mirrors the normalisation rules in
GymCore/Sources/GymCore/Import/ImportAliases.swift (lower-case, strip punctuation, split a
trailing "(Equipment)" qualifier) so a future Swift importer can reuse that file's alias table
instead of this script's throwaway matcher. This script is Python because it only produces a
side-by-side review artifact under docs/ — if adoption is approved, the real merge should be
written in Swift against ImportAliases directly, not by promoting this script.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
SEED_PATH = REPO_ROOT / "DaGym" / "Resources" / "Seed" / "exercises.json"
OUT_DIR = REPO_ROOT / "docs" / "reviews" / "exercisedb-staged"

# ExerciseDB `target` -> our GymCore.Muscle raw value. `None` means "no clean equivalent,
# drop rather than guess" (kept, but flagged with unmappedTarget).
TARGET_TO_MUSCLE = {
    "abs": "abs",
    "pectorals": "chest",
    "biceps": "biceps",
    "glutes": "glutes",
    "delts": "delts",
    "triceps": "triceps",
    "lats": "lats",
    "calves": "calves",
    "quads": "quads",
    "forearms": "forearms",
    "hamstrings": "hams",
    "traps": "traps",
    "spine": "lowerBack",
    "adductors": "quads",
    "serratus anterior": "chest",
    "abductors": "glutes",
    "levator scapulae": "traps",
    "upper back": "lats",
    "cardiovascular system": None,
}

# ExerciseDB `equipment` -> our equipment vocabulary (bodyweight/dumbbell/barbell/cable/
# kettlebell/machine/bands/ezBar/other), matching DaGym/Resources/Seed/exercises.json.
EQUIPMENT_MAP = {
    "body weight": "bodyweight",
    "dumbbell": "dumbbell",
    "cable": "cable",
    "barbell": "barbell",
    "leverage machine": "machine",
    "band": "bands",
    "smith machine": "machine",
    "kettlebell": "kettlebell",
    "weighted": "other",
    "stability ball": "other",
    "ez barbell": "ezBar",
    "assisted": "other",
    "sled machine": "machine",
    "medicine ball": "other",
    "rope": "cable",
    "roller": "other",
    "resistance band": "bands",
    "bosu ball": "other",
    "olympic barbell": "barbell",
    "wheel roller": "other",
    "upper body ergometer": "machine",
    "skierg machine": "machine",
    "hammer": "other",
    "stationary bike": "machine",
    "tire": "other",
    "trap bar": "barbell",
    "elliptical machine": "machine",
    "stepmill machine": "machine",
}

_STOP_QUALIFIERS = {"barbell", "dumbbell", "machine", "cable", "kettlebell", "bodyweight", "ezbar", "ez bar"}


def normalised_name(name: str) -> tuple[str, str | None]:
    """Mirrors ImportAliases.normalised(_:): lower-case, strip a trailing "(Equipment)"."""
    text = name.strip()
    open_paren = text.rfind("(")
    close_paren = text.rfind(")")
    if open_paren == -1 or close_paren == -1 or open_paren >= close_paren:
        return _clean(text.lower()), None
    inside = text[open_paren + 1:close_paren].strip().lower()
    if inside not in _STOP_QUALIFIERS:
        return _clean(text.lower()), None
    base = text[:open_paren].strip()
    return _clean(base.lower()), inside


def _clean(text: str) -> str:
    text = text.replace("-", " ").replace("_", " ").replace("/", " ")
    text = re.sub(r"[^\w\s]", "", text)
    return re.sub(r"\s+", " ", text).strip()


def load_seed_names() -> set[str]:
    if not SEED_PATH.exists():
        return set()
    seed = json.loads(SEED_PATH.read_text())["exercises"]
    return {normalised_name(e["name"])[0] for e in seed}


def convert(dataset_dir: Path) -> list[dict]:
    data_path = dataset_dir / "data" / "exercises.json"
    if not data_path.exists():
        raise SystemExit(f"expected {data_path} (dataset layout changed?)")
    records = json.loads(data_path.read_text())
    seed_names = load_seed_names()

    out = []
    for rec in sorted(records, key=lambda r: r["id"]):
        target = rec.get("target", "")
        primary_muscle = TARGET_TO_MUSCLE.get(target)
        secondary = []
        for m in rec.get("secondary_muscles", []):
            mapped = TARGET_TO_MUSCLE.get(m)
            if mapped and mapped != primary_muscle and mapped not in secondary:
                secondary.append(mapped)

        equipment = EQUIPMENT_MAP.get(rec.get("equipment", ""), "other")
        base_name, _ = normalised_name(rec["name"])

        out.append({
            "id": f"exercisedb_{rec['id']}",
            "name": rec["name"],
            "primary": [primary_muscle] if primary_muscle else [],
            "secondary": secondary,
            "equipment": equipment,
            "instructions": rec.get("instructions", {}).get("en", ""),
            "instructionSteps": rec.get("instruction_steps", {}).get("en", []),
            "source": "exercisedb-via-hasaneyldrm",
            "sourceURL": "https://github.com/hasaneyldrm/exercises-dataset",
            "licence": "MIT (claimed by republisher — DISPUTED, see docs/reviews/exercisedb.md)",
            "authors": [],
            "media": {
                "attribution": rec.get("attribution", ""),
                "note": "Media (image/gif) is (c) Gym visual, NOT MIT. Not staged here — "
                        "metadata only. Do not copy images/ or videos/ into the app bundle.",
            },
            "unmappedTarget": target if primary_muscle is None else None,
            "matchesSeedByName": base_name in seed_names,
        })
    return out


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("dataset_path", help="path to a checkout of hasaneyldrm/exercises-dataset")
    args = parser.parse_args()

    dataset_dir = Path(args.dataset_path).expanduser().resolve()
    if not dataset_dir.exists():
        raise SystemExit(f"no such path: {dataset_dir}")

    staged = convert(dataset_dir)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out_path = OUT_DIR / "exercises.json"
    payload = {
        "version": 1,
        "staged": True,
        "warning": "STAGING ONLY. Disputed licence — see docs/reviews/exercisedb.md. "
                   "Do NOT copy into DaGym/Resources/Seed or wire into the app.",
        "source": "hasaneyldrm/exercises-dataset (republished ExerciseDB metadata, MIT claimed "
                   "but disputed by AscendAPI)",
        "recordCount": len(staged),
        "exercises": staged,
    }
    out_path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n")
    matched = sum(1 for e in staged if e["matchesSeedByName"])
    print(f"wrote {len(staged)} records to {out_path}")
    print(f"{matched} match an existing seed exercise by normalised name; "
          f"{len(staged) - matched} are net-new candidates")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""Fill missing `instructions` text in DaGym/Resources/Seed/exercises.json.

Two modes:
  --emit-todo
      Writes docs/instructions-todo.json: a list of
      {id, name, equipment, primary, mechanic, loggingStyle}
      for every exercise whose `instructions` is empty or missing.

  --merge docs/instructions-batch-N.json
      Merges a {"id": "instruction text"} mapping back into the seed file.
      Validates each entry before writing:
        - non-empty after stripping
        - <= 70 words
        - contains a digit-dot step marker, e.g. "1."
        - id exists in the seed
        - no duplicate instruction text across ALL exercises (existing + new)
      Sets "source": "dagym" and "licence": "MIT" on every merged row.
      Aborts (no write) if any entry fails validation, printing all failures.

Usage:
  python3 scripts/fill-instructions.py --emit-todo
  python3 scripts/fill-instructions.py --merge docs/instructions-batch-1.json
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED_PATH = ROOT / "DaGym" / "Resources" / "Seed" / "exercises.json"
TODO_PATH = ROOT / "docs" / "instructions-todo.json"

STEP_MARKER_RE = re.compile(r"\d+\.")


def load_seed() -> dict:
    with open(SEED_PATH, encoding="utf-8") as f:
        return json.load(f)


def save_seed(seed: dict) -> None:
    with open(SEED_PATH, "w", encoding="utf-8") as f:
        json.dump(seed, f, indent=2, ensure_ascii=False)
        f.write("\n")


def is_missing(ex: dict) -> bool:
    return not ex.get("instructions")


def emit_todo() -> None:
    seed = load_seed()
    todo = [
        {
            "id": ex["id"],
            "name": ex["name"],
            "equipment": ex.get("equipment"),
            "primary": ex.get("primary", []),
            "mechanic": ex.get("mechanic"),
            "loggingStyle": ex.get("loggingStyle"),
        }
        for ex in seed["exercises"]
        if is_missing(ex)
    ]
    TODO_PATH.parent.mkdir(parents=True, exist_ok=True)
    with open(TODO_PATH, "w", encoding="utf-8") as f:
        json.dump(todo, f, indent=2, ensure_ascii=False)
        f.write("\n")
    print(f"Wrote {len(todo)} missing exercises to {TODO_PATH}")


def word_count(text: str) -> int:
    return len(text.split())


def merge_batch(batch_path: Path) -> None:
    seed = load_seed()
    exercises = seed["exercises"]
    by_id = {ex["id"]: ex for ex in exercises}

    with open(batch_path, encoding="utf-8") as f:
        batch: dict = json.load(f)

    # Existing non-empty instruction texts (normalized) across the whole seed,
    # used to catch duplicates against already-written rows too.
    existing_texts: dict[str, str] = {}
    for ex in exercises:
        text = ex.get("instructions")
        if text:
            norm = " ".join(text.split()).lower()
            existing_texts[norm] = ex["id"]

    errors: list[str] = []
    seen_in_batch: dict[str, str] = {}

    for ex_id, text in batch.items():
        if ex_id not in by_id:
            errors.append(f"{ex_id}: id not found in seed")
            continue
        if not isinstance(text, str) or not text.strip():
            errors.append(f"{ex_id}: empty instructions")
            continue
        stripped = text.strip()
        wc = word_count(stripped)
        if wc > 70:
            errors.append(f"{ex_id}: {wc} words (max 70)")
            continue
        if not STEP_MARKER_RE.search(stripped):
            errors.append(f"{ex_id}: missing digit-dot step marker (e.g. '1.')")
            continue
        norm = " ".join(stripped.split()).lower()
        if norm in existing_texts and existing_texts[norm] != ex_id:
            errors.append(f"{ex_id}: duplicate text also used by {existing_texts[norm]}")
            continue
        if norm in seen_in_batch and seen_in_batch[norm] != ex_id:
            errors.append(f"{ex_id}: duplicate text also used by {seen_in_batch[norm]} (same batch)")
            continue
        seen_in_batch[norm] = ex_id

    if errors:
        print(f"Validation FAILED for {batch_path} — {len(errors)} error(s). No changes written.")
        for e in errors:
            print(f"  - {e}")
        sys.exit(1)

    updated = 0
    for ex_id, text in batch.items():
        ex = by_id[ex_id]
        ex["instructions"] = text.strip()
        ex["source"] = "dagym"
        ex["licence"] = "MIT"
        updated += 1

    save_seed(seed)
    print(f"Merged {updated} instructions from {batch_path} into {SEED_PATH}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--emit-todo", action="store_true", help="emit docs/instructions-todo.json")
    group.add_argument("--merge", metavar="BATCH_JSON", help="merge a batch file into the seed")
    args = parser.parse_args()

    if args.emit_todo:
        emit_todo()
    else:
        merge_batch(Path(args.merge))


if __name__ == "__main__":
    main()

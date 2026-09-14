#!/usr/bin/env python3
"""Merge wger.de exercise data (CC-BY-SA 3.0/4.0) into DaGym/Resources/Seed/exercises.json.

Stdlib only (urllib, json, re, html.parser). No API key needed -- wger's public
API v2 allows anonymous GET reads. See docs/exercise-data-sources.md for the
licence rationale (per-exercise CC-BY-SA, attribution required, share-alike
applies to this data file, not the app's Swift source).

Usage:
    python3 scripts/import-exercises.py
"""
from __future__ import annotations

import json
import re
import urllib.request
import urllib.parse
from html.parser import HTMLParser
from pathlib import Path
from typing import Any

API_BASE = "https://wger.de/api/v2"
SEED_PATH = Path(__file__).resolve().parent.parent / "DaGym" / "Resources" / "Seed" / "exercises.json"
LICENCE = "CC-BY-SA 4.0"  # normalised display licence; per-item short_name kept in sourceURL note
USER_AGENT = "DaGym-import-script/1.0 (+https://wger.de/api/v2/)"

# --- wger muscle id -> our GymCore Muscle raw value (see GymCore/Sources/GymCore/Muscle.swift) ---
# wger has no "forearms" or "lowerBack" muscle in its 15-muscle list; those simply
# never get populated from wger data. "Serratus anterior" and "Brachialis" are
# approximated to the nearest of our 14 regions (documented, not exact anatomy).
MUSCLE_MAP: dict[int, str] = {
    1: "biceps",       # Biceps brachii
    2: "delts",        # Anterior deltoid
    3: "obliques",     # Serratus anterior (approximation) -- the body map draws serratus as an
                       # obliques sub-group (DaGym/Design/Components/BodyMapMuscleMapping.swift),
                       # so mapping it to "chest" tinted a different region than the one the
                       # figure itself labels serratus. The drawing wins.
    4: "chest",        # Pectoralis major
    5: "triceps",      # Triceps brachii
    6: "abs",          # Rectus abdominis
    7: "calves",       # Gastrocnemius
    8: "glutes",       # Gluteus maximus
    9: "traps",        # Trapezius
    10: "quads",       # Quadriceps femoris
    11: "hams",        # Biceps femoris
    12: "lats",        # Latissimus dorsi
    13: "biceps",       # Brachialis (approximation)
    14: "obliques",    # Obliquus externus abdominis
    15: "calves",      # Soleus
}

# wger equipment id -> our free-form equipment string (see exercises.json values:
# bands, barbell, bodyweight, cable, dumbbell, ezBar, kettlebell, machine, other)
EQUIPMENT_MAP: dict[int, str] = {
    1: "barbell",
    2: "ezBar",
    3: "dumbbell",
    4: "other",        # Gym mat
    5: "other",         # Swiss Ball
    6: "bodyweight",    # Pull-up bar
    7: "bodyweight",    # none (bodyweight exercise)
    8: "other",         # Bench
    9: "other",         # Incline bench
    10: "kettlebell",
    11: "bands",
    12: "cable",
}

# Manual alias table: wger exercise name -> our seed exercise name, for the
# mismatches the normaliser can't bridge (found by running this script once
# with ALIASES = {} and inspecting the unmatched list).
ALIASES: dict[str, str] = {
    "Bench Press": "Barbell Bench Press - Medium Grip",
    "Dumbbell Bench Press": "Dumbbell Bench Press",
    "Squats": "Barbell Squat",
    "Barbell Squats": "Barbell Squat",
    "Deadlift": "Barbell Deadlift",
    "Romanian Deadlift": "Romanian Deadlift",
    "Pullups": "Pullups",
    "Pull-ups": "Pullups",
    "Chin-ups": "Chin-Up",
    "Push Ups": "Pushups",
    "Push-Ups": "Pushups",
    "Overhead Press": "Standing Military Press",
    "Military Press": "Standing Military Press",
    "Barbell Curl": "Barbell Curl",
    "Bicep Curl": "Dumbbell Bicep Curl",
    "Lat Pulldown": "Wide-Grip Lat Pulldown",
    "Seated Row": "Seated Cable Rows",
    "Leg Press": "Leg Press",
    "Leg Curl": "Lying Leg Curls",
    "Leg Extension": "Leg Extensions",
    "Calf Raise": "Standing Calf Raises",
    "Hip Thrust": "Barbell Hip Thrust",
    "Face Pull": "Face Pull",
    "Plank": "Plank",
    "Side Plank": "Side Bridge",
}


class _TextExtractor(HTMLParser):
    """Strips HTML tags, keeping block-level tags as paragraph breaks."""

    _BLOCK_TAGS = {"p", "li", "div", "br", "ul", "ol"}

    def __init__(self) -> None:
        super().__init__()
        self.chunks: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag in self._BLOCK_TAGS:
            self.chunks.append("\n")

    def handle_endtag(self, tag: str) -> None:
        if tag in self._BLOCK_TAGS:
            self.chunks.append("\n")

    def handle_data(self, data: str) -> None:
        self.chunks.append(data)


def strip_html(html: str) -> str:
    """Convert wger's HTML description into plain-text paragraphs."""
    parser = _TextExtractor()
    parser.feed(html)
    raw = "".join(parser.chunks)
    lines = [line.strip() for line in raw.splitlines()]
    paragraphs = [line for line in lines if line]
    return "\n".join(paragraphs)


def normalise_name(name: str) -> str:
    """Lowercase, strip punctuation, sort tokens -- makes word order irrelevant
    so "Barbell Bench Press" ~ "Bench Press Barbell"."""
    cleaned = re.sub(r"[^a-z0-9 ]", " ", name.lower())
    tokens = sorted(t for t in cleaned.split() if t)
    return " ".join(tokens)


def fetch_json(url: str) -> dict[str, Any]:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.loads(response.read().decode("utf-8"))


def fetch_all_exercises() -> list[dict[str, Any]]:
    """Paginate through /exerciseinfo/ filtered to English, following `next`."""
    params = urllib.parse.urlencode({"language": "2", "limit": "100", "format": "json"})
    url = f"{API_BASE}/exerciseinfo/?{params}"
    results: list[dict[str, Any]] = []
    while url:
        page = fetch_json(url)
        results.extend(page.get("results", []))
        url = page.get("next")
    return results


def english_translation(entry: dict[str, Any]) -> dict[str, Any] | None:
    for translation in entry.get("translations", []):
        if translation.get("language") == 2 and translation.get("name"):
            return translation
    return None


def map_muscles(muscle_list: list[dict[str, Any]]) -> list[str]:
    mapped = []
    for muscle in muscle_list:
        value = MUSCLE_MAP.get(muscle.get("id"))
        if value and value not in mapped:
            mapped.append(value)
    return mapped


def map_equipment(equipment_list: list[dict[str, Any]]) -> str:
    if not equipment_list:
        return "bodyweight"
    return EQUIPMENT_MAP.get(equipment_list[0].get("id"), "other")


def build_wger_record(entry: dict[str, Any]) -> dict[str, Any] | None:
    translation = english_translation(entry)
    if translation is None:
        return None
    name = translation["name"].strip()
    instructions = strip_html(translation.get("description", ""))
    license_info = entry.get("license") or {}
    short_name = license_info.get("short_name", "CC-BY-SA").replace("CC-BY-SA 4", "CC-BY-SA 4.0").replace(
        "CC-BY-SA 3", "CC-BY-SA 3.0"
    )
    authors = sorted({a for a in entry.get("author_history", []) if a})
    images = [
        {
            "url": image.get("image"),
            "licence": (image.get("license_title") or short_name),
            "author": image.get("license_author") or (authors[0] if authors else ""),
        }
        for image in entry.get("images", [])
        if image.get("image")
    ]
    return {
        "wger_id": entry.get("id"),
        "name": name,
        "instructions": instructions,
        "primary": map_muscles(entry.get("muscles", [])),
        "secondary": map_muscles(entry.get("muscles_secondary", [])),
        "equipment": map_equipment(entry.get("equipment", [])),
        "licence": short_name,
        "sourceURL": f"https://wger.de/en/exercise/{entry.get('uuid', entry.get('id'))}/view/",
        "authors": authors,
        "images": images,
    }


def slugify(name: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9]+", "_", name).strip("_")
    return cleaned or "Exercise"


def merge(seed: dict[str, Any], wger_records: list[dict[str, Any]]) -> tuple[int, int]:
    existing = seed["exercises"]
    by_norm: dict[str, dict[str, Any]] = {normalise_name(item["name"]): item for item in existing}
    existing_ids = {item["id"] for item in existing}

    matched = 0
    appended = 0
    skipped_unmapped = 0
    for record in wger_records:
        alias_target = ALIASES.get(record["name"])
        target = by_norm.get(normalise_name(alias_target)) if alias_target else None
        if target is None:
            target = by_norm.get(normalise_name(record["name"]))

        if target is not None:
            target["instructions"] = record["instructions"]
            target["source"] = "wger"
            target["sourceURL"] = record["sourceURL"]
            target["licence"] = record["licence"]
            target["authors"] = record["authors"]
            if record["images"]:
                target["images"] = record["images"]
            matched += 1
            continue

        if not record["instructions"]:
            continue  # skip stub-only unmatched entries, not worth appending

        # No fallback muscle. The `primary` line below used to read
        # `record["primary"] or ["abs"]`, which quietly turned every wger exercise whose
        # muscles failed to map -- neck stretches, rotator-cuff work, running, rest timers --
        # into an abs exercise, and made abs the most common primary mover in the library.
        # An exercise we cannot tag is an exercise we do not append;
        # DaGymTests/SeedMuscleDataTests.swift fails the build if one ever ships with an
        # empty `primary` outside the curated non-muscular allowlist.
        if not record["primary"]:
            skipped_unmapped += 1
            continue

        new_id = slugify(record["name"])
        suffix = 2
        while new_id in existing_ids:
            new_id = f"{slugify(record['name'])}_{suffix}"
            suffix += 1
        existing_ids.add(new_id)

        new_item = {
            "id": new_id,
            "name": record["name"],
            "primary": record["primary"],
            "secondary": record["secondary"],
            "equipment": record["equipment"],
            "mechanic": None,
            "loggingStyle": "bodyweightReps" if record["equipment"] == "bodyweight" else "weightReps",
            "isPerSide": False,
            "bar": "olympic" if record["equipment"] == "barbell" else None,
            "incrementKg": 0.0 if record["equipment"] == "bodyweight" else 2.5,
            "restSeconds": 150,
            "instructions": record["instructions"],
            "source": "wger",
            "sourceURL": record["sourceURL"],
            "licence": record["licence"],
            "authors": record["authors"],
        }
        if record["images"]:
            new_item["images"] = record["images"]
        existing.append(new_item)
        by_norm[normalise_name(record["name"])] = new_item
        appended += 1

    if skipped_unmapped:
        print(f"skipped {skipped_unmapped} wger exercises with no mappable muscles")
    return matched, appended


def main() -> None:
    seed = json.loads(SEED_PATH.read_text())
    original_total = len(seed["exercises"])

    wger_entries = fetch_all_exercises()
    records = [r for r in (build_wger_record(e) for e in wger_entries) if r is not None]

    matched, appended = merge(seed, records)

    seed["version"] = 2
    seed["source"] = (
        "free-exercise-db (yuhonas/free-exercise-db, Unlicense) — names, muscles, equipment; "
        "wger.de (wger-project, CC-BY-SA 3.0/4.0 per exercise) — instructions, additional exercises. "
        "See docs/exercise-data-sources.md for attribution details."
    )

    SEED_PATH.write_text(json.dumps(seed, indent=2) + "\n")

    still_missing = sum(
        1 for item in seed["exercises"][:original_total] if not item.get("instructions")
    )

    print(f"wger exercises fetched: {len(wger_entries)}")
    print(f"matched to existing seed rows: {matched}")
    print(f"newly appended: {appended}")
    print(f"original {original_total} seed exercises still missing instructions: {still_missing}")


if __name__ == "__main__":
    main()

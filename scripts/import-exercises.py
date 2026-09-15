#!/usr/bin/env python3
"""Merge wger.de exercise data (CC-BY-SA 3.0/4.0) into DaGym/Resources/Seed/exercises.json.

Stdlib only (urllib, json, re, html.parser). No API key needed -- wger's public
API v2 allows anonymous GET reads. See docs/exercise-data-sources.md for the
licence rationale (per-exercise CC-BY-SA, attribution required, share-alike
applies to this data file, not the app's Swift source).

Usage:
    python3 scripts/import-exercises.py                 # merge wger data (network)
    python3 scripts/import-exercises.py --tag-machines  # offline: (re)apply MACHINE_RULES only
"""
from __future__ import annotations

import json
import re
import sys
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


# --- Station tagging (`machine` field, GymCore `Machine` raw values) ---------------------------
#
# Each rule is (equipment kinds it applies to, case-insensitive name regex, Machine raw value or
# None for "explicitly no station"). First match wins, so specific rules come before generic
# ones. Rows of a kind with no matching rule are left untagged; `--tag-machines` prints a table
# of counts per station and the untagged remainder for hand-checking.
#
# Kinds: "machine"/"cable" rows are the target. "other" and "bodyweight" are the seed's two
# catch-all kinds (every wger import without equipment landed in "bodyweight"), so a station tag
# there is a refinement — "Leverage Machine Chest Press" is filed as bodyweight but needs the
# chest press. Barbell/dumbbell/… rows are never tagged; a Smith move filed under barbell is an
# equipment error, fixed by EQUIPMENT_FIXES before the rules run.
TAGGABLE_KINDS = {"machine", "cable", "other", "bodyweight"}
CATCH_ALL_KINDS = {"other", "bodyweight"}
MACHINE_RULES: list[tuple[set[str], str, str | None]] = [
    # Cardio stations first: their names are unambiguous. "Rowing" alone is not the erg — wger's
    # "Rowing seated", "Rowing, T-bar" and "Rowing with TRX band" are strength rows.
    (TAGGABLE_KINDS, r"treadmill", "treadmill"),
    (TAGGABLE_KINDS, r"rowing machine|rowing, stationary|\brower\b", "rower"),
    (TAGGABLE_KINDS, r"elliptical", "elliptical"),
    (TAGGABLE_KINDS, r"stairmaster|stair master|step mill|stair climber|climbmill", "stairClimber"),
    (TAGGABLE_KINDS, r"bicycling, stationary|recumbent bike|stationary bike|air bike", "stationaryBike"),
    (TAGGABLE_KINDS, r"ski machine|skierg|ski erg", "skiErg"),
    # Smith before anything else: "Smith Machine Leg Press" is a Smith move. wger calls the Smith
    # a "Multi Press".
    (TAGGABLE_KINDS, r"\bsmith\b|multi press", "smithMachine"),
    # Machine kind. "Lying Machine Squat" is lie-back-feet-on-platform-press: a leg press.
    (TAGGABLE_KINDS, r"leg press|calf press|toe press|side glute press|lying machine squat", "legPress"),
    (TAGGABLE_KINDS, r"pendular|pendulum", "pendulumSquat"),
    (TAGGABLE_KINDS, r"belt squat", "beltSquat"),
    (TAGGABLE_KINDS, r"hack squat|hackenschmitt|v-squat", "hackSquat"),
    (TAGGABLE_KINDS, r"leg extension", "legExtension"),
    (TAGGABLE_KINDS, r"ball leg curl", None),
    (TAGGABLE_KINDS, r"leg curl", "legCurl"),
    (TAGGABLE_KINDS, r"thigh abductor|thigh adductor|machine hip abduction|seated hip (ab|ad)duction",
     "hipAbductorAdductor"),
    (TAGGABLE_KINDS, r"seated calf|sitting calf raise", "seatedCalf"),
    ({"machine"}, r"calf", "calfRaiseMachine"),
    (TAGGABLE_KINDS, r"ab crunch machine|crunches on machine|3008 abdominal", "abCrunchMachine"),
    # Floor / partner / ball / bench variants of the hyper and GHR need no station; the reverse
    # hyper row is written for a flat bench.
    (TAGGABLE_KINDS, r"natural glute ham|floor glute-ham|hyper y w|reverse hyperextension|no hyperextension bench",
     None),
    (TAGGABLE_KINDS, r"glute ham raise|machine glute extension", "gluteHamDeveloper"),
    (TAGGABLE_KINDS, r"hyperextensions|roman chair crunch", "backExtension"),
    (TAGGABLE_KINDS, r"^butterfly( narrow grip)?$|pec deck|reverse machine flyes|machine chest fly", "pecDeck"),
    (TAGGABLE_KINDS, r"leverage.*chest press|machine bench press|machine press|leverage machine chest|"
     r"hammerstrength.*chest press|legend (incline bench|chest) press|seated bench press|^chest press$|"
     r"diagonal shoulder press", "chestPressMachine"),
    (TAGGABLE_KINDS, r"machine shoulder|leverage shoulder press", "shoulderPressMachine"),
    (TAGGABLE_KINDS, r"machine (side )?lateral raise", "lateralRaiseMachine"),
    (TAGGABLE_KINDS, r"pullover machine", "pulloverMachine"),
    (TAGGABLE_KINDS, r"machine preacher|machine bicep curl|biceps curl machine", "preacherCurlMachine"),
    (TAGGABLE_KINDS, r"dip machine", "seatedDipMachine"),
    (TAGGABLE_KINDS, r"machine triceps extension|triceps on machine", "tricepsExtensionMachine"),
    (TAGGABLE_KINDS, r"leverage high row|leverage iso row|leverage machine iso row|t-bar row|rowing, t-bar|"
     r"seated row \(machine\)", "rowMachine"),
    (TAGGABLE_KINDS, r"rotary torso", "torsoRotation"),
    (TAGGABLE_KINDS, r"glute kickback \(machine\)", "gluteKickback"),
    (TAGGABLE_KINDS, r"band assisted", "pullUpBar"),
    (TAGGABLE_KINDS, r"assisted", "assistedDipPullUp"),
    # Cable kind: the seated-row seat and the lat-pulldown seat are their own stations. A
    # single-arm pulldown *sat at the lat pulldown machine* (its instructions say so) stays on
    # that seat; a half-kneeling / cross-body / standing one is done on the dual adjustable pulley.
    (TAGGABLE_KINDS, r"seated cable rows?|long-pulley|seated v-grip row|seated one-arm cable pulley rows|"
     r"low pulley row to neck|seated cable mid trap shrug|rowing seated|unilateral cable row",
     "seatedRowMachine"),
    ({"cable"}, r"^one arm lat pulldown$|^single-arm lat pulldown$|cross body single arm|modified pulldown|"
     r"mentzer", "latPulldown"),
    ({"cable"}, r"single-arm|one arm|1-arm|cross body|cross-body|half-kneeling|unilateral|incline bench pulldown",
     "cableStation"),
    ({"cable"}, r"straight-arm|straight arm|pullover", "cableStation"),
    ({"cable"}, r"pulldown|pull down|jalón", "latPulldown"),
    ({"cable"}, r".", "cableStation"),
    # Catch-all kinds: only what plainly names a station.
    (CATCH_ALL_KINDS, r"cable|polea|pulley", "cableStation"),
    # Hangboards, floor/low-bar and stretch rows share words with bar work; rule them out first.
    (CATCH_ALL_KINDS, r"fingerboard|sloper|australian|chin tuck", None),
    (CATCH_ALL_KINDS, r"parallel bar|dips - chest|dips - triceps|^dips$", "dipStation"),
    (CATCH_ALL_KINDS, r"pull-?ups?|chin-?up|\bchins\b|chin/crunch|mixed grip chin|muscle up|"
     r"hanging (leg|knee|pike)|toes to bar|pull up bar|arch hang|front lever|back lever", "pullUpBar"),
    (CATCH_ALL_KINDS, r"pulldown|pull down", "latPulldown"),
]
# Rows whose `equipment` the source got wrong in a way a station tag must not paper over: a
# Smith move is a machine move. Applied before MACHINE_RULES so the Smith rule then tags them.
EQUIPMENT_FIXES: dict[str, str] = {
    "Smith_Machine_Split_Squat": "machine",
    "Smith_Incline_Shoulder_Raise": "machine",
}
# Machine-kind rows that genuinely have no station in the taxonomy (or aren't machines at all)
# — listed so DaGymTests/SeedMachineDataTests can insist every other machine row is tagged.
UNTAGGED_MACHINE_ROWS: dict[str, str] = {
    "Chair_Squat": "a bodyweight squat to a chair; 'machine' is a source error",
    "Lunge_Sprint": "a sprinting drill; 'machine' is a source error",
    "Leverage_Deadlift": "plate-loaded deadlift/shrug machine — too rare for a station",
    "Leverage_Shrug": "plate-loaded shrug machine — too rare for a station",
    "Reverse_Hyperextension": "written for a flat bench; the dedicated reverse-hyper machine is too rare",
}


def machine_for(item: dict[str, Any]) -> str | None:
    """The station `item` needs by the first matching MACHINE_RULES row, or None."""
    kind = item["equipment"]
    if kind not in TAGGABLE_KINDS:
        return None
    for kinds, pattern, machine in MACHINE_RULES:
        if kind in kinds and re.search(pattern, item["name"], re.IGNORECASE):
            return machine
    return None


def tag_machines(seed: dict[str, Any]) -> None:
    """Sets `machine` on every row the rules match and prints the per-station table. Touches
    nothing else — the field is added or replaced, never any other key — except the
    EQUIPMENT_FIXES rows, whose `equipment` is corrected first."""
    counts: dict[str, int] = {}
    untagged: dict[str, list[str]] = {}
    for item in seed["exercises"]:
        if item["id"] in EQUIPMENT_FIXES:
            item["equipment"] = EQUIPMENT_FIXES[item["id"]]
        machine = machine_for(item)
        if machine is None:
            item.pop("machine", None)
            if item["equipment"] in ("machine", "cable"):
                untagged.setdefault(item["equipment"], []).append(item["name"])
            continue
        item["machine"] = machine
        counts[machine] = counts.get(machine, 0) + 1
    print(f"{'station':24} {'rows':>4}")
    for machine, count in sorted(counts.items(), key=lambda pair: (-pair[1], pair[0])):
        print(f"{machine:24} {count:>4}")
    print(f"{'total tagged':24} {sum(counts.values()):>4}")
    for kind, names in untagged.items():
        print(f"\nuntagged {kind} rows ({len(names)}):")
        for name in names:
            print(f"  {name}")


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

    if "--tag-machines" in sys.argv[1:]:
        tag_machines(seed)
        SEED_PATH.write_text(json.dumps(seed, indent=2, ensure_ascii=False) + "\n")
        return

    wger_entries = fetch_all_exercises()
    records = [r for r in (build_wger_record(e) for e in wger_entries) if r is not None]

    matched, appended = merge(seed, records)

    seed["version"] = 2
    seed["source"] = (
        "free-exercise-db (yuhonas/free-exercise-db, Unlicense) — names, muscles, equipment; "
        "wger.de (wger-project, CC-BY-SA 3.0/4.0 per exercise) — instructions, additional exercises. "
        "See docs/exercise-data-sources.md for attribution details."
    )

    tag_machines(seed)
    SEED_PATH.write_text(json.dumps(seed, indent=2, ensure_ascii=False) + "\n")

    still_missing = sum(
        1 for item in seed["exercises"][:original_total] if not item.get("instructions")
    )

    print(f"wger exercises fetched: {len(wger_entries)}")
    print(f"matched to existing seed rows: {matched}")
    print(f"newly appended: {appended}")
    print(f"original {original_total} seed exercises still missing instructions: {still_missing}")


if __name__ == "__main__":
    main()

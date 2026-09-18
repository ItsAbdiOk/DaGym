#!/usr/bin/env python3
"""Propose media aliases: uncovered seeded exercises -> a covered exercise showing the same movement.

An exercise is "covered" when it has illustrated art (DaGym/Data/ExerciseArtCatalog.swift),
bundled photos (DaGym/Resources/ExercisePhotos/<seedID>-0.heic) or an existing alias in
DaGym/Resources/Seed/exercise-media-aliases.json. For everything else this prints the best few
covered candidates with a score, so a human can pick the true matches — the output is a
proposal list, never the alias file itself. Only the final, hand-reviewed mapping is committed.

Scoring is deliberately simple: weighted token overlap on the normalised names (movement words
such as "curl" or "squat" count most, equipment words least) multiplied by primary-muscle
agreement. Zero primary-muscle overlap is never proposed.

Usage:
    scripts/propose-media-aliases.py            # one line per uncovered exercise, top 3
    scripts/propose-media-aliases.py --min 0.4  # only proposals scoring at least 0.4
    scripts/propose-media-aliases.py --json     # machine-readable, every candidate
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SEED = ROOT / "DaGym" / "Resources" / "Seed" / "exercises.json"
ART = ROOT / "DaGym" / "Data" / "ExerciseArtCatalog.swift"
PHOTOS = ROOT / "DaGym" / "Resources" / "ExercisePhotos"
ALIASES = ROOT / "DaGym" / "Resources" / "Seed" / "exercise-media-aliases.json"

STOP = {"with", "the", "on", "a", "of", "and", "to", "in", "using", "an", "or", "for", "at", "from", "your"}

# Plural / spelling variants folded to one token.
SYNONYMS = {
    "biceps": "bicep", "triceps": "tricep", "curls": "curl", "rows": "row", "rowing": "row", "raises": "raise",
    "presses": "press", "squats": "squat", "lunges": "lunge", "crunches": "crunch", "extensions": "extension",
    "flyes": "fly", "flies": "fly", "flys": "fly", "flye": "fly", "pullovers": "pullover", "dips": "dip",
    "shrugs": "shrug", "pushups": "pushup", "deadlifts": "deadlift", "kickbacks": "kickback",
    "pulldowns": "pulldown", "pulls": "pull", "dumbbells": "dumbbell", "db": "dumbbell", "bb": "barbell",
    "sz": "ez", "kettlebells": "kettlebell", "kb": "kettlebell", "swings": "swing", "planks": "plank",
    "bridges": "bridge", "thrusts": "thrust", "stretches": "stretch", "twists": "twist", "jumps": "jump",
    "hammercurls": "hammer curl", "skullcrusher": "skull crusher", "skullcrushers": "skull crusher",
    "pushdowns": "pushdown", "pull-ups": "pullup", "pullups": "pullup", "chinups": "chinup",
    "situps": "sit up", "situp": "sit up", "ups": "up", "hyperextensions": "hyperextension",
    "pushup": "push up", "pullup": "pull up", "chinup": "chin up", "facepull": "face pull",
    "facepulls": "face pull", "deadbug": "dead bug", "deadhang": "dead hang", "woodchoppers": "wood chop",
    "woodchopper": "wood chop", "woodchop": "wood chop", "chops": "chop", "pendelay": "pendlay",
    "stepups": "step up", "stepup": "step up", "getup": "get up", "getups": "get up", "legpress": "leg press",
    "rdl": "romanian deadlift", "rdls": "romanian deadlift", "ohp": "overhead press", "ez-bar": "ez bar",
    "benchpress": "bench press", "goodmorning": "good morning", "lat": "lat", "lats": "lat",
    "abdominal": "ab", "abs": "ab", "single": "one", "alternate": "alternating", "supinated": "underhand",
    "pronated": "overhand", "reverse": "reverse", "lying": "lying", "laying": "lying",
}

MOVEMENT = {
    "curl", "press", "squat", "row", "raise", "pulldown", "chin", "fly", "extension", "crunch", "chop", "dead",
    "bug", "face", "sit", "up", "get", "turkish", "romanian", "pendlay", "renegade", "thruster", "handstand",
    "deadlift", "lunge", "pullover", "dip", "shrug", "pushup", "kickback", "pushdown", "swing", "plank",
    "bridge", "thrust", "stretch", "twist", "jump", "situp", "hyperextension", "clean", "snatch", "jerk",
    "carry", "walk", "hold", "hang", "step", "burpee", "crawl", "climber", "rollout", "pull", "push",
    "rotation", "flexion", "abduction", "adduction", "kick", "hinge", "windmill", "halo", "getup", "skull",
    "crusher", "good", "morning", "rdl", "leg", "calf", "hip", "glute", "ham", "lat", "ab", "tricep", "bicep",
    "chest", "shoulder", "back", "neck", "wrist", "forearm", "delt", "trap", "hammer", "preacher", "concentration",
    "front", "lateral", "rear", "side", "overhead", "upright", "bent", "incline", "decline", "flat", "seated",
    "standing", "lying", "kneeling", "hanging", "wide", "close", "narrow", "underhand", "overhand", "neutral",
    "reverse", "one", "alternating", "sumo", "goblet", "zercher", "hack", "bulgarian", "split", "pistol", "box",
    "wall", "pike", "diamond", "nordic", "sissy", "cossack", "jump", "high", "low", "cross", "face", "pull",
    "over", "arm", "military", "arnold", "landmine", "trap", "bar", "t", "hex",
}
EQUIPMENT = {
    "barbell", "dumbbell", "cable", "machine", "band", "bands", "kettlebell", "ez", "smith", "trx", "suspension",
    "plate", "plates", "rope", "ball", "bench", "bodyweight", "weighted", "medicine", "stability", "swiss",
    "trap", "hex", "sled", "chain", "chains", "bar", "v", "handle", "attachment", "pulley", "resistance",
}


def tokens(name: str) -> dict[str, float]:
    words = re.sub(r"[^a-z0-9]+", " ", name.lower()).split()
    weighted: dict[str, float] = {}
    for raw in words:
        for word in SYNONYMS.get(raw, raw).split():
            if word in STOP or word.isdigit() and len(word) > 2:
                continue
            weight = 3.0 if word in MOVEMENT else 0.5 if word in EQUIPMENT else 1.0
            weighted[word] = max(weighted.get(word, 0.0), weight)
    return weighted


def similarity(a: dict[str, float], b: dict[str, float]) -> float:
    shared = sum(min(a[t], b[t]) for t in a if t in b)
    union = sum(max(a.get(t, 0.0), b.get(t, 0.0)) for t in set(a) | set(b))
    return shared / union if union else 0.0


def load_covered() -> set[str]:
    art = set(re.findall(r'"([^"]+)":\s*"[^"]+"', ART.read_text()))
    photos = {f[:-7] for f in os.listdir(PHOTOS) if f.endswith("-0.heic")}
    return art | photos


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--min", type=float, default=0.0, help="drop proposals scoring below this")
    parser.add_argument("--top", type=int, default=3)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()

    exercises = json.loads(SEED.read_text())["exercises"]
    covered = load_covered()
    aliases = json.loads(ALIASES.read_text()) if ALIASES.exists() else {}
    by_id = {e["id"]: e for e in exercises}
    targets = [e for e in exercises if e["id"] in covered]
    target_tokens = {e["id"]: tokens(e["name"]) for e in targets}

    proposals = []
    for exercise in exercises:
        seed_id = exercise["id"]
        if seed_id in covered or seed_id in aliases:
            continue
        own = tokens(exercise["name"])
        primary = set(exercise["primary"])
        scored = []
        for target in targets:
            target_primary = set(target["primary"])
            # Same primary muscle, or a secondary overlap at a discount; an exercise whose seed
            # entry names no primary muscle at all (a few stretches) is matched on name only.
            if not primary:
                muscle = 0.8
            elif primary & target_primary:
                muscle = 1.0
            elif primary & set(target.get("secondary", [])) or target_primary & set(exercise.get("secondary", [])):
                muscle = 0.6
            else:
                continue
            same_equipment = 1.0 if exercise["equipment"] == target["equipment"] else 0.9
            score = similarity(own, target_tokens[target["id"]]) * same_equipment * muscle
            if score >= args.min and score > 0:
                scored.append((round(score, 2), target["id"]))
        scored.sort(reverse=True)
        proposals.append({
            "id": seed_id, "name": exercise["name"], "primary": exercise["primary"],
            "equipment": exercise["equipment"],
            "candidates": [{"id": t, "name": by_id[t]["name"], "score": s} for s, t in scored[: args.top]],
        })

    if args.json:
        json.dump(proposals, sys.stdout, indent=1)
        return
    for p in proposals:
        cands = "; ".join(f"{c['id']} ({c['score']})" for c in p["candidates"]) or "-"
        print(f"{p['id']} | {p['name']} | {'/'.join(p['primary'])} | {p['equipment']} => {cands}")
    print(f"{len(proposals)} uncovered exercises, {len(covered)} covered targets", file=sys.stderr)


if __name__ == "__main__":
    main()

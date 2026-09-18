#!/usr/bin/env python3
"""Import the exercise images that do not come from free-exercise-db: wger.de, OpenTraining
(chaosbastler/opentraining-exercises) and Wikimedia Commons.

The manifest is DaGym/Resources/Seed/exercise-photo-credits.json — one entry per seedID:

    "Front_Squats": {
        "source": "wger",                 # wger | opentraining | commons
        "author": "Everkinetic",
        "licence": "CC BY-SA 3.0",        # CC0 / Public domain / CC BY 2.0-4.0 / CC BY-SA 2.0-4.0
        "licenceURL": "https://creativecommons.org/licenses/by-sa/3.0/",
        "sourceURL": "https://wger.de/en/exercise/…/view/",
        "frames": ["https://wger.de/media/exercise-images/…-1.png", "…-2.png"]
    }

It ships in the app (the exercise detail hero reads it for its credit line) and is the single
record of every image's origin, so nothing in the photos folder is untraceable. Only licences
that allow redistribution with attribution are accepted; the importer refuses anything else.

For each entry the frames are downloaded (cached under a scratch directory), flattened onto
white, downscaled to at most 850 px wide and written as
DaGym/Resources/ExercisePhotos/<seedID>-0.heic (and -1.heic for a second frame). Then
DaGym/Resources/ATTRIBUTION-ExercisePhotos.txt and DaGym/Data/ExercisePhotoCatalog.swift are
regenerated. Re-runnable: existing .heic files are only rewritten with --force.

Images only. Nothing else from these sources — names, descriptions, metadata — is read.

Usage:
    python3 scripts/import-exercise-photos-extra.py [--cache DIR] [--force] [--only seedID…]

Needs Pillow (`pip install pillow`) for the decode/flatten step and macOS `sips` for HEIC.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CREDITS = ROOT / "DaGym" / "Resources" / "Seed" / "exercise-photo-credits.json"
PHOTOS = ROOT / "DaGym" / "Resources" / "ExercisePhotos"
ATTRIBUTION = ROOT / "DaGym" / "Resources" / "ATTRIBUTION-ExercisePhotos.txt"
CATALOG_WRITER = ROOT / "scripts" / "lib" / "write-exercise-photo-catalog.py"

ALLOWED_LICENCES = {
    "Public domain", "CC0", "CC BY 2.0", "CC BY 3.0", "CC BY 4.0", "CC BY-SA 2.0", "CC BY-SA 3.0", "CC BY-SA 4.0",
}
MAX_WIDTH = 850
QUALITY = 60
# Size ceiling per frame; the free-exercise-db pairs average ~27 KB.
MAX_BYTES = 60 * 1024
USER_AGENT = "DaGym-media-import/1.0 (+https://github.com/abdirahmanm/dagym)"

SOURCE_NAMES = {
    "wger": "wger.de (wger Workout Manager)",
    "opentraining": "OpenTraining (github.com/chaosbastler/opentraining-exercises)",
    "commons": "Wikimedia Commons",
}


def fetch(url: str, cache: Path) -> bytes:
    name = url.rsplit("/", 1)[-1]
    cached = cache / (str(abs(hash(url))) + "-" + name)
    if cached.exists():
        return cached.read_bytes()
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        data = response.read()
    cached.write_bytes(data)
    return data


def flatten_to_png(data: bytes) -> bytes:
    """Decode whatever the source served (png/jpg/webp/gif first frame), composite onto white
    — the line drawings are black on transparent and would vanish in dark mode — and cap the
    width. Returns PNG bytes for sips."""
    from PIL import Image, ImageOps  # noqa: PLC0415 — optional dependency, only needed here

    image = Image.open(io.BytesIO(data))
    image.seek(0)
    image = ImageOps.exif_transpose(image).convert("RGBA")
    background = Image.new("RGBA", image.size, (255, 255, 255, 255))
    background.alpha_composite(image)
    flat = background.convert("RGB")
    if flat.width > MAX_WIDTH:
        flat = flat.resize((MAX_WIDTH, round(flat.height * MAX_WIDTH / flat.width)), Image.LANCZOS)
    out = io.BytesIO()
    flat.save(out, format="PNG")
    return out.getvalue()


def write_heic(png: bytes, destination: Path) -> None:
    """Encode at `QUALITY`, stepping down for the few photographs that still land over
    `MAX_BYTES` — a busy gym photo at 850 px can be 150 KB at quality 60, three times the
    free-exercise-db average, and the hero is drawn at 240 pt."""
    with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as handle:
        handle.write(png)
        temp = handle.name
    try:
        for quality in (QUALITY, 45, 35, 25):
            subprocess.run(
                ["sips", "-s", "format", "heic", "-s", "formatOptions", str(quality), temp, "--out", str(destination)],
                check=True, stdout=subprocess.DEVNULL,
            )
            if destination.stat().st_size <= MAX_BYTES:
                break
    finally:
        os.unlink(temp)


def write_attribution(credits: dict) -> None:
    lines = [
        "Exercise photographs and drawings (DaGym/Resources/ExercisePhotos)",
        "",
        "Files named <seedID>-0.heic / <seedID>-1.heic are the start and end position of the",
        "seeded exercise with that id (DaGym/Resources/Seed/exercises.json).",
        "",
        "Every file NOT listed below is from yuhonas/free-exercise-db",
        "(https://github.com/yuhonas/free-exercise-db), released under the Unlicense (public",
        "domain dedication): re-encoded to HEIC and downscaled, no attribution required.",
        "",
        "The files listed below come from other open sources. Each was flattened onto white,",
        "downscaled to at most 850 px wide and re-encoded to HEIC; no other change was made.",
        "Licences: CC BY-SA 2.0/3.0/4.0 https://creativecommons.org/licenses/by-sa/,",
        "CC BY 2.0/3.0/4.0 https://creativecommons.org/licenses/by/,",
        "CC0 https://creativecommons.org/publicdomain/zero/1.0/, public domain (US government works",
        "and other works marked as such on Wikimedia Commons).",
        "Share-alike applies to these images only, not to DaGym's MIT-licensed source code.",
        "",
    ]
    for seed_id in sorted(credits):
        entry = credits[seed_id]
        files = ", ".join(f"{seed_id}-{index}.heic" for index in range(len(entry["frames"])))
        lines += [
            files,
            f"    Source:  {SOURCE_NAMES.get(entry['source'], entry['source'])}",
            f"    Author:  {entry['author']}",
            f"    Licence: {entry['licence']} ({entry['licenceURL']})",
            f"    Page:    {entry['sourceURL']}",
        ]
        lines += [f"    Image:   {url}" for url in entry["frames"]]
        lines.append("")
    ATTRIBUTION.write_text("\n".join(lines))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--cache", default=os.path.join(tempfile.gettempdir(), "dagym-photo-cache"))
    parser.add_argument("--force", action="store_true", help="rewrite .heic files that already exist")
    parser.add_argument("--only", nargs="*", default=None, help="restrict to these seedIDs")
    args = parser.parse_args()

    credits = json.loads(CREDITS.read_text())
    cache = Path(args.cache)
    cache.mkdir(parents=True, exist_ok=True)
    PHOTOS.mkdir(parents=True, exist_ok=True)

    written = skipped = 0
    for seed_id, entry in sorted(credits.items()):
        if args.only and seed_id not in args.only:
            continue
        if entry["licence"] not in ALLOWED_LICENCES:
            print(f"error: {seed_id}: licence {entry['licence']!r} is not redistributable", file=sys.stderr)
            sys.exit(1)
        if not 1 <= len(entry["frames"]) <= 2:
            print(f"error: {seed_id}: expected one or two frames", file=sys.stderr)
            sys.exit(1)
        for index, url in enumerate(entry["frames"]):
            destination = PHOTOS / f"{seed_id}-{index}.heic"
            if destination.exists() and not args.force:
                skipped += 1
                continue
            write_heic(flatten_to_png(fetch(url, cache)), destination)
            written += 1
        # A single-frame entry must not leave a stale end frame behind.
        if len(entry["frames"]) == 1:
            (PHOTOS / f"{seed_id}-1.heic").unlink(missing_ok=True)

    write_attribution(credits)
    subprocess.run([sys.executable, str(CATALOG_WRITER)], check=True)
    print(f"{len(credits)} credited exercises; wrote {written} file(s), kept {skipped}", file=sys.stderr)


if __name__ == "__main__":
    main()

# Third-party notices

The root `LICENSE` (MIT, © 2026 Abdirahman Mohamed) covers DaGym's **own** source code.
It does **not** cover the third-party material listed here, which ships in the repository
and in the app under its own terms. The same notices are reproduced in-app on the
Acknowledgements screen (`DaGym/Resources/Acknowledgements.md`).

DaGym is a *collection* that includes the CC BY-SA artwork below — not an adaptation of it —
so bundling that artwork does not place DaGym's own code under CC BY-SA.

---

## Exercise illustration artwork — CC BY-SA 4.0

**Files:** `DaGym/Resources/ExerciseArtPaths.zlib`,
`DaGym/Resources/ATTRIBUTION-ExerciseArt.txt`

Artwork by **Bryl Lim** (https://bryllim.com), derived from **Everkinetic**
(https://github.com/everkinetic/data), licensed under
**Creative Commons Attribution-ShareAlike 4.0 International**
(https://creativecommons.org/licenses/by-sa/4.0/legalcode).

`ExerciseArtPaths.zlib` contains the artwork's vector path data, modified by DaGym:
coordinates rounded to 1 decimal place; all 9,031 elliptical-arc commands across the 516
shipped frames are rendered as straight chords by the path builder; each frame is filled with
a single solid tint in place of the original fill. It is therefore an **adaptation**, and it
and any redistribution of it remain under **CC BY-SA 4.0**. See
`DaGym/Resources/ATTRIBUTION-ExerciseArt.txt` for the full notice.

## MuscleMap — MIT

**Files:** `DaGym/Vendor/MuscleMap/**` (licence text at `DaGym/Vendor/MuscleMap/LICENSE`)

Body-map figure, region path data and SVG path parser/builder from
**MuscleMap** (https://github.com/melihcolpan/MuscleMap) by **Melih Colpan**,
© 2026 Melih Colpan, MIT License.

Vendoring changes: `Muscle` renamed to `MMMuscle` to avoid colliding with GymCore's own
`Muscle` enum, and the upstream `displayName` properties plus `MMMuscle.localizationKey`
were removed (they read from SwiftPM's `Bundle.module`, which does not exist in this target).

## wger — CC BY-SA 3.0 / 4.0

**Files:** the seeded exercise data under `DaGym/Resources/Seed/`

Instruction text, muscle/equipment metadata and some exercise entries from the
**wger Workout Manager** project (https://wger.de), licensed under
**CC BY-SA 3.0/4.0**. Per-exercise author credit is stored alongside the data.

## free-exercise-db — Unlicense

**Files:** the seeded exercise data under `DaGym/Resources/Seed/`, and the start/end
photograph pairs under `DaGym/Resources/ExercisePhotos/` that are *not* listed in
`DaGym/Resources/ATTRIBUTION-ExercisePhotos.txt`

Exercise names, muscles and equipment metadata, and the start/end position photographs,
adapted from **yuhonas/free-exercise-db** (https://github.com/yuhonas/free-exercise-db),
released under the **Unlicense** (public-domain dedication). Photographs are re-encoded to
HEIC and downscaled.

## wger.de exercise images — CC BY-SA 3.0 / 4.0

**Files:** the files under `DaGym/Resources/ExercisePhotos/` listed with source "wger.de" in
`DaGym/Resources/ATTRIBUTION-ExercisePhotos.txt`; manifest in
`DaGym/Resources/Seed/exercise-photo-credits.json`

Drawings and photographs uploaded to https://wger.de by its contributors (including
Everkinetic line drawings), each **CC BY-SA 3.0** or **CC BY-SA 4.0** as recorded by wger and
credited per file (author, licence, source page, original image URL). Flattened onto white,
downscaled to ≤ 850 px and re-encoded to HEIC; no other change. Imported by
`scripts/import-exercise-photos-extra.py`.

## Wikimedia Commons photographs — public domain / CC0 / CC BY / CC BY-SA

**Files:** the files under `DaGym/Resources/ExercisePhotos/` listed with source
"Wikimedia Commons" in `DaGym/Resources/ATTRIBUTION-ExercisePhotos.txt`

A handful of photographs of movements no other source covered, each public domain, CC0,
CC BY 2.0/3.0/4.0 or CC BY-SA 2.0/3.0/4.0 as marked on its Commons file page and credited per
file. Downscaled and re-encoded; no other change.

## Generated exercise line-art — MIT (DaGym's own)

**Files:** `DaGym/Resources/ExerciseFrames/**`,
`DaGym/Resources/ATTRIBUTION-ExerciseFrames.txt`

Not third-party: three-frame line-art for 218 exercises generated for DaGym (Gemini 3.1
Flash Image via OpenRouter, September 2026), owned by the project and covered by the root
MIT `LICENSE`. Listed here so the origin of every image folder is recorded in one place.

## Barlow / Barlow Condensed — SIL Open Font License 1.1

**Files:** `DaGym/Resources/Fonts/**` (licence text at `DaGym/Resources/Fonts/OFL.txt`)

Typefaces by **Jeremy Tribby**, licensed under the
**SIL Open Font License, Version 1.1** (https://openfontlicense.org).

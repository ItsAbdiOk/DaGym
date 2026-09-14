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

**Files:** the seeded exercise data under `DaGym/Resources/Seed/`

Exercise names, muscles and equipment metadata adapted from
**yuhonas/free-exercise-db** (https://github.com/yuhonas/free-exercise-db),
released under the **Unlicense** (public-domain dedication).

## Barlow / Barlow Condensed — SIL Open Font License 1.1

**Files:** `DaGym/Resources/Fonts/**` (licence text at `DaGym/Resources/Fonts/OFL.txt`)

Typefaces by **Jeremy Tribby**, licensed under the
**SIL Open Font License, Version 1.1** (https://openfontlicense.org).

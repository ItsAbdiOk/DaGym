# Acknowledgements

DaGym is built with the help of the following open-source data, fonts, and libraries.

## Exercise data

**wger** — instruction text, muscle/equipment metadata, and some exercise entries are sourced
from [wger.de](https://wger.de) (the wger Workout Manager project), licensed under
**Creative Commons Attribution-ShareAlike 3.0/4.0 (CC-BY-SA)**. Per-exercise author credit is
stored alongside the data. Licence: https://creativecommons.org/licenses/by-sa/4.0/deed.en

> Exercise data from wger.de (wger Workout Manager), licensed under CC-BY-SA 3.0/4.0 —
> https://wger.de. Per-exercise author credit in the app's exercise data.

**free-exercise-db** — exercise names, muscles, and equipment metadata, *and* the start/end
position photographs shown on the Exercise Detail screen, are adapted from
[yuhonas/free-exercise-db](https://github.com/yuhonas/free-exercise-db), released under the
**Unlicense** (public domain dedication). The photographs are re-encoded to HEIC and downscaled
for the app; no attribution is legally required and none is shown in-app, but the credit is
recorded here.

> Exercise metadata and exercise photographs adapted from yuhonas/free-exercise-db
> (https://github.com/yuhonas/free-exercise-db), released under the Unlicense.

**Everkinetic** — some exercise illustrations surfaced via wger's image data are credited to
Everkinetic (https://github.com/everkinetic/data), licensed under **CC-BY-SA 4.0**.

> Illustration by Everkinetic (https://github.com/everkinetic/data), CC-BY-SA 4.0.

## Exercise photographs from other open sources

A few dozen exercises show a photograph or drawing that does not come from free-exercise-db.
Each one is listed, with its author, licence and source page, in
`DaGym/Resources/ATTRIBUTION-ExercisePhotos.txt` (bundled with the app) and credited under the
picture on the Exercise Detail screen when its licence asks for that.

**wger.de exercise images** — drawings and photographs uploaded to
[wger.de](https://wger.de) by its contributors (Everkinetic line drawings among them), each
licensed **CC BY-SA 3.0** or **CC BY-SA 4.0** by its uploader. Flattened onto white, downscaled
and re-encoded to HEIC; no other change.

> Exercise images from wger.de contributors, CC BY-SA 3.0 / 4.0 — author named per image.

**Wikimedia Commons** — a handful of photographs of movements no other source covered, each
public domain, **CC0**, **CC BY 2.0 / 3.0 / 4.0** or **CC BY-SA 2.0 / 3.0 / 4.0** as marked on
its Commons file page. Downscaled and re-encoded; no other change.

> Photographs via Wikimedia Commons — author and licence named per image.

Some exercises that have no picture of their own show the picture of another seeded exercise
that is the same movement (a two-handed kettlebell swing shows the kettlebell swing). That
mapping is `DaGym/Resources/Seed/exercise-media-aliases.json`; the credit shown always belongs
to the picture on screen.

## Exercise illustrations

**Bryl Lim** — the animated 3-frame exercise illustrations shown throughout the app are by
[Bryl Lim](https://bryllim.com), derived from Everkinetic (https://github.com/everkinetic/data),
licensed under **Creative Commons Attribution-ShareAlike 4.0 International (CC BY-SA 4.0)**.
Licence: https://creativecommons.org/licenses/by-sa/4.0/deed.en

DaGym does not ship the source SVGs. Each frame's vector path data is extracted and rendered
as a native shape. **Three changes were made to the licensed material:**

1. **Coordinate precision** — every decimal coordinate in the path data is rounded to 1 decimal
place, against the artwork's 512×512 coordinate space.

2. **Elliptical arcs are flattened** — the renderer DaGym uses draws every SVG elliptical-arc
command as a straight line to the arc's end point, so all 9,031 arcs across the 516 shipped
frames are drawn as straight chords rather than curves. Curved details are subtly flattened.

3. **Colour** — each frame is filled with a single solid colour (near-black in light appearance,
near-white in dark appearance), replacing the artwork's original fill. It does not follow the
accent colour.

No other changes were made to the linework.

These changes make the shipped path data an adaptation, so the artwork stays under CC BY-SA 4.0:
redistributing it, inside DaGym or on its own, means carrying this same attribution and offering
the artwork under CC BY-SA 4.0. That applies to the **artwork and its path data only** — DaGym's
own source code is MIT-licensed and is not relicensed by shipping this artwork alongside it.

> Exercise illustrations by Bryl Lim (https://bryllim.com), derived from Everkinetic
> (https://github.com/everkinetic/data), licensed under CC-BY-SA 4.0. Modified by DaGym:
> coordinates rounded to 1 decimal place, elliptical arcs drawn as straight chords, and
> recoloured to a single solid tint.

## Muscle diagrams

**MuscleMap** — the body map's anatomical figure and muscle-region outlines are adapted from
[MuscleMap](https://github.com/melihcolpan/MuscleMap) by Melih Colpan, licensed under the
**MIT License**. DaGym vendors part of the package's source (the SVG path data, its parser, and
its path builder); the `Muscle` enum was renamed to `MMMuscle` to avoid a name collision, and a
few members that depend on SwiftPM's `Bundle.module` were removed. Its full licence notice:

MIT License

Copyright (c) 2026 Melih Colpan

Permission is hereby granted, free of charge, to any person obtaining a copy of this software
and associated documentation files (the "Software"), to deal in the Software without
restriction, including without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or
substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING
BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM,
DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## Typography

**Barlow / Barlow Condensed** — the app's typeface, designed by Jeremy Tribby, is licensed under
the **SIL Open Font License 1.1**. Full licence text: https://openfontlicense.org

> Barlow and Barlow Condensed typefaces by Jeremy Tribby, licensed under the SIL Open Font
> License, Version 1.1.

## Licence notes

CC-BY-SA, CC-BY, CC0, the Unlicense, the MIT terms above and the SIL Open Font License apply to
the data, artwork, photographs, vendored code and fonts listed here — not to DaGym's own source code, which is
MIT-licensed. DaGym is a collection that includes the CC BY-SA artwork; it is not an adaptation
of it, so bundling that artwork does not place the app's own code under CC BY-SA.

The project repository (public, MIT) carries a THIRD-PARTY.md with the same breakdown, plus
docs/exercise-data-sources.md for the full research and share-alike rationale.

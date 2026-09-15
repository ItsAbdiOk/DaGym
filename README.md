# DaGym

DaGym is a free, open-source strength-training and gym-logging app for iPhone and Apple
Watch. No account, no ads, no subscription. Your data lives in SwiftData on-device and syncs
between your own devices through your private iCloud (CloudKit) database — the developer
never sees it, and there is no server.

- iOS 26+, watchOS 26+
- SwiftData + CloudKit private database (sync between your own devices only)
- On-device only: no analytics, no tracking, no backend

## Features

- Workout logging: strength sets, cardio (time/distance/pace/incline), supersets and timed
  holds, PR detection and progression suggestions
- Routines and programs, with a schedule that can sync to a dedicated "DaGym" calendar
- Rest timer with a Lock Screen / Dynamic Island Live Activity
- Home, History and Progress screens, with a body/muscle map
- Voice logging (on-device speech recognition — nothing leaves the phone)
- Progress photos (local by default, optionally lockable behind Face ID)
- Apple Health integration: reads bodyweight, body composition, HRV/RHR/sleep and imported
  workouts to personalise suggestions; writes strength workouts and bodyweight back
- Standalone Apple Watch app that can log a full workout on its own, plus watch
  complications/Smart Stack widgets
- iPhone widgets: today's workout, streak, and the rest-timer Live Activity
- Import workouts from Hevy
- Shareable `.gymplan` routine/program files
- Colour-blind-friendly heatmaps, Dynamic Type and accessibility pass throughout

## Building

Requirements: Xcode 27, a Mac.

```sh
brew install xcodegen swiftlint
xcodegen generate
./scripts/verify.sh
```

[`project.yml`](project.yml) is the source of truth for the Xcode project — run `xcodegen
generate` again after adding or moving files, and before opening `DaGym.xcodeproj`.
`scripts/verify.sh` lints, runs the GymCore unit tests, and runs the app + UI test suites on
a simulator; it's the same check the pre-push hook runs.

Schema changes: `scripts/cloudkit-schema.sh` (dry run) then `--deploy`.

To have the pre-push hook run automatically:

```sh
git config core.hooksPath .githooks
```

## Project structure

- `DaGym/` — the iPhone app
- `DaGymWidgets/` — iOS widget extension (rest-timer Live Activity, Home Screen widgets)
- `DaGymWatch/` — the standalone watchOS app, plus `DaGymWatch/Widgets` (complications /
  Smart Stack)
- `GymCore/` — pure Swift package for training math and logic (no UI, no SwiftData), tested
  independently with `swift test`

## Licence

DaGym's own source code is MIT-licensed — see [LICENSE](LICENSE).

The repository and app also bundle third-party material under their own licences, including:

- Body-map figure and path data from [MuscleMap](https://github.com/melihcolpan/MuscleMap)
  (MIT)
- Exercise metadata from [free-exercise-db](https://github.com/yuhonas/free-exercise-db)
  (Unlicense) and [wger](https://wger.de) (CC BY-SA)
- Exercise illustration artwork by [Bryl Lim](https://bryllim.com), derived from
  [Everkinetic](https://github.com/everkinetic/data) (CC BY-SA 4.0)
- Barlow / Barlow Condensed typefaces by Jeremy Tribby (SIL Open Font License 1.1)

Full attribution, including which files are covered and what was modified, is in
[THIRD-PARTY.md](THIRD-PARTY.md) and reproduced in-app on the Acknowledgements screen.

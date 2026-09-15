# Contributing

Thanks for looking at DaGym. A few ground rules to keep this easy to maintain:

- **Lint is strict.** `swiftlint lint --strict` must be clean before you open a PR — it
  ignores `.md`/`.yml` files, so this doc and CI config don't need to pass it.
- **Tests are [Swift Testing](https://developer.apple.com/documentation/testing)**, not
  XCTest. New tests should use `@Test`/`#expect`, matching the existing suites.
- **The gate must be green.** Run `./scripts/verify.sh` before pushing (the pre-push hook
  runs it automatically once you `git config core.hooksPath .githooks`). It lints, runs
  `GymCore`'s unit tests, and runs the app + UI tests on a simulator.
- **`project.yml` is the source of truth** for the Xcode project. If you add, move or remove
  a file, run `xcodegen generate` and commit the regenerated `DaGym.xcodeproj`,
  `Info.plist`s and entitlements — don't hand-edit the `.xcodeproj`.
- **No AGPL (or otherwise copyleft-incompatible) code or dependencies.** DaGym's own code is
  MIT-licensed; anything you bring in has to be compatible with that, and any new third-party
  material needs an entry in `THIRD-PARTY.md` with a real attribution, not just a licence
  name.
- **One PR per change.** Keep pull requests scoped to a single fix or feature — it makes
  review and revert both easier.

## Getting set up

```sh
brew install xcodegen swiftlint
xcodegen generate
./scripts/verify.sh
```

See [README.md](README.md) for the full build instructions and project layout.

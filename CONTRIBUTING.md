# Contributing to Ithil

Thanks for helping! Ithil is a small, focused app: a fast, offline, private calendar for students, where every
event can have files in real Finder folders. **Reliability beats features**, so the bar for changes that touch
people's data is high, and the bar for new features is "does this make Ithil better for students without
making it heavier?".

By taking part you agree to follow the [Code of Conduct](CODE_OF_CONDUCT.md).

## Before you start

- **Bugs:** open an issue with the bug template. Steps to reproduce help more than anything.
- **Features:** open an issue with the feature template first, so we can agree on the idea before you spend
  time on code.
- **Security problems:** don't open an issue; see [SECURITY.md](SECURITY.md).

## Building

You need macOS 14 or later and Xcode 26.

```sh
git clone https://github.com/Visaug36/Ithil.git
cd Ithil
open Ithil.xcodeproj
```

Press ⌘R to run and ⌘U to test. To try Ithil with sample data that never touches your own calendar, edit the
scheme (Product → Scheme → Edit Scheme… → Run → Arguments) and enable `-demo`. Add `-demoNow 2026-10-06T13:50` to
pin the clock to the design's sample week.

From the command line:

```sh
xcodebuild test -project Ithil.xcodeproj -scheme Ithil -destination 'platform=macOS'
scripts/install.sh          # builds Release and copies it to /Applications
```

## How the code is organized

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full picture and [docs/DESIGN.md](docs/DESIGN.md) for
the look. In short:

- `IthilCore/`: all logic, in plain Swift (dates, recurrence, storage, folder naming, file operations, Quick Add
  parsing, alert planning). No SwiftUI, no AppKit, no user-facing strings. Everything here is tested.
- `Ithil/`: the SwiftUI app, AppKit glue and every user-facing string (in `Localizable.xcstrings`).
- `IthilCoreTests/`: Swift Testing tests for `IthilCore`.

## Rules for changes

- **No third-party dependencies**, no network access, no analytics. The sandbox has no network entitlement on
  purpose.
- **Never risk user data.** Copy files, never move them; never delete permanently (use the Trash); never write
  outside the user's Ithil folder; keep `events.json` writes atomic and keep backups working.
- **The main thread never waits on disk.**
- **All date math goes through `Calendar`**, with an explicit time zone. Test DST and time zone changes.
- **Zero warnings.** CI builds with warnings as errors.
- **Format with swift-format** (it ships with Xcode): `xcrun swift-format format --in-place --recursive Ithil IthilCore IthilCoreTests`.
  CI runs `swift-format lint --strict`.
- **Every user-facing string is localizable** and lives in `Ithil/Localizable.xcstrings`.
- **Accessibility:** VoiceOver labels on every control, full keyboard access, respect Reduce Motion and Increase
  Contrast, and keep text at WCAG AA contrast in both Night and Dawn.
- **Tests:** logic changes in `IthilCore` come with Swift Testing tests. Tests must not depend on the machine's
  time zone, locale or the current date.
- **Design:** use the tokens from the asset catalog and `Ithil/Theme/`, not new colors or sizes.

## Pull requests

1. Fork, then branch from `main`.
2. Keep each pull request to one change, with a clear description and screenshots for anything visible
   (Night and Dawn).
3. Make sure `xcodebuild test` passes and swift-format is clean. CI checks both, plus a universal Release build.
4. Add a line to the `[Unreleased]` section of [CHANGELOG.md](CHANGELOG.md).

## License

By contributing you agree that your contributions are licensed under the [MIT License](LICENSE).

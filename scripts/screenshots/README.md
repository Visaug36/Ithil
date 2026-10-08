# README screenshots

The images in `docs/images/` are taken from the `-demo` build by `capture.sh`: five fresh launches with the sample
week, the clock pinned to Tuesday 6 October 2026, 13:50, in British English like the design. Your own calendar,
folder and settings are never touched.

- **On GitHub:** run the **Screenshots** workflow from the Actions tab. It sets the runner's display to
  1920×1080, takes the shots and commits them to the branch it ran on. It also runs on its own when this folder
  changes on a `claude/**` branch.
- **On your Mac:** build Release, then run
  `scripts/screenshots/capture.sh path/to/Ithil.app docs/images`. macOS asks Terminal for Screen Recording
  permission the first time. It quits any running Ithil before each shot. Quick Add reads "thursday" against
  your Mac's real date (the workflow sets the runner's clock to the demo's for that shot), so its date can
  differ from the published one.

The scenes come from the demo launch arguments (see `Ithil/App/DemoScene.swift`): `-demoAppearance night|dawn`,
`-demoSpan day|week|month`, `-demoScene details|quickAdd` and `-demoWindowSize 1280x800`.

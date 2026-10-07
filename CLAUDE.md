# Ithil

Save this brief as CLAUDE.md in the repo root, follow it in every session, and keep it updated as we make decisions.

You're building Ithil, a native macOS calendar for students, as a public open-source GitHub repo named "Ithil". It's fast, offline and private, feels like it shipped with the Mac, and every event can have files attached that live in real Finder folders. Reliability beats features.

## Start here
1. This folder has Ithil.xcodeproj (made with Xcode's New Project wizard; create one if it's missing) and Ithil__Offline_Student_Calendar.zip, the Claude Design export.
2. Before anything else, add design-reference/ and *.zip to .gitignore, then unzip the export into design-reference/. It must never be committed: it contains a reference photo that isn't ours to publish.
3. Read design-reference/Ithil.dc.html. It's the source of truth for the look: palette (SUBJ and BASE in its script), app icon option 1a, empty-state illustrations, every screen, and a Handoff section mapping screens to SwiftUI with type, spacing, radii and SF Symbols. Move everything the app needs into the asset catalog (colors with Night = dark / Dawn = light variants, app icon at all sizes, SVG illustrations, a static star-field image) and into docs/DESIGN.md, so the repo never depends on the export.
4. Check my setup (macOS and Xcode versions, gh auth status), then show me a plan for Phase 1 and wait for my OK.

## Architecture
- Swift + SwiftUI, macOS 14+, universal binary (Apple Silicon + Intel). No third-party packages.
- Logic (dates, recurrence, storage, folder naming, file operations) lives in plain Swift types separate from views. Notifications, file system and clock sit behind small protocols so everything is unit-testable and runs on CI.
- App Sandbox and Hardened Runtime on. Entitlements: user-selected read-write files and app-scope bookmarks only. No network entitlement, so the sandbox blocks the app from ever going online.
- Global Quick Add hotkey via Carbon RegisterEventHotKey (sandbox-safe, no permission prompts). Default ⌥Space, changeable in Settings since other apps use it too.
- os.Logger for logs; event titles and file names are always .private.

## Data
- Root folder chosen on first launch (suggest ~/Documents/Ithil), kept as a security-scoped bookmark. If the user picks a non-empty folder that isn't an Ithil folder, create an Ithil subfolder inside it. If the folder goes missing (moved, deleted, drive unplugged), show a clear "Locate or choose folder" screen; never crash or quietly start empty. Changing the folder in Settings offers to move everything there.
- Events live in <root>/.ithil/events.json: schema version with migrations, atomic writes, rolling backups, plus a safety copy in Application Support. A corrupt file is recovered from the newest good backup and the user is told. Copying the root folder is a full backup; opening an existing Ithil folder on a new Mac restores everything.
- Timed events store an absolute time plus time zone; all-day events store a plain date, so nothing shifts when traveling.
- All date math via Calendar/DateComponents (DST, leap years, month edges). Handle midnight rollover, time zone changes and sleep/wake.
- Display follows the user's locale (12/24h, date format, first weekday, with a Settings override). Folder names are always yyyy-MM-dd and HH.mm.

## Features (match the design)
1. Week (default), Day and Month views. Sidebar: mini month, Up next, Subjects with visibility toggles. Toolbar: ‹ Today ›, Day/Week/Month, search (titles, locations, notes), +.
2. Events: title, date, time or all-day, subject, location, alert, repeat (never/daily/weekly/monthly; edit this event or all future ones), notes.
3. Quick Add floating panel (⌥Space anywhere, ⌘N in the app): parse "physics quiz thursday 10am" with NSDataDetector plus subject keyword matching. ↩ adds, ⌘↩ adds and opens the editor, esc closes.
4. Subjects: users create their own, with colors from the design's palette plus a custom color, managed in Settings. The subjects and events in the design are sample data for -demo only.
5. Notifications (UserNotifications): per-event alert plus a default in Settings, and they must fire while Ithil is quit. Title "{Title} in 10 min", body "time · location · N files", with an "Open Files" action that opens the event's folder. Schedule only the nearest upcoming alerts and reschedule on launch, on every change, on wake and on time zone change. Explain before asking for permission; if it's denied, show how to turn it on.
6. Files:
   - <root>/yyyy-MM-dd/HH.mm Title/ per event; each occurrence of a repeating event gets its own. Create folders only when the first file arrives.
   - Drop files on an event (block, editor or details) or use Add Files: copy, never move the originals, in the background with progress. Name clashes get " 2" like Finder.
   - The folder is the source of truth: show what's in it and watch for changes so Finder edits appear live.
   - Renaming or rescheduling an event renames or moves its folder. A hidden marker file with the event ID lets Ithil find the folder even if it's renamed in Finder.
   - Deleting an event moves its folder to the Trash (confirm first if it has files). Never delete permanently.
   - Sanitize folder names (no / or :, no leading dots, length limit). Nothing may ever be written outside the root folder.
   - Space opens Quick Look, double-click opens the file, plus Show in Finder.
7. Menu bar extra (moon.fill template icon): today, the next event with Open Files, Quick Add, Open Ithil, Settings, Quit. Can be turned off in Settings.
8. Settings (General / Subjects / Files): appearance Night / Dawn / Match System, default alert, first weekday, Quick Add hotkey, folder, launch at login (SMAppService), menu bar.
9. First-launch onboarding, 3 short steps in the app's style: welcome, choose folder, notifications.
10. Keyboard: ⌘N, ⌘T today, ←/→, ⌘1/2/3, ⌘F, Delete, ⌘Z / ⇧⌘Z; drag events to move or resize; everything reachable by keyboard.
11. About window with version, license and GitHub link. Help menu: "Check for Updates…" and "Report an Issue…" open the GitHub pages in the browser (the app itself never touches the network).

## Quality bar
- No lag: launches in under a second; switching weeks and months stays instant with 5,000 events; the main thread never waits on disk; copying a 2 GB file never freezes the UI. Stars and glows are static assets, nothing animated behind the grid.
- Accessibility: VoiceOver labels everywhere (e.g. "Physics Lecture, 2 to 3:30 PM, 4 files"), full keyboard access, respects Reduce Motion and Increase Contrast, text meets WCAG AA contrast in both themes.
- Localization-ready: every string in a String Catalog, English first.
- Looks right on macOS 14 through the latest, including the Liquid Glass look on macOS 26+, in both Night and Dawn.
- Tests (Swift Testing) for date math, DST, recurrence, time zones, quick-add parsing, folder naming and sanitizing, file copy/rename/trash, storage migrations and corruption recovery.
- Zero warnings. Format with swift-format (ships with Xcode).
- A -demo launch argument loads sample data into a temporary folder for screenshots and testing, never touching real data.

## Public repo
- MIT license with my name (ask me). Bundle ID io.github.<my GitHub username>.Ithil.
- README.md: icon, one-line pitch, screenshots, features, download + first-launch steps (the app isn't notarized, so explain System Settings → Privacy & Security → Open Anyway), build from source, how files are stored (folder tree), keyboard shortcuts, privacy (no network, no analytics, no dependencies, everything stays in your folder), backup and moving to a new Mac, uninstall, FAQ (notifications not showing, folder missing), contributing, license, and a note that "Ithil" is Tolkien's Sindarin word for moon and the project isn't affiliated with the Tolkien Estate.
- CONTRIBUTING.md, CODE_OF_CONDUCT.md (Contributor Covenant), SECURITY.md (GitHub private vulnerability reporting), CHANGELOG.md (Keep a Changelog + SemVer), issue templates (bug, feature), PR template, Dependabot for GitHub Actions, docs/DESIGN.md, docs/RELEASE_CHECKLIST.md (manual test pass before each release).
- CI (GitHub Actions): build and run tests on every push and PR, with Xcode pinned as close to mine as the runners allow.
- Release workflow on vX.Y.Z tags: universal Release build → zip with ditto + SHA-256 → GitHub Release with notes from CHANGELOG. Ad-hoc signed by default; if Developer ID and notarization secrets are present, sign, notarize and staple automatically (document how to add them later).
- scripts/install.sh builds Release locally and copies it to /Applications.
- A 1280×640 social preview image in docs/ made from the design (I'll upload it in the repo settings). Set the repo description and topics with gh.
- Never commit: design-reference/, the zip, secrets, personal info, absolute paths, xcuserdata, DerivedData. Check the git history before the first push.

## How to work
- Build in phases. Stop after each so I can test, then commit:
  1. Repo and project setup, design tokens in the asset catalog, CI green on an empty window.
  2. Calendar core: data, storage, views, events, quick add, subjects, appearance.
  3. Notifications.
  4. Files and folders.
  5. Polish: menu bar, hotkey, onboarding, settings, keyboard, undo, accessibility.
  6. Release prep: README with real screenshots (via -demo), docs, release workflow. Get v1.0.0 ready, but don't tag or publish until I say so.
- Run xcodebuild after every change and fix all errors and warnings before calling a phase done.
- Create the public GitHub repo "Ithil" with gh when Phase 1 is green (confirm with me first) and push after each phase.
- If a product decision is unclear, ask me instead of guessing.

## Decisions & status log
Keep this section current. Newest first.

### Decisions
- **Working mode (user, 2026-10-06):** "do everything yourself". Claude merges each finished phase into `main` itself (PR from `claude/laughing-ride-8gg5eo`, merge commit, after CI is green) and moves on to the next phase without waiting for the user to test. Still: never tag or publish v1.0.0 until the user says so.
- **License / identity:** MIT, copyright "Visaug36" (the user didn't mind which name). Bundle ID `io.github.visaug36.Ithil`. Repo: https://github.com/Visaug36/Ithil, public from the start.
- **Design source:** the user sent the design as a PDF instead of the zip. It lives only in `design-reference/Ithil.pdf` (git-ignored, along with renders). Containers are ephemeral, so if it's missing, ask the user to upload it again. `docs/DESIGN.md` must stay complete enough to build every screen without it.
- **Project layout:** `Ithil.xcodeproj` (objectVersion 77, file-system-synchronized folders, so new files are picked up without editing the project). Targets: `Ithil` (app), `IthilCore` (static framework for all logic: dates, recurrence, storage, folder naming, file ops), `IthilCoreTests` (Swift Testing, not hosted, so it runs without launching the app). IthilCore is static so ad-hoc-signed builds don't trip hardened-runtime library validation. User-facing strings live in the app's `Localizable.xcstrings`, not in IthilCore.
- **Build settings:** Swift 6 language mode, macOS 14.0 deployment target, universal Release build. Signing defaults to ad-hoc ("Sign to Run Locally", `CODE_SIGN_IDENTITY = -`, Manual, no team). Sandbox, user-selected read-write and app-scope bookmark entitlements are in `Config/Ithil.entitlements`, plus Hardened Runtime. No network entitlement.
- **Color tokens:** named `BackgroundWindow/Sidebar/Raised/Menu`, `Text*`, `Accent*`, `ControlFill`, `SeparatorLine`, `Subject{Clay,Teal,Iris,Fern,Rose}` (not `WindowBackground`, which clashes with SwiftUI's `.windowBackground`). `TextTertiary` and Dawn `AccentText` were adjusted from the design to pass WCAG AA (see docs/DESIGN.md).
- **Assets:** the app icon (option 1a) was rasterized from the design PDF at 600 dpi and masked onto Apple's 824/1024 grid. The illustrations were redrawn as plain SVG (no masks or filters). The star field is a generated, seeded 512 pt tile.
- **CI:** GitHub Actions on `macos-26` with the newest stable Xcode 26.x on the runner (26.6 as of 2026-10-06; the user doesn't know their own versions, so this is the pin). Runs swift-format lint (strict), Debug tests, and a universal Release build (checked with `lipo`). It fails on any warning (`scripts/check-warnings.sh` + `SWIFT_TREAT_WARNINGS_AS_ERRORS`).
- **Environment:** Claude works in a Linux cloud container without Xcode, so GitHub Actions is the build-and-test loop. `gh` isn't authenticated there; GitHub is reached through git and the GitHub connector.
- **How work is done:** the API contract for each module goes in `docs/ARCHITECTURE.md` first. Then parallel engineers implement against it, independent reviewers fix in place, an integration pass follows, and CI on the pushed branch is the compiler. Prefer reading CI failures from the xcresult summary (the "Show test failures" step) and swift-format's printed patch.
- **Product rules decided along the way:**
  - Monthly repeats skip months without that day (like Calendar.app and RFC 5545).
  - All-day alerts are relative to 09:00 local.
  - All-day event folders have no time prefix (`2026-10-14/Mara's birthday`). Timed folders use HH.mm in the event's own time zone.
  - Quick Add with no date means today, all day; "due friday" keeps "due" in the title.
  - Deleting a series' future events moves only those occurrences' folders to the Trash.
  - Edits carry folders along and never trash them.
- **Strings:** `xcodebuild` does not sync the String Catalog, so `Localizable.xcstrings` is kept up to date by hand or script. CI's `scripts/check-strings.sh` runs `xcstringstool sync` on a copy and fails when code uses a string the catalog lacks.
- **Dependabot PRs** for Actions are taken over on the working branch (checkout/upload-artifact are already on v7).
- **Demo mode** never schedules real notifications and never touches the real bookmark or settings. `-demoNow` only works together with `-demo`.
- **README screenshots** come from the Screenshots workflow (`scripts/screenshots/`): `-demo` scenes (`-demoAppearance`, `-demoSpan`, `-demoScene details|quickAdd`, `-demoWindowSize`) at 1280×800, in en_GB like the design, on a runner switched to 1920×1080 with displayplacer. It commits `docs/images/*.png` to the branch it ran on, so pull before pushing after a run. On the runner SwiftUI doesn't open the main window at launch, so the script reopens the app (like a Dock click).
- **Time grid scrolling** goes through `TimeGridScroller` (sets the enclosing `NSScrollView`'s position). `ScrollViewReader` never found the hour targets inside the lazy, pinned-header stack, so the grid always opened at midnight.
- **Version:** `MARKETING_VERSION` is 1.0.0 and CHANGELOG has `## [1.0.0] - 2026-10-07`. Update that date when the user says to tag.

### Open items
- Liquid Glass app icon for macOS 26 (an Icon Composer `.icon` file). The legacy AppIcon set still works.
- Needs a check on a real Mac (CI can't drive the UI):
  - Can the sandboxed app move a folder back out of `~/.Trash` when a delete is undone? If not, it shows an error and the folder stays in the Trash.
  - Do click, double-click and drop still work together with drag-to-move and the resize handle?
  - Do the Increase Contrast colors apply when Night or Dawn is forced?
  - Does ⌘F reach Ithil's Find… item?
  - Does launching Ithil open its main window? On the CI runner it doesn't until the app is reopened.
  - Does the time grid open at 08:00 (or an hour before now), and does Quick Add's ⌘↩ scroll to the new event?
- Merges made through GitHub carry the account's name and email. The user can turn on "Keep my email addresses private" in GitHub's email settings to use the noreply address for future ones.

### Status
- 2026-10-07: **Phase 6 (release prep)**: README with real screenshots, String Catalog check in CI, version 1.0.0, screenshot workflow, time grid scroll fix. Not tagged; waiting for the user's go-ahead to release.
- 2026-10-07: **Phase 5 done, CI green** (326 tests, zero warnings, universal build): menu bar, global hotkey, onboarding, launch at login, undo/redo, drag to move and resize, Delete and ⌘F, About and Help, Increase Contrast, Liquid Glass rim on Quick Add.
- 2026-10-07: **Phases 3 and 4 merged** (https://github.com/Visaug36/Ithil/pull/5): notifications and files in the app, plus the Phase 6 release tooling and community files. CI green: 312 tests, zero warnings, universal build. Next: Phase 5 (polish).
- 2026-10-06:
  - Phase 2 merged (https://github.com/Visaug36/Ithil/pull/4), together with the Phase 3 and 4 IthilCore logic: 312 tests, zero warnings, universal build.
  - Release workflow, `scripts/install.sh`, community files, issue and PR templates, `docs/RELEASE_CHECKLIST.md` and `docs/social-preview.png` were added on the branch.
- 2026-10-06: Phase 1 merged (https://github.com/Visaug36/Ithil/pull/1).

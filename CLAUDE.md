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

- 2026-10-06 — Session 1 (cloud container, Linux, no Xcode/Swift): saved this brief and `.gitignore`.
  - The GitHub repo already exists at `Visaug36/Ithil`, so "create the repo with gh" is done; it only contains a stub README. Visibility still to confirm.
  - Not present in the repo: `Ithil.xcodeproj` and `Ithil__Offline_Student_Calendar.zip`. The zip must never be committed, so it has to reach a session some other way (see Phase 1 plan open questions).
  - `xcodebuild` can't run in a Linux container; macOS builds must happen on the user's Mac or on GitHub Actions macOS runners.
  - Pending answers: name for the MIT license; bundle ID (proposed `io.github.visaug36.Ithil`); user's macOS and Xcode versions.

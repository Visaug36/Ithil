# Release checklist

Do this whole pass on a real Mac before tagging a release. Use a **fresh macOS user account** (or a fresh
`~/Documents/Ithil`) for first-launch checks, and your normal account for the rest. Test both **Night** and
**Dawn**, and if you can, both an Apple silicon and an Intel Mac (or Rosetta: Get Info → Open using Rosetta).

## 0. Before you start

- [ ] `main` is green in CI (lint, tests, universal Release build, zero warnings).
- [ ] `CHANGELOG.md` has a `## [X.Y.Z] - YYYY-MM-DD` section; `[Unreleased]` is empty or gone.
- [ ] The version you'll tag (`vX.Y.Z`) matches the changelog. The release workflow sets `MARKETING_VERSION`
      from the tag.
- [ ] Build a Release locally: `scripts/install.sh --open`.

## 1. First launch and onboarding

- [ ] The three onboarding steps (welcome, choose folder, notifications) look right in Night and Dawn.
- [ ] "Create Ithil Folder…" suggests `~/Documents/Ithil` and creates it.
- [ ] Choosing a **non-empty folder** that isn't an Ithil folder creates an `Ithil` subfolder inside it.
- [ ] Choosing an **existing Ithil folder** (copied from another Mac) restores every event, subject and file.
- [ ] Notifications are explained before macOS asks. Denying them shows how to turn them on later.
- [ ] Quit and reopen: the folder is remembered (security-scoped bookmark) and no prompt appears.

## 2. Calendar

- [ ] Week view is the default. Day (⌘1), Week (⌘2), Month (⌘3), Today (⌘T) and ←/→ all work.
- [ ] The now line moves and the today markers update past midnight (leave Ithil open across midnight, or change
      the clock).
- [ ] Switching weeks and months is instant with a large library (use `-demo`, or import ~5,000 events).
- [ ] The mini month, Up next and the subject toggles work; hidden subjects disappear everywhere.
- [ ] Search finds titles, locations and notes; "no results" shows the lantern empty state.
- [ ] System Settings → General → Language & Region: switching 12/24-hour time and the first weekday is followed;
      the Settings override for the first weekday wins.

## 3. Events

- [ ] Create, edit and delete timed and all-day events (popover editor and ⌘N Quick Add).
- [ ] Quick Add: "physics quiz thursday 10am" gives Physics Quiz, Thursday 10:00–11:00, subject Physics.
      ↩ adds, ⌘↩ adds and opens the editor, esc closes. ⌥Space works from another app.
- [ ] Repeating events: daily, weekly, monthly (on the 31st it skips short months). Edit and delete with both
      "This Event Only" and "All Future Events".
- [ ] Drag events to move and resize; ⌘Z / ⇧⌘Z undo and redo.
- [ ] Travel: change the Mac's time zone. Timed events keep their absolute time, all-day events keep their dates,
      and the HH.mm in folder names doesn't change.
- [ ] DST: a weekly 14:00 event stays at 14:00 the week after a DST change.

## 4. Files and folders

- [ ] Drop files on an event block, in the editor and in the details popover: they're **copied** (the originals
      stay), with progress for large files. A 2 GB file doesn't freeze the UI.
- [ ] The folder appears at `<root>/yyyy-MM-dd/HH.mm Title/` only once the first file arrives.
- [ ] Name clashes get " 2" like Finder.
- [ ] Add, rename and delete files in Finder: Ithil shows the changes live.
- [ ] Rename the event folder in Finder: Ithil still finds it (marker file).
- [ ] Rename or reschedule the event: its folder is renamed or moved to match. Each occurrence of a repeating
      event has its own folder.
- [ ] Deleting an event with files asks first, then moves its folder to the **Trash**. Nothing is ever deleted
      permanently.
- [ ] Space opens Quick Look, double-click opens the file, and Show in Finder works.
- [ ] Settings → Files → Change… offers to move everything, and the move works.

## 5. Notifications

- [ ] An alert fires at the right time **with Ithil quit**: title "Title in 10 min", body
      "time · location · N files".
- [ ] "Open Files" opens the event's folder. Clicking the notification opens the event in Ithil.
- [ ] Editing or deleting an event updates or removes its pending alert.
- [ ] After sleep/wake and after a time zone change, alerts are still right.
- [ ] The default alert in Settings is used for new events.

## 6. Data safety and recovery

- [ ] Quit Ithil and corrupt `<root>/.ithil/events.json` (e.g. cut it in half). Relaunch: Ithil recovers from the
      newest good backup, tells you, and keeps the damaged file as `events.corrupt-….json`.
- [ ] Rename the Ithil folder, or move it elsewhere on the same drive, while Ithil is quit, then relaunch: Ithil
      follows it and opens it at its new place.
- [ ] Delete the Ithil folder (or move it to the Trash or to another drive) while Ithil is quit, then relaunch: you
      get "Ithil can't find its folder" with **Locate Folder…**, never an empty calendar. Unplug the drive the
      folder lives on: same.
- [ ] Copy the whole root folder to another Mac and open it there: everything is back.

## 7. Menu bar, settings, system integration

- [ ] The menu bar extra (moon) shows today and the next event, with Open Files, Quick Add, Open Ithil, Settings
      and Quit. It can be turned off.
- [ ] Settings: appearance Night / Dawn / Match System, default alert, first weekday, the Quick Add hotkey (change
      it, and check that ⌥Space then stops working), folder, launch at login, menu bar.
- [ ] About shows the version, license and GitHub link. Help → Check for Updates… and Report an Issue… open the
      GitHub pages in the browser.

## 8. Accessibility and looks

- [ ] VoiceOver reads event blocks like "Physics Lecture, 2 to 3:30 PM, 4 files", and every control has a label.
- [ ] Full keyboard access (System Settings → Keyboard → Keyboard navigation): everything is reachable.
- [ ] Reduce Motion and Increase Contrast are respected.
- [ ] Looks right on macOS 14, 15 and 26 (Liquid Glass), in Night and Dawn.

## 9. Release

- [ ] Make the `vX.Y.Z` tag on `main`, either way:
      - On GitHub: **Releases → Draft a new release → Choose a tag**, type `vX.Y.Z`, pick **Create new tag on
        publish** with `main` as the target, then **Publish release** (title and notes can stay empty).
      - In Terminal: `git tag -a vX.Y.Z -m "Ithil X.Y.Z" origin/main && git push origin vX.Y.Z`.
- [ ] The Release workflow (Actions tab, about 15 minutes) attaches `Ithil-X.Y.Z.zip` and
      `Ithil-X.Y.Z.zip.sha256` and the changelog notes.
- [ ] Download the zip on a clean Mac, check the checksum (`shasum -a 256 -c Ithil-X.Y.Z.zip.sha256`), and launch
      it. Without notarization you'll need System Settings → Privacy & Security → Open Anyway.

## Signing and notarization (optional)

Releases are ad-hoc signed unless these repository secrets exist (Settings → Secrets and variables → Actions).
Once they're set, the Release workflow signs with Developer ID, notarizes and staples automatically:

| Secret | What it is |
|---|---|
| `DEVELOPER_ID_CERTIFICATE_P12` | Your "Developer ID Application" certificate and its private key, exported from Keychain Access as `.p12`, then `base64 -i cert.p12 \| pbcopy`. |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | The password you chose when exporting the `.p12`. |
| `APPLE_TEAM_ID` | Your 10-character Team ID (developer.apple.com → Membership). |
| `NOTARY_APPLE_ID` | The Apple ID email of your developer account. |
| `NOTARY_APP_PASSWORD` | An app-specific password from account.apple.com → Sign-In and Security. |

This needs a paid Apple Developer Program membership. Without it, the app is still safe to use, but each user has to
allow it once in Privacy & Security.

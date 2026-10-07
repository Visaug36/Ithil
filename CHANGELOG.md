# Changelog

All notable changes to Ithil are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Week, Day and Month views with a sidebar (mini month, Up next, subject toggles) and search across titles,
  locations and notes.
- Events with a date and time or all-day, subject, location, alert, repeat (daily, weekly or monthly; edit this
  event or all future ones) and notes.
- Quick Add (⌘N): type "physics quiz thursday 10am" and Ithil works out the date, time and subject.
- Subjects with colors from the Ithil palette or a custom color.
- Night and Dawn appearances, or match the system.
- Your calendar lives in a folder you choose, in a schema-versioned `events.json` with atomic writes, rolling
  backups, a safety copy and automatic recovery from damaged files.
- Notifications before events, even while Ithil is quit, with an Open Files action.
- Files for every event in real Finder folders (`2026-10-06/14.00 Physics Lecture`): drop files on an event,
  see them live, open them with Quick Look, and folders follow your edits.
- A moon in the menu bar with today's and tomorrow's events, the next event's files, and Quick Add. It can be
  turned off in Settings.
- A global Quick Add shortcut (⌥Space by default) that works from any app, changeable or switchable off in
  Settings, with a warning when another app already uses it.
- First-launch onboarding in three short steps: welcome, choose a folder, notifications.
- Launch at login, from Settings → General.
- Undo and redo for adding, editing, moving and deleting events and for subject changes; event folders follow
  along, and folders of an undone deletion come back from the Trash.
- Drag events to move them (to another time, or another day in Week view) or drag their bottom edge to change
  the end, with 15-minute snapping; ⌥↑ / ⌥↓ and ⌥⇧↑ / ⌥⇧↓ do the same from the keyboard.
- Delete key and Edit › Find… (⌘F) in the calendar; an About window and Help menu links to the project's
  GitHub pages (opened in your browser).
- Stronger colors when Increase Contrast is on, in both Night and Dawn.
- A Liquid Glass edge on the Quick Add panel on macOS 26 and later.
- A `-demo` launch argument with sample data in a temporary folder.

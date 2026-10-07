# Ithil design

This is the source of truth for how Ithil looks. It was transcribed from the original Claude Design
export, which is not part of the repository. Everything the app needs lives in
`Ithil/Assets.xcassets` (colors, app icon, illustrations, star field) and in `Ithil/Theme/`
(sizes, radii, type).

## Principles

- **Night** is the primary look. **Dawn** is the same world in daylight. In the asset catalog Night is
  the *Dark* appearance and Dawn is *Any* (light).
- Stars appear only in the sidebar, title areas and empty states. The calendar grid stays plain.
- **Amber is reserved** for today, now, selection and primary buttons.
- Glow appears only on the selected event, a drop target, and the today and now markers. Nothing animates
  behind the grid. Stars and glows are static assets.
- Icons are SF Symbols, and file icons are the system's own (`NSWorkspace.icon(forFile:)`).
- The design's mock "now" is Tuesday 6 October 2026, 13:50. The `-demo` sample data uses it.

## Color tokens

Names are the asset-catalog names. Xcode generates Swift symbols from them (`Color.backgroundWindow`,
`Color.textPrimary`, …).

| Token | Night | Dawn | Used for |
|---|---|---|---|
| `BackgroundWindow` | `#141B2E` | `#FBF6EA` | Window, calendar grid |
| `BackgroundSidebar` | `#0F1527` | `#F2EAD7` | Sidebar, title/toolbar area |
| `BackgroundRaised` | `#1D2642` | `#FFFCF4` | Popovers, form groups, Quick Add panel |
| `BackgroundMenu` | `#232D4D` | `#FFFCF4` | Menus |
| `ControlFill` | `rgba(237,230,211,0.08)` | `rgba(27,35,64,0.06)` | Text fields, segmented controls, pills |
| `SeparatorLine` | `rgba(237,230,211,0.08)` | `rgba(27,35,64,0.09)` | Hour lines, dividers |
| `TextPrimary` | `#EDE6D3` | `#1B2340` | Titles, body |
| `TextSecondary` | `#A9ADBE` | `#5A6180` | Times, captions, secondary lines |
| `TextTertiary` | `#888EA5` ¹ | `#62687E` ¹ | Section labels, out-of-month days, hints |
| `AccentColor` | `#F2B45A` | `#E9A23B` | Today, now line, selection ring, primary buttons |
| `AccentText` | `#F5C27A` | `#8D5416` ¹ | Amber text and icon tint ("in 10 min", active tab) |
| `TextOnAccent` | `#1F1607` | `#1B2340` | Text on amber fills |
| `AccentSoft` | `rgba(242,180,90,0.15)` | `rgba(233,162,59,0.18)` | Selection, highlighted "Up next" row |

¹ The design used `TextTertiary` `#6F7692` / `#80869C` and Dawn `AccentText` `#A4621A`. Those miss
WCAG AA (4.5:1) for small text on the window, sidebar and popover backgrounds, so their lightness was
shifted just enough to pass:

| Token | Theme | On window | On sidebar | On raised |
|---|---|---|---|---|
| `TextPrimary` | Night | 13.8 | 14.6 | 12.0 |
| `TextSecondary` | Night | 7.7 | 8.1 | 6.7 |
| `TextTertiary` | Night | 5.3 | 5.6 | 4.6 |
| `AccentText` | Night | 10.5 | 11.1 | 9.2 |
| `TextPrimary` | Dawn | 14.3 | 12.9 | 15.1 |
| `TextSecondary` | Dawn | 5.6 | 5.1 | 5.9 |
| `TextTertiary` | Dawn | 5.1 | 4.6 | 5.4 |
| `AccentText` | Dawn | 5.7 | 5.1 | 6.0 |

`TextOnAccent` on `AccentColor`: 9.7 (Night), 7.1 (Dawn).

### Increase Contrast

With **Increase Contrast** on (System Settings → Accessibility → Display), the tokens that carry text or
lines switch to stronger values. They are the asset catalog's High Contrast variants
(`{"appearance": "contrast", "value": "high"}`, combined with `luminosity: dark` for Night). Backgrounds,
amber fills and subject colors stay as they are. Views that draw their own borders (buttons, drop zones,
event blocks) also strengthen them when `colorSchemeContrast == .increased`.

| Token | Night | Dawn |
|---|---|---|
| `TextSecondary` | `#C8CBD6` | `#383C52` |
| `TextTertiary` | `#B8BBC9` | `#454A5D` |
| `AccentText` | `#FFCF8A` | `#623A0D` |
| `SeparatorLine` | `rgba(237,230,211,0.40)` | `rgba(27,35,64,0.50)` |
| `ControlFill` | `rgba(237,230,211,0.16)` | `rgba(27,35,64,0.12)` |

Text tokens reach 7:1 (WCAG AAA) on every background they're used on:

| Token | Theme | On window | On sidebar | On raised | On menu |
|---|---|---|---|---|---|
| `TextSecondary` | Night | 10.6 | 11.2 | 9.2 | 8.3 |
| `TextTertiary` | Night | 9.0 | 9.5 | 7.8 | 7.1 |
| `AccentText` | Night | 11.9 | 12.6 | 10.3 | 9.4 |
| `TextSecondary` | Dawn | 10.1 | 9.1 | 10.6 | — |
| `TextTertiary` | Dawn | 8.1 | 7.3 | 8.6 | — |
| `AccentText` | Dawn | 9.1 | 8.2 | 9.6 | — |

(Dawn `BackgroundMenu` is the same color as `BackgroundRaised`.)

- `AccentText` on an `AccentSoft` row (the highlighted "Up next" row): Night 9.4 on the sidebar,
  7.6 on raised; Dawn 7.4 on the sidebar, 8.5 on raised.
- `SeparatorLine` lines reach 3:1 against the surface they're drawn on (WCAG 1.4.11 non-text contrast):
  Night 3.3 window, 3.3 sidebar, 3.1 raised, 3.0 menu; Dawn 3.1 window, 3.0 sidebar, 3.1 raised (up from
  about 1.2).
- `ControlFill` doubles its opacity, so pills, fields and the mini month's week stand out (1.5:1 Night,
  1.3:1 Dawn against the surface, up from 1.2 and 1.1) while text on them stays readable: `TextPrimary`
  on the fill is at least 7.0 (Night, on a menu; 7.7 on raised) and 10.2 (Dawn), and `TextSecondary` at
  least 5.4 (Night) and 7.2 (Dawn).

Ratios are WCAG 2 relative-luminance contrast ratios, with translucent tokens composited over each
background first.

### Subject palette

Users create their own subjects and pick one of these colors (or a custom one). The names in brackets
are the design's sample subjects, used only by `-demo`.

| Token | Night | Dawn | Sample subject |
|---|---|---|---|
| `SubjectClay` | `#E08A62` | `#C0643C` | Physics |
| `SubjectTeal` | `#6FB5B0` | `#3F8A86` | Linear Algebra |
| `SubjectIris` | `#A598D6` | `#7466B0` | Literature |
| `SubjectFern` | `#8FB07A` | `#5E8650` | Biology |
| `SubjectRose` | `#D98FA6` | `#B8657F` | Personal |

- **Event fill** = subject color at 20 % (Night) / 15 % (Dawn), with a 1 pt border of the subject
  color at about 35 %.
- **Event title** text uses the subject color in Night (at least 6.5:1). The Dawn subject colors are only
  about 3.8:1 on cream, so in Dawn titles use the subject color mixed toward `TextPrimary` until
  they reach 4.5:1. That gets worked out in Phase 2.
- Past events (ended before now) are drawn at reduced opacity.

## Type

- **New York** (`Font.Design.serif`), semibold: month title 22–28 pt (26 in the window title), event
  title in details 22 pt, day header 18–21 pt, empty-state headline 19–20 pt. The year after the month
  title ("October **2026**") is regular weight in `TextSecondary`.
- **SF Pro** for everything else: body 13 pt, secondary 12–12.5 pt, captions and section labels 11 pt
  semibold, event blocks 12 pt semibold title / 11 pt time.
- **Tabular numerals** for every time (`.monospacedDigit()`).

Defined in `Ithil/Theme/Typography.swift`.

## Spacing and shape

- 4 pt grid. Sidebar 244 pt. Toolbar 52 pt (64 pt with large title). Week header 56 pt. Hour row 48 pt.
  Time gutter 56 pt.
- Padding: popovers 18 pt, grouped form rows 10 × 14 pt, sidebar rows 7 × 8 pt.
- Radii: event block 6, controls 6–7, list rows 7, form groups and drop zones 10, popovers 12 (system),
  panel 14.
- Glow: selected event = 1.5 pt amber ring + 14 pt soft shadow; drop target = 1.5 pt ring + 32 pt
  shadow at 32 %; today and now markers.

Defined in `Ithil/Theme/Metrics.swift`.

## SF Symbols

`chevron.left` / `chevron.right`, `sidebar.left`, `magnifyingglass`, `plus`, `moon.fill` (menu bar,
template image), `bell`, `repeat`, `mappin`, `paperclip`, `folder`, `eye`, `gearshape`,
`circle.grid.2x2`, `chevron.up.chevron.down`, `checkmark`. Tint: `TextSecondary` (moonlight) by default,
`AccentText` (amber) for active or primary.

## Assets

| Asset | What it is |
|---|---|
| `AppIcon` | Option **1a**: a crescent moon over a glowing arched window with tree mullions, on a deep navy night sky with small stars and a dark hill. Body on Apple's 824/1024 grid with a soft drop shadow, at 16–512 pt @1x/@2x. A 1024 px master is in `docs/images/icon-1024.png`. |
| `StarField` | A static 512 × 512 pt tile (@1x, @2x) of about 95 small dots, drawn with `.resizable(resizingMode: .tile)`. Night: cream `#EDE6D3` stars; Dawn: faint amber `#C79A55` specks. Transparent, so it sits on any background. |
| `EmptyDay` | SVG. Crescent moon with a soft glow, a hill, a small house with a lit door. |
| `EmptyFiles` | SVG. An open folder with a paper sticking out, a crescent on the front, two sparkles, and an amber glow behind. |
| `EmptySearch` | SVG. A hanging lantern with a flame and a warm glow, over a dotted ground line. |

Every image has a Night (Dark) and Dawn (Any) variant.

## Screens

### 1. Main window, Week view (default)

`WindowGroup` + `NavigationSplitView`.

**Sidebar** (244 pt, `BackgroundSidebar` + stars):
- Traffic lights at top left.
- **Mini month**: "October" in New York semibold with ‹ › chevrons on the right; weekday initials
  (M T W T F S S, following the locale's first weekday) in `TextTertiary`; day numbers in
  `TextPrimary`, out-of-month days in `TextTertiary`. The week on screen gets a `ControlFill` pill
  across its row. Today is an amber filled circle with the number in `TextOnAccent`, bold.
- **Up next** (section label 11 pt semibold `TextTertiary`): rows with a subject-colored dot, a title
  in 13 pt `TextPrimary`, and a secondary line ("Today · 17:00", "Tomorrow · 09:00",
  "Thursday · 10:00"). The very next event is highlighted with an `AccentSoft` rounded row (radius 7)
  and its secondary line is amber `AccentText`: "in 10 min · 14:00 · Room B204".
- **Subjects**: one row per subject with a rounded checkbox filled with the subject color (checkmark
  in dark ink) and the name. Unchecking hides that subject's events.

**Toolbar** (52 pt, title area `BackgroundWindow`, stars allowed): `sidebar.left` toggle, title
"October 2026" (month New York semibold 26 pt, year regular `TextSecondary`), then on the right a
`ControlGroup` "‹ Today ›", a segmented `Picker` Day | Week | Month (selected segment is a raised pill),
a search field ("Search", `magnifyingglass`), and a square amber `+` button (`.borderedProminent`,
tinted amber).

**Week grid** (`BackgroundWindow`, no stars):
- Header row 56 pt: "Mon 5", "Tue 6", …; the weekday is `TextSecondary`, the number `TextPrimary`.
  For today the weekday is amber and the number sits in an amber circle.
- Time gutter 56 pt with hour labels ("09:00") in `TextTertiary`, tabular. Hour rows 48 pt with
  `SeparatorLine` lines; vertical day separators.
- **Now**: an amber pill in the gutter with the time ("13:50", `TextOnAccent`), and a 1 pt amber
  line. The line is solid with a dot across today's column, and faint across the other days.
- **Event blocks** (radius 6): subject fill + border; title 12 pt semibold in the subject color
  (wraps to 2 lines), time "14:00 – 15:30" 11 pt, followed by `paperclip` + file count when the event
  has files. Overlapping events split the column width.
- **Selected event**: 1.5 pt amber ring + soft amber glow.

### 2. Month view (sidebar collapsed)

Same scene with `columnVisibility = .detailOnly`. Weekday header row (Mon … Sun, `TextSecondary`), then
a `LazyVGrid` of 7 columns. Each cell has the day number top right ("1 Oct" / "1 Nov" on the first of
a month; out-of-month numbers in `TextTertiary`; today in an amber circle). Up to 3 events per cell as
rows: subject dot, title truncated with "…", time right-aligned in `TextSecondary`. All-day events
("Mara's birthday", "Essay due") are shown as a tinted bar (subject fill) instead of a dotted row.
More than 3 → "N more" in `TextTertiary`.

### 3. Day view

Not drawn in the design. Follow the week view with a single, wider day column. The empty day uses the
"A quiet day." empty state.

### 4. Quick Add (⌥Space anywhere, ⌘N in the app)

A nonactivating floating `NSPanel`, radius 14, `BackgroundRaised`, over a starry backdrop.
- Top: a crescent glyph in amber, then the text field at about 17 pt: "physics quiz thursday 10am".
  Recognized date/time tokens are highlighted with an `AccentSoft` background and `AccentText` color.
- Preview row: subject dot, "Physics Quiz" (13 pt semibold) over "Thursday, 8 October · 10:00 – 11:00"
  (`TextSecondary`). On the right a subject capsule ("Physics", subject fill + subject-colored text)
  and an alert capsule (`bell` "10 min before", `ControlFill`).
- Footer (11 pt `TextTertiary`, separated by a line): left "Subject matched from "physics""; right the
  key hints "↩ Add", "⌘↩ Add and edit", "esc Close".
- **Liquid Glass (macOS 26+ only):** the panel keeps its opaque `BackgroundRaised` fill and hairline, inset
  2 pt over a `.glassEffect(.regular)` in the panel's shape, so only a thin glass rim (with its own lit
  edge) shows around it. Every word stays on the opaque token color, so the contrast below holds whatever is
  behind the panel. macOS 14 and 15 are unchanged (`RaisedPanelBackground`).

### 5. New / edit event popover

`.popover(arrowEdge: .leading)` pointing at the event block, radius 12, padding 18.
- Header: subject dot + title "Physics Quiz" (editable, 15 pt semibold).
- Form rows with right-aligned labels in `TextSecondary`: **Date** (`DatePicker(.field)`
  "Thu, 8 Oct 2026"), **Time** ("10:00" to "11:00" fields + duration hint "1 hr" in `TextTertiary`),
  **Subject**, **Alert**, **Repeat** (`Picker(.menu)`), **Notes** (`TextEditor`).
- Alert menu items: At time of event · 10 minutes before (checked) · 1 hour before · 1 day before ·
  divider · None. The checked item is highlighted amber with `TextOnAccent`.
- Drop zone (dashed border, radius 10): `paperclip` + "Drop files here", with a secondary line
  "Copied to Ithil › 2026-10-08 › 10.00 Physics Quiz".
- Buttons bottom right: "Cancel" (bordered) and "Add Event" (amber, prominent; "Done" when editing).

### 6. Event details popover

- Subject label (dot + "Physics" in subject color, 11 pt), title "Physics Lecture" (New York 22 pt),
  "Tuesday, 6 October · 14:00 – 15:30" (`TextSecondary`).
- Info rows with symbols: `mappin` "Room B204", `bell` "10 minutes before", `repeat` "Every Tuesday".
- Divider, then "Files · 4" (section label) and a "Show in Finder" button (`folder`).
- File list rows (radius 7): system file icon, name (13 pt) over "PDF document · 2.4 MB"
  (`TextSecondary`). The selected row has an `AccentSoft` background and an `eye` "Space" hint on the
  right (Space opens Quick Look).
- Footer path row: `folder` "Ithil › 2026-10-06 › 14.00 Physics Lecture" (`TextTertiary`).
- **Dragging files over it**: the whole popover gets the drop-target glow (amber ring + 32 pt glow). The
  list dims, and a dashed amber drop zone shows a `folder` icon and "Drop to add 2 files" /
  "Copied into 14.00 Physics Lecture", with the dragged file icons and a green count badge.

### 7. Notification (drawn by macOS)

Ithil supplies the app icon, text and action. Title "Physics Lecture in 10 min", body
"14:00 – 15:30 · Room B204 · 4 files". On hover macOS shows the "Open Files" action button. Category
`EVENT`, action "Open Files" opens the event's folder.

### 8. Menu bar extra

`MenuBarExtra("Ithil", systemImage: "moon.fill")` with `.menuBarExtraStyle(.window)`, `BackgroundRaised`
panel:
- "Tuesday" (New York semibold) + "6 October" (`TextSecondary`).
- Next card (`AccentSoft` fill, amber border, radius 10): "Next, in 10 min" (amber 11 pt), "Physics
  Lecture" (13 pt semibold), "14:00 – 15:30 · Room B204", an amber "Open Files" button (`folder`) and
  "4 files" (`TextTertiary`).
- "Today" and "Tomorrow" sections: rows with a time (tabular, `TextSecondary`), a subject dot, the title,
  and `paperclip` + count on the right. Past rows are dimmed.
- Divider, then menu-style rows with shortcuts on the right: "Quick Add… ⌥Space", "Open Ithil ⌘O",
  "Settings… ⌘,", "Quit Ithil ⌘Q".

As built: `MenuBarExtra(isInserted: $settings.showsMenuBarExtra)` with a `moon.fill` template label, 300 pt
wide. "N files" on the Next card uses `TextSecondary` (`TextTertiary` on the amber card is about 3.4:1 in
Night, below AA), and "Open Files" with the count shows only once the event has files. Past rows are dimmed by
switching to the quieter text tokens, not by lowering opacity, so they stay above AA. Each day list shows up
to 6 rows, then "N more". The Quick Add row shows the shortcut from Settings and is disabled while the
calendar can't be edited. On macOS 26 the system draws the window as Liquid Glass; the content keeps its
opaque `BackgroundRaised` background on every version (no glass on glass).

### 9. Settings (General / Subjects / Files)

`Settings` scene, toolbar-style tabs with symbols: General (`gearshape`-like sun icon in the design,
amber when selected), Subjects (`circle.grid.2x2`), Files (`folder`). Title area has stars.
`Form.formStyle(.grouped)`, radius-10 groups on `BackgroundRaised`.
- **Appearance**: three thumbnail cards (Night, Dawn, Match System, the last split diagonally). The
  selected card has the amber ring and a bold label. It sets `NSApp.appearance` (nil = Match System).
- **Default alert**: pop-up "10 minutes before".
- **Attachments folder**: `folder` "~/Documents/Ithil" + "Change…" button. Footnote: "Each event gets
  its own folder, like 2026-10-06/14.00 Physics Lecture."
- **Launch at login** and **Show in menu bar**: amber switches. Launch at login uses
  `SMAppService.mainApp`.
- **Quick Add shortcut**: a recorder field showing "⌥Space" (`ControlFill` capsule; "Type Shortcut" in
  amber inside the selection ring while recording) and "Reset". Esc cancels, ⌫ turns it off ("Off"); a
  shortcut needs ⌘, ⌥ or ⌃ and can't be one of Ithil's own menu shortcuts. The footnote warns "Another app
  is using this shortcut. Choose a different one." when registration fails.
- **Launch at login**: when macOS needs approval, a row says it's switched off in System Settings → General →
  Login Items, with "Open Login Items…".
- Also required by the brief: first weekday (General); subject management (Subjects); folder location and
  move (Files).

### 10. Empty states

A `ContentUnavailableView`-style layout: illustration, New York headline 20 pt, SF Pro secondary line,
centered, on a starry background.
- **Empty day**: header "Saturday, 17 October" (New York) top left; `EmptyDay`; "A quiet day." /
  "Nothing planned. Press ⌘N to add something."
- **No files**: section label "Files", a large dashed drop zone (radius 10) holding `EmptyFiles`;
  "No files yet. Drop some here." / "They're copied to 14.00 Physics Lecture and show up in Finder
  too."
- **No search results**: the search field focused with an amber ring, showing "chemistry"; `EmptySearch`;
  "Nothing by that name." / "No events match "chemistry"."

### 11. Onboarding (first launch)

Not drawn in the design; built from the folder screens' style. Three short pages on `BackgroundWindow`
with stars, each centered and at most 440 pt wide: the app icon (96 pt), a New York headline 26 pt in
`TextPrimary`, one line in 13 pt `TextSecondary`, the page's content, then its buttons (amber prominent
with `TextOnAccent`, or quiet `ControlFill`). Three 7 pt step dots sit centered along the bottom: the
current one amber, the others `TextTertiary` at 55 % (`TextSecondary` with Increase Contrast).

1. **Welcome**: "Welcome to Ithil" / "A calm calendar for your classes, with every event’s files close at
   hand." A `BackgroundRaised` card (radius 10, `SeparatorLine` border) with three points, each a
   moonlight SF Symbol beside a 13 pt semibold title and a 12.5 pt secondary line: `lock` "Offline and
   private", `folder` "Files in real folders", `keyboard` "Quick Add from anywhere" (with the current
   shortcut, e.g. ⌥Space). "Continue" (amber, Return).
2. **Choose folder**: the choose-folder screen's headline, explanation and buttons ("Create Ithil
   Folder…" suggesting ~/Documents/Ithil, "Use Existing Folder…") and its backup footnote. "‹ Back" in
   `AccentText` at the bottom left.
3. **Notifications**: "Stay on time" / "One more thing before your calendar opens.", the notification
   permission card (max 380 pt wide), then "Skip" (quiet, `AccentText`) until macOS has an answer and
   "Continue" (amber) after. Footnote: "You can change this later in Settings."

Pages slide in by 40 pt and fade (0.25 s); with Reduce Motion they only cross-fade.

## Screen → SwiftUI map

| Screen | Implementation |
|---|---|
| Main window | `WindowGroup` + `NavigationSplitView`. Sidebar: custom mini-month `Grid`, `List` sections "Up next" and "Subjects" (a `Toggle` per subject). Detail: custom week grid in a `ScrollView`. Toolbar: `ControlGroup` ‹ Today ›, `Picker(.segmented)` Day/Week/Month, `.searchable`, `Button(+)` `.borderedProminent` tinted amber. |
| Month view | Same scene, `columnVisibility = .detailOnly`. `LazyVGrid` of 7 columns, 3 events max + "N more". |
| Quick Add | `NSPanel` (nonactivating, floating) hosting a `TextField`; `NSDataDetector` + keyword match for date, time and subject. Return adds, ⌘Return opens the edit popover. |
| Edit popover | `.popover(arrowEdge: .leading)`. Form with `DatePicker(.field)`, `Picker(.menu)` for Subject, Alert, Repeat; `TextEditor` for notes; drop zone via `.dropDestination(for: URL.self)`. |
| Event details | `.popover`. File `List` with `NSWorkspace` icons, `.quickLookPreview($url)` on Space, "Show in Finder" = `NSWorkspace.activateFileViewerSelecting`. `isTargeted` from `.dropDestination` switches to the amber drop state. Path row = `PathControl` or plain `Text`. |
| Files on disk | `Documents/Ithil/yyyy-MM-dd/HH.mm Title/`. Copy on drop with `FileManager`; watch with `DispatchSource` / `NSFilePresenter` so Finder edits show up live. Rename the folder when title or time changes. |
| Notification | `UNUserNotificationCenter`. Category "EVENT" with `UNNotificationAction` "Open Files" (opens the folder). Title "{Title} in 10 min", body "time · location · N files". |
| Menu bar | `MenuBarExtra("Ithil", systemImage: "moon.fill").menuBarExtraStyle(.window)`. Hidden when the Settings toggle is off. |
| Settings | `Settings` scene, `TabView` (General, Subjects, Files), `Form.formStyle(.grouped)`. Appearance sets `NSApp.appearance` or nil for Match System. `SMAppService.mainApp` for launch at login. |
| Empty states | `ContentUnavailableView`-style layout: illustration asset, New York headline, SF Pro secondary line. |
| Onboarding | `OnboardingView(startAt:onFinish:)` in the main window: one `OnboardingPage` per step, `.transition` gated by `accessibilityReduceMotion`. The folder step reuses `ChooseFolderActions`; the last step reuses `NotificationPermissionView` and sets `AppSettings.hasCompletedOnboarding`. |

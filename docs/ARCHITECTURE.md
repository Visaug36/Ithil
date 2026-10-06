# Ithil architecture

Ithil is one Xcode project with three targets:

| Target | What lives there |
|---|---|
| `Ithil` (app) | SwiftUI views, AppKit glue (panels, menus, hotkey), the `@Observable` app model, user-facing strings (`Localizable.xcstrings`). |
| `IthilCore` (static framework) | Every piece of logic that can be tested without a window: model, date math, recurrence, storage, folder naming, file operations, Quick Add parsing. No SwiftUI, no AppKit, no user-facing strings. |
| `IthilCoreTests` | Swift Testing tests for `IthilCore`. Not hosted, so they run without launching the app. |

Rules that apply everywhere:

- **The main thread never waits on disk.** Storage and file work run on actors or background tasks; the app
  model updates its in-memory state first and saves asynchronously.
- **Time, file system and notifications sit behind protocols** (`TimeSource`, `FileSystem`, later
  `NotificationScheduling`) so tests can fake them.
- **All date math goes through `Calendar` / `DateComponents`** with an explicit time zone. Never add
  `86_400` seconds to get "tomorrow".
- **Nothing is ever written outside the library's root folder**, except Ithil's own safety copy in
  Application Support.
- **Logs** use `os.Logger`; event titles and file names are always `privacy: .private`.

## Model (`IthilCore/Model`)

| Type | Meaning |
|---|---|
| `CalendarDate` | A plain Gregorian day (`yyyy-MM-dd`), no time zone. Converted to `Date` only with an explicit `TimeZone`. |
| `Event` | One entry. `timing` is `.timed(start, end, timeZone)` (absolute instants plus the event's own zone) or `.allDay(start, end)` (plain dates, `end` inclusive). Optional `subjectID`, `alert`, `recurrence`; `excludedDates`; `detachedFrom`. |
| `RecurrenceRule` | `daily` / `weekly` / `monthly` plus an optional inclusive `until` day. Monthly skips months without the day. |
| `SeriesOccurrence` | (series ID, original date): identifies one occurrence of a repeating event. |
| `Occurrence` | A concrete appearance of an event: the event, its original `date`, and absolute `start` / `end`. |
| `Subject` | Name, `SubjectColor` (`.palette(PaletteColor)` or `.custom(r, g, b)`), Quick Add `keywords`. |
| `Library` | The whole document: `id`, `subjects`, `events`. |
| `AlertOffset` | Minutes before start (0 = at time of event). Presets: at time, 10 min, 1 hour, 1 day. |

All model types are `Sendable`, `Hashable` and `Codable`. Timestamps are rounded to whole seconds, which is
the precision events.json keeps.

### Repeating events

- Occurrences are generated in the **event's own time zone**: a weekly 14:00 lecture stays at 14:00
  wall-clock time across DST changes. Duration is kept as absolute elapsed time.
- If the wall-clock time doesn't exist on a day (spring-forward gap), the occurrence moves forward to the
  next valid time, as `Calendar` does.
- **Edit this event only:** the occurrence's date is added to the series' `excludedDates`, and a new
  non-repeating event with `detachedFrom = (seriesID, date)` takes its place (the copy never repeats,
  whatever `edited.recurrence` says).
- **Edit all future events:** the series ends the day before (`until = date - 1`), and a new series
  starts at the edited occurrence. Excluded dates and detached events on or after the split move to the
  new series. If the edit moved the occurrence to another day, they move along with it (daily/weekly: by
  the same number of days; monthly: by the same number of months, onto the new day of the month, dropped
  if that month lacks it), so a cancelled or replaced occurrence never comes back on the new day. If the
  new event doesn't repeat, those detached events become ordinary events (`detachedFrom = nil`).
- Editing all future events from the **first occurrence** edits the whole series in place, keeping its
  `id` and `createdAt`; if that moves it to another day, its excluded dates and its detached events' links
  move along in the same way. An edit that changes nothing leaves the library untouched.
- Non-repeating and detached events are replaced or removed by `id`, whatever the scope. Deleting a
  detached event keeps its date excluded from the series.
- **Delete this event only** adds the date to `excludedDates`. **Delete all future** ends the series the
  day before and removes detached events from that day on; from the first occurrence it removes the series
  and all its detached events. A series left with no occurrences is removed (an in-place edit never
  removes it). Deleting doesn't touch `modifiedAt` (there is no clock); edits stamp `modifiedAt = now`.

## Dates (`IthilCore/Dates`)

```swift
public enum CalendarSpan: Hashable, CaseIterable, Sendable { case day, week, month }

public enum RelativeDay: Hashable, Sendable {
    case yesterday, today, tomorrow
    case laterThisWeek(weekday: Int)   // 2…6 days ahead; Gregorian weekday 1 = Sunday
    case other(CalendarDate)
}

public struct CalendarMath: Sendable {
    public let timeZone: TimeZone
    public let firstWeekday: Int                      // 1 = Sunday … 7 = Saturday
    public init(timeZone: TimeZone, firstWeekday: Int)
    public var calendar: Calendar { get }             // Gregorian, with timeZone and firstWeekday set
    public func today(now: Date) -> CalendarDate
    public func week(containing date: CalendarDate) -> [CalendarDate]          // 7 days from firstWeekday
    public func monthGrid(year: Int, month: Int) -> [CalendarDate]            // whole weeks, 35 or 42 days
    public func weekdayOrder() -> [Int]                                        // e.g. [2,3,4,5,6,7,1]
    public func interval(from first: CalendarDate, through last: CalendarDate) -> DateInterval
    public func visibleDays(for span: CalendarSpan, around date: CalendarDate) -> [CalendarDate]
    public func step(_ date: CalendarDate, by span: CalendarSpan, count: Int) -> CalendarDate
    public func relativeDay(_ date: CalendarDate, today: CalendarDate) -> RelativeDay
    public func minutesOfDay(_ instant: Date) -> Int                           // wall-clock hh*60+mm
}

public struct OccurrenceExpander: Sendable {
    public init(displayTimeZone: TimeZone)
    public let displayTimeZone: TimeZone                      // where all-day events are placed
    public func occurrences(of event: Event, in interval: DateInterval) -> [Occurrence]
    public func occurrences(of events: [Event], in interval: DateInterval) -> [Occurrence]   // sorted
    public func occurrence(of event: Event, on date: CalendarDate) -> Occurrence?
    public func upcoming(_ events: [Event], after now: Date, limit: Int, horizonDays: Int) -> [Occurrence]
}

public struct DayLayout: Sendable {
    public struct Item: Hashable, Sendable {
        public var occurrence: Occurrence
        public var column: Int, columnCount: Int        // side-by-side columns for overlaps
        public var startMinute: Int, endMinute: Int     // 0…1440, clipped to the day
        public var continuesBefore: Bool, continuesAfter: Bool
        public init(occurrence:column:columnCount:startMinute:endMinute:continuesBefore:continuesAfter:)
    }
    public static func layout(_ occurrences: [Occurrence], on day: CalendarDate, timeZone: TimeZone,
                              minimumMinutes: Int) -> [Item]
}

public enum SeriesEditing {
    public enum Scope: Hashable, Sendable { case thisEvent, allFutureEvents }
    public static func update(_ occurrence: Occurrence, with edited: Event, scope: Scope,
                              in library: inout Library, now: Date)
    public static func delete(_ occurrence: Occurrence, scope: Scope, from library: inout Library)
}

public enum EventSearch {
    public static func matches(_ event: Event, query: String) -> Bool
    public static func search(_ library: Library, query: String, now: Date,
                              expander: OccurrenceExpander) -> [Occurrence]
}
```

- Queries over 5,000 events must stay well under a frame. Non-repeating events are tested by interval
  overlap. Repeating events jump straight to the first candidate in the range (arithmetic on days or
  months) instead of walking from the series start.
- `search` returns one row per matching event: its next occurrence that hasn't ended (one in progress
  counts), or, if none, its latest past one. Upcoming rows come first, by start; then past rows, most
  recent first. Every whitespace-separated term must match the title, location or notes (case- and
  diacritic-insensitive). A blank query: `matches` is true for every event, `search` returns nothing.
- `monthGrid` is always 35 or 42 days (a February that fits in exactly 4 weeks gets a fifth row); months
  outside 1…12 roll over. `firstWeekday` outside 1…7 wraps. `step(by: .month)` clamps to the month's last
  day (31 Jan + 1 month = 28/29 Feb). `relativeDay` gives `laterThisWeek` for any day 2…6 ahead.
- `upcoming` returns occurrences that start at or after `now` (in-progress ones are left out).
- `DayLayout` leaves out all-day occurrences (they go in the all-day row). Blocks shorter than
  `minimumMinutes` are drawn that tall (moved up near midnight), and overlap is judged on drawn blocks.
- Internal helpers other IthilCore code may use: `OccurrenceDayMath` (integer day numbers on plain dates,
  series-day enumeration) and `OccurrenceExpander.chronologicalOrder` / `overlaps(start:end:_:)`.

## Storage (`IthilCore/Storage`)

```
<root>/
  .ithil/
    events.json                 ← the library (schema-versioned JSON)
    backups/events-yyyyMMdd-HHmmss.json
    events.corrupt-yyyyMMdd-HHmmss.json   ← a damaged file, set aside (never deleted)
  2026-10-06/14.00 Physics Lecture/       ← event folders (Phase 4)
~/Library/Containers/…/Application Support/Ithil/SafetyCopies/<library id>.json
```

events.json:

```json
{
  "schemaVersion": 1,
  "savedAt": "2026-10-06T11:50:00Z",
  "id": "…",
  "subjects": [ { "id": "…", "name": "Physics", "color": "clay" } ],
  "events": [ { "id": "…", "title": "Physics Lecture",
                "timing": { "kind": "timed", "start": "2026-10-06T12:00:00Z", "end": "2026-10-06T13:30:00Z",
                            "timeZone": "Europe/Amsterdam" },
                "subjectID": "…", "location": "Room B204", "alert": 10,
                "recurrence": { "frequency": "weekly" }, "createdAt": "…", "modifiedAt": "…" } ]
}
```

```swift
public protocol FileSystem: Sendable {
    func fileExists(at url: URL) -> Bool
    func isDirectory(at url: URL) -> Bool
    func contentsOfDirectory(at url: URL) throws -> [URL]   // includes hidden files
    func createDirectory(at url: URL) throws                  // with intermediates; fine if it exists
    func readData(at url: URL) throws -> Data
    func writeAtomically(_ data: Data, to url: URL) throws    // temp file in the same folder, then rename
    func copyItem(at source: URL, to destination: URL) throws
    func moveItem(at source: URL, to destination: URL) throws
    func removeItem(at url: URL) throws                       // only for Ithil's own housekeeping files
    func trashItem(at url: URL) throws                        // moves to the Trash
    func modificationDate(at url: URL) -> Date?
}
public struct LocalFileSystem: FileSystem { public init() }

public enum LibraryCodec {
    public static let currentSchemaVersion: Int               // 1
    public static let schemaMigrator: SchemaMigrator          // the real migrations (none yet)
    public static func encode(_ library: Library, savedAt: Date) throws -> Data   // pretty, sorted keys
    public static func decode(_ data: Data) throws -> DecodedLibrary              // runs migrations
    public static func decode(_ data: Data, migrator: SchemaMigrator) throws -> DecodedLibrary   // tests
}
public struct DecodedLibrary: Hashable, Sendable {
    public var library: Library
    public var savedAt: Date?
    public var schemaVersion: Int                             // as written, before migration
    public init(library: Library, savedAt: Date?, schemaVersion: Int)
}

public struct SchemaMigrator: Sendable {   // JSON-object-level steps, version n → n+1
    public typealias Step = @Sendable (inout [String: Any]) throws -> Void
    public let currentVersion: Int
    public init(currentVersion: Int, steps: [Int: Step])
    @discardableResult
    public func migrate(_ object: inout [String: Any]) throws -> Int   // returns the version it started at
}

public enum LibraryStoreError: Error, Equatable, Sendable {
    case noLibrary                                   // nothing to load and nothing to recover from
    case newerSchema(found: Int, supported: Int)     // written by a newer Ithil: never overwrite it
    case unreadable(String)                          // corrupt, and no good backup or safety copy
    case readOnly                                    // save() after a newerSchema load
}

public struct RecoveryReport: Hashable, Sendable {
    public enum Source: Hashable, Sendable {
        case backup(URL)
        case safetyCopy(URL)
        public var url: URL { get }
    }
    public var source: Source
    public var recoveredSavedAt: Date?
    public var damagedFileMovedTo: URL?                       // nil when events.json was missing
    public init(source: Source, recoveredSavedAt: Date?, damagedFileMovedTo: URL?)
}

public struct LibraryLoad: Hashable, Sendable {
    public var library: Library
    public var recovery: RecoveryReport?
    public init(library: Library, recovery: RecoveryReport?)
}

public actor LibraryStore {
    public init(root: URL, safetyDirectory: URL, knownLibraryID: UUID?,
                fileSystem: any FileSystem, timeSource: any TimeSource,
                backupInterval: TimeInterval, maxBackups: Int)
    public nonisolated let root: URL
    public func load() throws -> LibraryLoad
    public func create(_ library: Library) throws               // a brand-new library in an empty folder
    public func save(_ library: Library) throws
}

public enum RootFolderPolicy {
    public static let defaultFolderName: String                // "Ithil"
    public static func isIthilFolder(_ url: URL, fileSystem: any FileSystem) -> Bool
    public static func isEffectivelyEmpty(_ url: URL, fileSystem: any FileSystem) -> Bool   // ignores .DS_Store etc.
    public static func libraryFolder(forChosen url: URL, fileSystem: any FileSystem) throws -> URL
}
```

- **Load:** read events.json → decode (migrating older schemas in memory). A newer schema throws
  `newerSchema` and the folder is opened read-only. If events.json is missing or unreadable, try the
  candidates (backups and the safety copy for the known library ID), newest `savedAt` first. The first one
  that decodes wins: the damaged file is moved aside, the recovered library is written back, and a
  `RecoveryReport` is returned so the app can tell the user. No candidates → `noLibrary` (missing file) or
  `unreadable` (the damaged file is then left untouched). A read error counts as damage. Candidates from a
  newer schema are skipped; on equal `savedAt` the newer backup wins and the safety copy comes last. The
  winner's original bytes are written back. If the damaged file can't be moved aside, `load()` throws
  `unreadable` rather than overwrite it.
- **Missing root** (moved folder, unplugged drive): `load()` throws `noLibrary`; `create` and `save` throw
  `CocoaError(.fileNoSuchFile)`. Nothing is written anywhere, so the folder is never recreated.
- **Save:** unless a backup exists within `backupInterval` of now (either direction, so a clock set back
  doesn't stop backups), copy the current events.json into `backups/` first, then keep only the newest
  `maxBackups` (by name; `-2`, `-3`… within one second, always numbered past the highest one there). The
  first save after loading an older schema always backs up. Write events.json atomically, then write the
  same bytes to the safety copy. Failed backups, pruning and safety copies are logged, not thrown.
- **Save without a successful `load()`/`create`** first checks the events.json it would replace: a newer
  schema makes the store read-only (`readOnly`), a damaged file is set aside first.
- **Create** refuses (`CocoaError(.fileWriteFileExists)`) when events.json already exists.
- **Choosing a folder:** an empty folder or an existing Ithil folder is used as is. Any other folder gets an
  `Ithil` subfolder (or `Ithil 2`, `Ithil 3`… if that name is taken by something else; an existing empty
  or Ithil `Ithil N` is reused). "Ithil folder" means it has a `.ithil` folder, even without events.json.
  "Empty" ignores `.DS_Store`, `.localized`, `Icon\r`, `._*` and drive-root metadata. Throws if the chosen
  folder doesn't exist.
- Internal constants for other IthilCore code: `LibraryStore.metadataFolderName` (`.ithil`, e.g. to skip
  it when scanning event folders), `eventsFileName`, `backupsFolderName`.

## Quick Add (`IthilCore/QuickAdd`)

```swift
public struct QuickAddDraft: Hashable, Sendable {
    public var title: String                 // may be empty: the app shows a localized placeholder
    public var timing: EventTiming
    public var subjectID: UUID?
    public var matchedKeyword: String?       // as typed, for "Subject matched from “physics”"
    public var highlightedRanges: [NSRange]  // UTF-16 ranges in the input recognized as date/time
    public var alert: AlertOffset?
    public var hasDate: Bool
    public var hasTime: Bool
    public init(title:timing:subjectID:matchedKeyword:highlightedRanges:alert:hasDate:hasTime:)   // defaults
}

public struct QuickAddParser: Sendable {
    public init(subjects: [Subject], timeZone: TimeZone, defaultDuration: TimeInterval,
                defaultAlert: AlertOffset?)
    public let subjects: [Subject], timeZone: TimeZone, defaultDuration: TimeInterval
    public let defaultAlert: AlertOffset?
    public func parse(_ text: String, now: Date) -> QuickAddDraft?   // nil for blank input
    public func makeEvent(from draft: QuickAddDraft, fallbackTitle: String, now: Date) -> Event
}
```

- `NSDataDetector(types: .date)` finds the date and time; the matched text is removed from the title and
  highlighted. A match with no time-of-day words (`10am`, `14:30`, `noon`…) becomes an all-day event on
  that date. Nothing detected → today, all-day. A detected duration sets the end; otherwise the default
  duration (1 hour).
- Subjects match on whole words, case- and diacritic-insensitive: the subject's name (multi-word names
  too) or any of its keywords. The longest match wins, and the word stays in the title.
- Titles typed in all lowercase become title case, keeping small words ("with", "of", "and"…) lowercase
  unless they come first: `physics quiz` → `Physics Quiz`, `lunch with mara` → `Lunch with Mara`.
  Anything with a capital letter is kept as typed. The check looks at the title after the date text is
  removed, so `bio exam Friday` still becomes `Bio Exam`.
- Title cleanup also drops a connector right before the date (`at on from by until till @`), a lone
  connector after it (`… tomorrow at`), and stray punctuation at both ends. Subjects are matched against
  the cleaned title, so date words never pick a subject.
- `alert` is `defaultAlert` for timed drafts and nil for all-day ones. All-day drafts are one day long.
- NSDataDetector reads text in the Mac's current time zone. A detected wall-clock time is kept as that
  wall-clock time in the parser's `timeZone`; a time with a named zone ("3pm EST") keeps its instant.
  `NSDataDetector` isn't Sendable, so `parse` makes one per call.

## Demo (`IthilCore/Demo`)

```swift
public enum DemoLibrary {
    public static func make(weekContaining now: Date, timeZone: TimeZone) -> Library
}
```

The design's sample subjects (Physics, Linear Algebra, Literature, Biology, Personal) and their week of
events, placed in the Monday-start week containing `now`. The app's `-demo` launch argument loads it into a
temporary folder; `-demoNow 2026-10-06T13:50` additionally pins the clock for screenshots. Every ID is fixed
(`4954484C-DE30-4000-8000-00000000GGNN`: group 00 library, 01 subjects, 02 events), so equal arguments give
equal libraries. Weekly classes repeat forever; timed events have a 10-minute alert.

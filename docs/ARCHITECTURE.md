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
- **Time, file system and notifications sit behind protocols** (`TimeSource`, `FileSystem`,
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
    func trashItemReturningURL(at url: URL) throws -> URL?   // the same, plus where it went (nil = unknown)
    func modificationDate(at url: URL) -> Date?
}
extension FileSystem { public func trashItemReturningURL(at url: URL) throws -> URL? }  // trashItem, then nil
public struct LocalFileSystem: FileSystem { public init() }   // FileManager.trashItem(at:resultingItemURL:)

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

## Notifications (`IthilCore/Notifications`)

```swift
public struct PlannedAlert: Hashable, Sendable {
    public var identifier: String          // the notification request's identifier
    public var occurrence: Occurrence
    public var fireDate: Date
    public var minutesBefore: Int
}

public struct AlertPlanner: Sendable {
    public static let identifierPrefix = "ithil.alert."
    public init(displayTimeZone: TimeZone, allDayAlertHour: Int = 9, maximumCount: Int = 48, horizonDays: Int = 14)
    public func plan(_ library: Library, now: Date) -> [PlannedAlert]     // nearest first, fireDate > now
    public func identifier(for occurrence: Occurrence, minutesBefore: Int) -> String
    public static func parse(identifier: String) -> (eventID: UUID, date: CalendarDate)?
}

public protocol NotificationScheduling: Sendable {
    func pendingAlertIdentifiers() async -> Set<String>    // only identifiers with identifierPrefix
    func schedule(_ alerts: [PlannedAlert]) async throws   // same identifier replaces the pending one
    func cancel(identifiers: Set<String>) async
}

public struct AlertSyncResult: Hashable, Sendable { public var added: [String]; public var removed: [String] }
public actor AlertSynchronizer {
    public init(scheduler: any NotificationScheduling, planner: AlertPlanner)
    public func sync(library: Library, now: Date) async throws -> AlertSyncResult   // touches only the difference
    public func cancelAll() async
}
```

- **Only the nearest alerts are pending** (14 days, at most 48; macOS keeps 64 per app), so they fire while
  Ithil is quit. The app re-plans often enough (see Notifications (app)) that the window always moves on.
- **Timed events** fire `minutesBefore` minutes of elapsed time before the start. **All-day events** fire
  relative to 09:00 on their first day in the display time zone, in wall-clock time.
- **Identifiers** are `ithil.alert.<event UUID>.<yyyy-MM-dd>.<minutes>.<hash>`; the hash covers title,
  location, start, end, all-day and the offset, so any change to what the alert says gives a new identifier
  and `AlertSynchronizer` replaces it. The display time zone isn't part of it: after a time zone change the
  app makes a new synchronizer and calls `cancelAll()` first.
- Calls to one synchronizer are serialized in arrival order, so the latest library always wins.

## Files (`IthilCore/Files`)

```
<root>/2026-10-06/14.00 Physics Lecture/                 timed: day and HH.mm in the event's own time zone
<root>/2026-10-06/14.00 Physics Lecture/.ithil-event     EventFolderMarker {eventID, date, version}
<root>/2026-10-14/Mara's birthday/                       all-day: first day, title only
```

```swift
public enum FolderNaming {
    public static let maximumTitleLength = 80              // Characters (fewer for very wide ones: ≤ 240 bytes)
    public static let fallbackTitle = "Event"
    public static func sanitizedTitle(_ title: String) -> String   // no / or :, no leading dots, trimmed, cut
    public static func dayFolderName(for occurrence: Occurrence) -> String     // "2026-10-06"
    public static func eventFolderName(for occurrence: Occurrence) -> String   // "14.00 Physics Lecture"
    public static func relativePath(for occurrence: Occurrence) -> String      // "2026-10-06/14.00 Physics Lecture"
}

public struct EventFolderMarker: Codable, Hashable, Sendable { public static let fileName = ".ithil-event" … }
public struct EventFile: Hashable, Sendable, Identifiable {
    public var url: URL; public var name: String; public var byteCount: Int64
    public var modified: Date?; public var isDirectory: Bool
}
public enum EventFoldersError: Error { case outsideRoot(String), notADirectory(String) }

public actor EventFolders {
    public nonisolated let root: URL
    public init(root: URL, fileSystem: any FileSystem)
    public func existingFolder(for occurrence: Occurrence) -> URL?      // never creates one
    public func ensureFolder(for occurrence: Occurrence) throws -> URL  // only when the first file arrives
    public func files(for occurrence: Occurrence) -> [EventFile]        // visible items, Finder order
    public func fileCount(for occurrence: Occurrence) -> Int
    @discardableResult public func relocate(from old: Occurrence, to new: Occurrence) throws -> URL?
    @discardableResult
    public func trashFolder(for occurrence: Occurrence) throws -> URL?  // Trash, never a permanent delete;
                                                                        // returns where it is in the Trash
    public func restoreFolder(from trashed: URL, for occurrence: Occurrence) throws -> URL   // Undo of a delete
    public func reindex()                                               // rescan every marker
    public func markedFolders() -> [Occurrence.ID: URL]                 // after a full rescan
    public nonisolated func contains(_ url: URL) -> Bool                // inside root, links resolved
}

public struct FileCopyProgress: Hashable, Sendable {
    public var completedBytes: Int64; public var totalBytes: Int64
    public var completedFiles: Int; public var totalFiles: Int; public var currentName: String?
    public var fractionCompleted: Double { get }
}
public enum FileImport {
    public static func availableName(for name: String, in folder: URL, fileSystem: any FileSystem) -> String
    public static func copy(_ sources: [URL], into folder: URL, root: URL, fileSystem: any FileSystem,
                            progress: @escaping @Sendable (FileCopyProgress) -> Void) async throws -> [URL]
}
public enum LibraryMove {
    public static func move(from oldRoot: URL, to newRoot: URL, fileSystem: any FileSystem) throws
}
```

- **The folder is the source of truth.** Folders are created only by `ensureFolder` (when the first file
  arrives); every lookup finds folders by their expected path first, then by marker, so a folder renamed or
  moved to another day folder in Finder is still found. A folder the user made at the expected path is
  adopted by writing a marker.
- **Copy, never move:** `FileImport.copy` copies each item under a hidden temporary name and renames it into
  place when complete; clashes get " 2", " 3"… like Finder. Cancelling leaves the finished items.
- **Nothing outside the root:** every create, write, move and trash checks `contains(_:)` (symbolic links
  resolved). **Nothing deleted:** folders and files go to the Trash; only completely empty day folders are
  removed (`rmdir`).
- `restoreFolder(from:for:)` puts a trashed folder back at the occurrence's expected path, for Undo. It
  refuses (`CocoaError.fileNoSuchFile`) anything that isn't a real folder whose marker names the occurrence,
  and (`.fileWriteFileExists`) an occurrence that already has a folder again; a taken name gets " 2" like
  Finder; every target is checked to be inside the root; the day folder is created if needed, never the root.
  On failure the folder stays in the Trash.
- `LibraryMove` moves `.ithil` and the day folders (renames on one volume, copy then move across volumes),
  `.ithil` last, and moves everything back if one item fails.

## App layer (`Ithil/`)

Files and their owners (Phase 2, then Phases 3, 4 and 5). Shared types are declared once, by the owner listed;
everyone else uses them exactly as specified here.

```
Ithil/
  IthilApp.swift                 App: scenes, commands, environment wiring           (shell)
  App/LaunchOptions.swift        -demo, -demoNow parsing                              (shell)
  App/AppModel.swift             @Observable app model (below)                        (shell)
  App/AppSettings.swift          @Observable UserDefaults-backed settings             (shell)
  App/LibrarySaveQueue.swift     latest-wins background saver                         (shell)
  App/FolderAccess.swift         security-scoped bookmarks, open/save panels          (shell)
  App/ClockMonitor.swift         minute ticks, day change, time zone change, wake     (shell)
  App/Appearance.swift           Night / Dawn / Match System → NSApp.appearance       (shell)
  App/AppDelegate.swift          quitting waits (up to 5 s) for the last save         (shell)
  App/IthilCommands.swift        About; New Event… ⌘N; Find… ⌘F; View: Today, Day/Week/Month, ‹ ›; Help (shell)
  App/OccurrenceCache.swift      MRU cache of occurrence queries                      (shell)
  App/LibraryMessages.swift      user-facing load/save/recovery sentences             (shell)
  App/ModelTypeAliases.swift     `Subject` = IthilCore.Subject (Combine has one too)  (integration)
  Views/MainView.swift           switches on AppModel.state                           (shell)
  Views/FolderSetup/*.swift      choose folder, folder missing, library problems      (shell)
  Views/CalendarWindow.swift     NavigationSplitView + toolbar + .searchable          (sidebar)
  Views/Toolbar/*.swift          title, ‹ Today ›, Day/Week/Month, + button           (sidebar)
  Views/Sidebar/*.swift          mini month, Up next, Subjects                        (sidebar)
  Views/Search/*.swift           search results + empty state                         (sidebar)
  Views/Components/*.swift       SubjectStyle, SubjectDot, EventFormatting            (sidebar)
  Views/Calendar/*.swift         TimeGrid (week/day), event blocks, now line, month   (calendar)
  Views/Editor/*.swift           new/edit event popover                               (editor)
  Views/Details/*.swift          event details popover                                (editor)
  Views/QuickAdd/*.swift         Quick Add NSPanel + view                             (editor)
  Views/Settings/*.swift         Settings window: General, Subjects, Files            (editor)
  App/LibraryChangeObserver.swift  LibraryChange + observer protocol (AppModel → controllers)   (shell)
  App/Files/*.swift              FilesController, RootFolderWatcher, DemoFiles, folder carry plan (files-app)
  App/Notifications/*.swift      NotificationsController, scheduler, delegate, alert text      (notify)
  Views/Files/*.swift            file list, drop targets, editor drop zone, Add Files panel     (files-ui)
  Views/Notifications/*.swift    the explain-then-ask permission card                           (notify)
  App/HotKey/*.swift             HotKeyCombo, GlobalHotKey (Carbon), QuickAddHotKeyController, VirtualKey (hotkey)
  App/LaunchAtLogin.swift        SMAppService.mainApp wrapper                                   (hotkey)
  Views/Settings/HotKeyRecorder.swift  the shortcut recorder field                              (hotkey)
  App/AppLinks.swift             GitHub URLs for About and Help, opened in the browser          (menubar)
  Views/MenuBar/*.swift          MenuBarContent/Label, agenda, navigation, RaisedPanelBackground (menubar)
  Views/About/*.swift            the About window                                               (menubar)
  Views/Onboarding/*.swift       the three first-launch pages                                   (onboarding)
  App/SearchFocus.swift          Edit › Find… focuses the toolbar search field                  (keyboard)
  App/Files/FolderRestorePlan.swift  which folders an Undo / Redo moves (pure)                  (keyboard)
  Views/Calendar/TimeGridDrag.swift, EventBlockEditing.swift   drag to move / resize, ⌥-arrows  (keyboard)
  Views/Calendar/CalendarDeleteCommand.swift   Delete key on the calendar                       (keyboard)
```

`Subject` also names a Combine protocol that SwiftUI makes visible, so the app declares
`typealias Subject = IthilCore.Subject` once (`App/ModelTypeAliases.swift`); declarations in the app module
win over imported ones, so `Subject` always means the model type in app code.

### `AppModel` (`@Observable @MainActor final class`, injected with `.environment(model)`)

```swift
enum LibraryState: Equatable {
    case needsFolder                                // first launch
    case loading
    case ready
    case folderMissing(path: String)                // bookmark broken or folder gone: "Locate or choose folder"
    case noLibrary(path: String)                    // folder exists, no events.json, nothing to recover
    case unreadable(path: String, message: String)  // corrupt and unrecoverable
}

private(set) var state: LibraryState
private(set) var library: Library
private(set) var isReadOnly: Bool                   // folder written by a newer Ithil
var recoveryNotice: RecoveryReport?                 // set after a recovery; UI shows an alert, then sets nil
var saveError: String?                              // last save failure; UI shows an alert, then sets nil
private(set) var rootURL: URL?
let isDemo: Bool

private(set) var now: Date                          // ticks every minute, on wake, day change, time zone change
private(set) var math: CalendarMath                 // display time zone + first weekday
var today: CalendarDate { get }
var timeZone: TimeZone { get }

var span: CalendarSpan                              // default .week
var selectedDate: CalendarDate                      // the day views are centered on
var selectedOccurrenceID: Occurrence.ID?
var searchText: String
var visibleDays: [CalendarDate] { get }             // math.visibleDays(for: span, around: selectedDate)
func goToToday()
func step(_ count: Int)                             // ‹ / › by the current span
func show(_ date: CalendarDate, span: CalendarSpan?)

private(set) var hiddenSubjectIDs: Set<UUID>        // persisted per Mac
func isVisible(_ subjectID: UUID?) -> Bool          // events without a subject are always visible
func setVisible(_ visible: Bool, subjectID: UUID)
func subject(for event: Event) -> Subject?
func addSubject(_ subject: Subject)
func updateSubject(_ subject: Subject)
func deleteSubject(id: UUID)                        // its events keep existing with no subject

func occurrences(in days: [CalendarDate]) -> [Occurrence]   // visible subjects only, sorted
func occurrences(on day: CalendarDate) -> [Occurrence]
var upNext: [Occurrence] { get }                            // next 4, visible subjects only
var searchResults: [Occurrence] { get }                     // EventSearch over searchText
func occurrence(id: Occurrence.ID) -> Occurrence?

func newEvent(on day: CalendarDate, startMinute: Int?) -> Event   // 1 h, default alert, not yet added
func add(_ event: Event)
func update(_ occurrence: Occurrence, with edited: Event, scope: SeriesEditing.Scope,
            undoAction: LibraryUndoAction = .editEvent)    // .moveEvent from drag / ⌥-arrows
func delete(_ occurrence: Occurrence, scope: SeriesEditing.Scope)

func useFolder(_ chosen: URL)                       // applies RootFolderPolicy, then creates or loads
func startFresh()                                   // from .noLibrary: create an empty library there
func retryLoad()
func makeQuickAddParser() -> QuickAddParser

var pendingEditorOccurrenceID: Occurrence.ID?       // set by Quick Add ⌘↩: the calendar opens its editor

// Beyond the original contract (shell); other areas rely on these:
init(options: LaunchOptions, settings: AppSettings, defaults: UserDefaults)
func start()                                        // once, from App.init: clock, then demo / saved folder / .needsFolder
var canEdit: Bool { get }                           // .ready, not read-only, not moving; editors and Files guard on it
var isMovingLibrary: Bool                           // set by FilesController.moveLibrary: no edits until it reopens
func addChangeObserver(_ observer: any LibraryChangeObserver)   // held weakly; see "Library change observers"
private(set) var libraryRevision: Int               // bumped on every change to `library`
var folderError: String?                            // chosen folder unusable; UI shows an alert, then sets nil
var showsRecoveryNotice: Bool, showsSaveError: Bool, showsFolderError: Bool   // alert bindings
func relocateFolder(_ chosen: URL)                  // "Locate Folder…": only an Ithil folder (or one holding `Ithil`)
func retrySave()
var hasPendingSaves: Bool { get }
func finishPendingSaves(timeout: Duration) async    // AppDelegate, on quit
func refreshClock()                                 // ClockMonitor: minute ticks, day change, clock change
func refreshCalendar()                              // ClockMonitor: time zone / locale change, wake; first-weekday setting
static var preview: AppModel { get }                // demo library in memory, for #Preview

// Undo / Redo (Phase 5, keyboard):
@ObservationIgnored weak var undoManager: UndoManager?   // set by MainView from @Environment(\.undoManager);
                                                         // capped at 100 levels when set
func restore(_ snapshot: Library, actionName: String)    // puts a snapshot back, registers the inverse
enum LibraryUndoAction { case addEvent, editEvent, moveEvent, deleteEvent, editSubjects; var name: String }
```

- `today` is stored (`private(set) var`), kept current by `refreshClock` / `refreshCalendar`; the views follow a
  day change when they were on today. The model observes `AppSettings.firstWeekday` itself.
- `-demoNow` only takes effect together with `-demo`. In `-demo`, `useFolder` / `relocateFolder` show an alert
  and change nothing.
- A folder written by a newer Ithil opens read-only (`isReadOnly`, banner, no save queue). A failed save keeps the
  calendar open and shows an alert with "Try Again".
- `update` / `delete` only change the library; `FilesController` hears about them as a `LibraryChange` and
  renames, moves or trashes the event folders.

**Undo and Redo** are snapshots: every `add` / `update` / `delete` and subject change registers an undo step
that holds the library from before it (`Library` is a value type, so this is cheap to take; at most 100 steps
are kept). Undoing calls `restore(_:actionName:)`, which commits the snapshot (and saves it), registers the
opposite step under the same name (so Redo works), and notifies observers with `.restored`. Names: "Add
Event", "Edit Event", "Move Event", "Delete Event", "Edit Subjects"; edits of one subject less than two
seconds apart share a step (typing a name, dragging the color picker). Nothing is registered while the
library can't be edited (loading, read-only, moving), and a snapshot of another library is ignored. Subject
edits made in Settings land on the main window's undo manager.

Every mutation updates `library` immediately (the UI never waits) and hands a snapshot to
`LibrarySaveQueue`, which saves on the `LibraryStore` actor. A newer snapshot replaces any pending one.

### `AppSettings` (`@Observable @MainActor final class`, injected with `.environment(settings)`)

```swift
enum AppearanceChoice: String, CaseIterable { case night, dawn, system }
var appearance: AppearanceChoice        // default .night
var defaultAlert: AlertOffset?          // default 10 minutes
var firstWeekday: Int?                  // nil = follow the locale; 1 = Sunday … 7 = Saturday
var effectiveFirstWeekday: Int { get }
var showsMenuBarExtra: Bool             // default true
var quickAddHotKey: HotKeyCombo?        // default .optionSpace; nil = off (stored as "off")
var hasCompletedOnboarding: Bool        // default false; always true in -demo and previews
init(defaults: UserDefaults = .standard, isDemo: Bool = LaunchOptions.current.isDemo)
static var preview: AppSettings { get }
```

Setting `appearance` applies it to `NSApp.appearance` at once (`Appearance.apply`).

In `-demo` mode settings live in a throwaway `UserDefaults` suite, so nothing real is touched.

### Shared view helpers (`Views/Components`)

```swift
@MainActor enum SubjectStyle {
    static func color(for subject: Subject?) -> Color          // palette asset or custom; textSecondary if nil
    nonisolated static func resource(for palette: PaletteColor) -> ColorResource   // the asset of a palette slot
    static func fill(for subject: Subject?, scheme: ColorScheme) -> Color     // 20 % Night / 15 % Dawn
    static func border(for subject: Subject?, scheme: ColorScheme) -> Color   // ~35 %
    static func text(for subject: Subject?, scheme: ColorScheme) -> Color     // AA-safe title color
}
struct SubjectDot: View { init(subject: Subject?, size: CGFloat = 8) }

enum EventFormatting {
    static func time(_ date: Date, timeZone: TimeZone) -> String                   // locale 12/24 h
    static func timeRange(_ occurrence: Occurrence, timeZone: TimeZone) -> String  // "14:00 – 15:30"
    static func longDate(_ day: CalendarDate, timeZone: TimeZone, includeYear: Bool = false) -> String
        // "Tuesday, 6 October"
    static func dayAndTime(_ occurrence: Occurrence, timeZone: TimeZone, includeYear: Bool = false) -> String
        // "Tuesday, 6 October · 14:00 – 15:30"
    static func upNextSubtitle(_ occurrence: Occurrence, now: Date, math: CalendarMath) -> String
        // "in 10 min · 14:00 · Room B204" / "Today · 17:00" / "Tomorrow · 09:00" / "Thursday · 10:00"
    static func recurrence(_ event: Event, timeZone: TimeZone) -> String?          // "Every Tuesday"
    static func alert(_ alert: AlertOffset?) -> String                             // "10 minutes before"
    static func accessibilityLabel(_ occurrence: Occurrence, timeZone: TimeZone) -> String
        // "Physics Lecture, 2:00 PM to 3:30 PM" / "Essay due, all day"

    // Helpers used across areas:
    static func upNextParts(_ occurrence: Occurrence, now: Date, math: CalendarMath) -> [String]
    static func joined(_ parts: [String]) -> String                 // " · "
    static func spokenJoined(_ parts: [String]) -> String           // ", " for VoiceOver
    static func displayTitle(_ event: Event) -> String              // "New Event" when empty
    static func displayDay(of occurrence: Occurrence, timeZone: TimeZone) -> CalendarDate
    static func monthName(_ day: CalendarDate) -> String            // "October"
    static func year(_ day: CalendarDate) -> String                 // "2026"
    static func monthAndYear(_ day: CalendarDate) -> String         // "October 2026"
    static func shortDate(_ day: CalendarDate, includeYear: Bool = false) -> String   // "Mon 12 Oct"
    static func veryShortWeekdaySymbol(_ weekday: Int) -> String    // "M"
}
```

Also shared from the editor area: `EventChangeContext`, `View.confirmsEventChange(_:isPresented:context:perform:)`
(the "This Event Only / All Future Events" and delete questions), `AlertChoices.offered(including:)`,
`SubjectSwatch.image(for:)` (colored menu dots) and `EditorDuration`. From the shell: `FolderAccess.displayPath(_:)`
("~/…").

### Views provided to each other

```swift
struct EventEditorView: View {                       // editor
    enum Mode { case new(Event), edit(Occurrence) }
    init(mode: Mode, onClose: @escaping () -> Void)
}
struct EventDetailsView: View {                      // editor
    init(occurrence: Occurrence, onEdit: @escaping () -> Void, onClose: @escaping () -> Void)
}
@MainActor final class QuickAddPanelController {     // editor
    static let shared: QuickAddPanelController
    func toggle(model: AppModel, settings: AppSettings)
    func show(model: AppModel, settings: AppSettings)
    func close()
    var isShown: Bool { get }
}
struct SettingsView: View { init() }                 // editor
struct CalendarWindow: View { init() }               // sidebar: split view, toolbar, search, detail
struct DayWeekView: View { init(days: [CalendarDate]) }   // calendar: time grid for 1 or 7 days
struct MonthView: View { init(month: CalendarDate) }      // calendar: month of the given day
struct EmptyStateView: View                          // existing
```

- Popovers: the calendar owns the event blocks and shows `EventDetailsView` (single click or Return on a
  focused event) and `EventEditorView` (double-click, Edit in the details, the VoiceOver "Edit" action, or
  `pendingEditorOccurrenceID`) as `.popover` on the block. In a read-only folder the details stand in for the
  editor. Quick Add's ⌘↩ adds the event, calls `show(day, span: nil)` and then sets
  `pendingEditorOccurrenceID`; only the first on-screen segment of an occurrence opens the editor.
  The toolbar's + shows `EventEditorView(.new)` as a popover on the button. Editing a repeating occurrence
  asks "This Event Only" / "All Future Events" with a `confirmationDialog` before saving or deleting.
- Every user-facing string is a `LocalizedStringKey` / `String(localized:)` literal so it lands in
  `Localizable.xcstrings`.
- VoiceOver: every interactive element has a label; event blocks use `EventFormatting.accessibilityLabel`.

### Library change observers (`App/LibraryChangeObserver.swift`)

```swift
enum LibraryChange {
    case opened(root: URL)                                   // never change the disk in response
    case added(Event)
    case updated(Occurrence, edited: Event, scope: SeriesEditing.Scope)
    case deleted(Occurrence, scope: SeriesEditing.Scope)     // the UI asked first
    case subjectsChanged
    case restored                                            // Undo / Redo put back a snapshot
}
@MainActor protocol LibraryChangeObserver: AnyObject {
    func libraryDidChange(_ change: LibraryChange, from old: Library, to new: Library)
}
```

`AppModel` holds observers weakly and calls them on the main actor right after `library` changed, in the order
they registered. `FilesController` registers first, then `NotificationsController`.

### Files (app) (`App/Files`, `Views/Files`)

```swift
@Observable @MainActor final class FilesController: LibraryChangeObserver {   // .environment(files)
    init(model: AppModel)                         // registers as observer; follows an already open library
    private(set) var root: URL?
    private(set) var fileCounts: [Occurrence.ID: Int]          // missing = not loaded yet (show nothing)
    private(set) var changeToken: Int                          // bumped when files may have changed
    private(set) var imports: [Occurrence.ID: FileCopyProgress]
    private(set) var isMovingLibrary: Bool
    var lastError: String?                                     // MainView shows it as an alert
    var showsLastError: Bool                                   // alert binding
    func requestCounts(for occurrences: [Occurrence])          // batched (50 ms, 500 a turn), off the main thread
    func fileCount(for occurrence: Occurrence) -> Int?         // asks for unknown counts itself
    func files(for occurrence: Occurrence) async -> [EventFile]
    func addFiles(_ urls: [URL], to occurrence: Occurrence)    // copies; queued after a running copy into it
    func cancelImport(for occurrence: Occurrence)
    func folderURL(for occurrence: Occurrence) async -> URL?
    func revealInFinder(_ occurrence: Occurrence)              // opens the event folder, else day folder, else root
    func reveal(_ file: EventFile)
    func open(_ file: EventFile)
    func moveToTrash(_ file: EventFile)
    func displayPath(for occurrence: Occurrence) -> String     // "Ithil › 2026-10-06 › 14.00 Physics Lecture"
    func folderName(for occurrence: Occurrence) -> String      // "14.00 Physics Lecture"
    func makeFileCountProvider() -> @Sendable (Occurrence) async -> Int
    func moveLibrary(to destination: URL) async throws         // the chosen folder (LibraryFolderChoice picks the root)
    func openLibrary(at folder: URL)
    static var preview: FilesController { get }                // demo files in memory, no disk
}
```

- **Following the library:** `.opened` starts a session (new `EventFolders`, marker index, `RootFolderWatcher`,
  counts cleared; in `-demo` the sample files from `DemoFiles`, the only disk write on `.opened`). `.updated`
  carries the edited event's folders along (`FolderCarryPlan`: same event on the same date, a detached
  occurrence, or the moved series after an "all future" split); folders with no new home stay put.
  `.deleted` trashes only the deleted occurrences' folders. `.added` / `.subjectsChanged` touch nothing.
- **Undo and Redo** (`.restored`): `FolderRestorePlan` compares the two libraries and moves each changed
  event's folders to where the restored library expects them (the same event moved back, a detached
  occurrence rejoining its series, a split series joining up again, and the reverse for Redo). Folders this
  session trashed (`trashFolder` returns their URL in the Trash) come back with `restoreFolder` when an
  occurrence that was missing before the step exists after it; the check runs when the work runs, so a
  quick Redo that deletes it again leaves the folder in the Trash. A restore never trashes anything: after
  Redo of a delete, the folder stays in the root until Undo links it up again. Failures say "Ithil couldn't
  bring the folder of “…” back from the Trash. It's still in the Trash."
- **Disk work runs one at a time** (copies, renames, the Trash, a library move) in the order it was asked
  for; work for an earlier library is dropped when another opens.
- **FSEvents** (`RootFolderWatcher`, file-level, 0.3 s, main queue): `FolderChangeFilter` sorts paths into
  structural changes (reindex), content changes (refresh counts) and noise (`.ithil` saves, `.DS_Store`,
  copies in progress). Every refresh bumps `changeToken`; file lists reload on it.
- **Moving the library** (Settings → Files): waits for pending saves, refuses while copies run, sets
  `AppModel.isMovingLibrary` (so `canEdit` is false and no save lands in a moving folder), moves with
  `LibraryMove`, then `model.useFolder(newRoot)` and waits for it to open. Changes that still arrive during the
  move are replayed afterwards.
- **Views:** `EventBlockView` (paperclip + count, drop target, 2 pt progress bar, ", 4 files" for VoiceOver),
  `EventDetailsView` → `EventFilesSection` / `EventFileList` (Space Quick Look, Return / double-click open,
  Delete asks, context menu), `EventEditorView` → `EditorFilesSection` (a new event keeps dropped files until
  it is added), `FilesSettingsView` (Show in Finder, Change…). Shared pieces: `View.fileDropTarget`,
  `FileDragState`, `FileDropGlow`, `FileDropPrompt`, `FileImportProgressRow`, `AddFilesPanel`, `FileLabels`,
  `FileIcons` (from the type only, so drawing never reads the disk). Deleting an event with files says
  so and its button is "Move to Trash" (`EventChangeContext.fileCount`).

### Notifications (app) (`App/Notifications`, `Views/Notifications`)

```swift
@Observable @MainActor final class NotificationsController: LibraryChangeObserver {   // .environment(notifications)
    enum Authorization: Equatable { case unknown, notDetermined, denied, authorized }
    init(model: AppModel, files: FilesController)   // observer; attaches to NotificationDelegate; live: categories
    private(set) var authorization: Authorization    // .unknown until read, and always in -demo
    var isPromptDismissed: Bool                      // "Not Now" (UserDefaults; memory only in -demo)
    var hasUpcomingAlerts: Bool { get }              // any planned alert in 14 days (cached per revision/minute)
    @ObservationIgnored var openMainWindow: (() -> Void)?   // set by MainView: openWindow(id: "main")
    func refreshAuthorization() async
    func requestAuthorization() async                // only from a button the user pressed
    func openSystemSettings()
    func scheduleSync()                              // debounced 1 s
    func timeZoneDidChange()                         // new pipeline, cancelAll, then sync
    func handleResponse(identifier: String, actionIdentifier: String)
    static var preview: NotificationsController { get }
}
struct UserNotificationScheduler: NotificationScheduling   // UNUserNotificationCenter; calendar triggers
final class NotificationDelegate: NSObject, UNUserNotificationCenterDelegate { static let shared; static func install() }
enum AlertText                                       // "Physics Lecture in 10 min" / "14:00 – 15:30 · Room B204 · 4 files"
struct NotificationPermissionView: View              // explain-then-ask card: sidebar, Settings, onboarding
```

- **When it syncs:** about a second after the library opens or changes, after files change (`changeToken`,
  for "N files" and the Open Files action), on wake, at midnight (`NSCalendarDayChanged`), when the clock,
  region settings or display time zone change, when permission becomes authorized, and every hour. A system
  time zone change (`NSSystemTimeZoneDidChange`) calls `timeZoneDidChange()`. Syncs never overlap.
- **Requests:** one `UNCalendarNotificationTrigger` per alert (Gregorian, era to second, with the planning
  zone), sound, thread = event ID, category `EVENT_FILES` (with "Open Files", `.foreground`) when the event has
  files, else `EVENT`. Pending alerts whose text is out of date are rewritten under the same identifier.
- **Clicks:** `NotificationDelegate` is the center's delegate from `applicationWillFinishLaunching`; its
  `nonisolated` methods copy the strings out and hop to the main actor. "Open Files" → `files.revealInFinder`;
  a plain click activates Ithil, shows the day, selects the occurrence and brings the main window forward
  (or `openMainWindow`). A click that launched Ithil waits until the library is `.ready`.
- **Permission:** read at launch and whenever Ithil becomes active. The sidebar card shows while an alert is
  coming up in the next 14 days and permission is not determined (until "Not Now") or denied. Settings →
  General has a Notifications row.
- **`-demo`** never reads permission or schedules anything (it would replace the user's real alerts).

### Phase 5: menu bar, hotkey, onboarding, keyboard

```swift
struct HotKeyCombo: Codable, Hashable, Sendable {          // hotkey
    var keyCode: UInt32; var carbonModifiers: UInt32; var keyName: String
    static let optionSpace: HotKeyCombo
    var displayString: String { get }                       // "⌥Space", ⌃⌥⇧⌘ order
    @MainActor init?(event: NSEvent)                        // nil unless ⌘, ⌥ or ⌃ is held
    var hasRequiredModifier: Bool { get }
    @MainActor var isMainMenuShortcut: Bool { get }         // the recorder refuses Ithil's own menu shortcuts
}
@MainActor final class GlobalHotKey {                      // Carbon RegisterEventHotKey; sandbox-safe, no prompt
    enum RegistrationResult { case registered, off, unavailable }
    init(onPress: @escaping @MainActor () -> Void)
    @discardableResult func register(_ combo: HotKeyCombo?) -> RegistrationResult
    func unregister()
}
@Observable @MainActor final class QuickAddHotKeyController {   // owns the one GlobalHotKey
    static let shared: QuickAddHotKeyController
    private(set) var status: GlobalHotKey.RegistrationResult   // for Settings' "Another app is using this shortcut"
    func start(settings: AppSettings, onPress: @escaping @MainActor () -> Void)   // once, from IthilApp
    func suspend(); func resume()                              // while the recorder records
}
@MainActor enum LaunchAtLogin {                            // SMAppService.mainApp
    enum Status { case on, off, requiresApproval }
    static var status: Status { get }; static func set(_ on: Bool) throws; static func openLoginItemsSettings()
}
enum AppLinks { static let repository, releases, newIssue, license: URL; static func open(_ url: URL) }  // menubar
struct MenuBarContent: View; struct MenuBarLabel: View     // menubar: the MenuBarExtra window and its moon
struct AboutView: View { static let windowID = "about" }   // menubar
struct OnboardingView: View {                              // onboarding
    enum Step { case welcome, chooseFolder, notifications }
    init(startAt: Step, onFinish: @escaping () -> Void = {})  // sets hasCompletedOnboarding when done
}
struct ChooseFolderActions: View                           // shared by ChooseFolderView and onboarding
@MainActor enum SearchFocus { static func focus() }        // keyboard: Edit › Find… ⌘F
```

- **Global hotkey:** Carbon `RegisterEventHotKey` on the application event target with one
  `InstallEventHandler` callback (`@convention(c)`, unretained context, `MainActor.assumeIsolated`; presses
  arrive on the main thread). It registers exclusively first, so a shortcut another app holds reports
  `.unavailable`; shortcuts macOS itself uses (`CopySymbolicHotKeys`) and ones without ⌘, ⌥ or ⌃ are
  `.unavailable` too. `QuickAddHotKeyController` re-registers whenever `settings.quickAddHotKey` changes
  (`withObservationTracking`). A press toggles the Quick Add panel. ⌘N in the app is unaffected.
- **Menu bar extra:** `MenuBarExtra(isInserted: $settings.showsMenuBarExtra)` with `.menuBarExtraStyle(.window)`:
  today's date, the next event (`model.upNext.first`) with Open Files when it has files, Today and Tomorrow
  (6 rows each, then "N more"), and Quick Add… / Open Ithil ⌘O / Settings… ⌘, / Quit Ithil ⌘Q. Clicking an
  event shows it in the main window (`MenuBarNavigation`), which also closes the menu bar window.
- **Liquid Glass (macOS 26+ only):** the Quick Add panel keeps its opaque `BackgroundRaised` fill, inset
  2 pt over a `.glassEffect(.regular)`, so only a glass rim shows and all text stays on the opaque token
  color (`RaisedPanelBackground`). The menu bar window stays opaque inside the system's own glass window.
  macOS 14 and 15 draw exactly as before.
- **About and Help:** Ithil › About Ithil opens `Window(id: "about")`. Help: "Ithil on GitHub", "Check for
  Updates…", "Report an Issue…" open the GitHub pages in the browser (`NSWorkspace.open`); the app makes no
  network request.
- **Find:** Edit › Find… ⌘F (before the system's text-editing group) focuses the toolbar search field
  (`NSSearchToolbarItem.beginSearchInteraction`, else the first `NSSearchField` in the window). While a text
  view is editing, ⌘F goes to that text's own find bar instead. Disabled unless the calendar is `.ready`.
- **Onboarding:** `MainView` shows `OnboardingView(startAt: .welcome)` for `.needsFolder` and
  `OnboardingView(startAt: .notifications)` for `.ready` until `hasCompletedOnboarding`; then
  `ChooseFolderView` and the calendar. Reduce Motion turns the page slide into a cross-fade.
- **Keyboard and drag:** Delete (`.onDeleteCommand` on Day/Week and Month) asks the same question as the
  details and editor. Blocks drag to move (15-minute snapping; whole days across Week columns) and resize at
  their bottom 6 pt (minimum 15 minutes), with a preview and no animation; a repeating occurrence asks
  "This Event Only" / "All Future Events" first, and Cancel puts it back. ⌥↑ / ⌥↓ move a focused block 15
  minutes and ⌥⇧↑ / ⌥⇧↓ change its end; VoiceOver has the same four actions. All of it is one "Move
  Event" undo step through `model.update(…, undoAction: .moveEvent)`.
- **Increase Contrast:** `TextSecondary`, `TextTertiary`, `AccentText`, `SeparatorLine` and `ControlFill`
  have high-contrast variants in the asset catalog (see docs/DESIGN.md).

### App wiring (integration)

- `IthilApp.init`: `AppSettings` → `AppModel` → `FilesController(model:)` → `NotificationsController(model:files:)`
  → `model.start()`, so both observers are registered before any library opens (and `FilesController` also
  follows a library that is already open). All four are `@State` on the app and injected with `.environment`
  into the main `WindowGroup(id: "main")`, the `Settings` scene and the `MenuBarExtra`. Previews use the
  `.preview` instances. `AppSettings` gets `isDemo: options.isDemo`.
- Scenes: `WindowGroup(id: "main")`, `Settings`, `Window("About Ithil", id: "about")` (content size, hidden
  title bar, centered, no Window-menu command) and `MenuBarExtra(isInserted: $settings.showsMenuBarExtra)`.
- Once the run loop runs (`Task { @MainActor in … }` in `init`), `QuickAddHotKeyController.shared.start` registers
  the global shortcut; a press calls `QuickAddPanelController.shared.toggle(model:settings:)`.
- `AppDelegate.applicationWillFinishLaunching` calls `NotificationDelegate.install()`; the controller attaches
  itself and observes `didBecomeActive` for the permission, so the delegate needs nothing else.
- Clock events: `ClockMonitor` keeps `AppModel` current; `NotificationsController` observes the same system
  notifications itself (day change, clock, time zone, locale, wake) instead of a callback from the model,
  so neither the model nor the monitor knows about notifications.
- `MainView` shows `files.lastError` ("There was a problem with your files") next to the model's alerts,
  sets `notifications.openMainWindow`, sets `model.undoManager` from `@Environment(\.undoManager)` (on appear
  and when it changes), and picks onboarding or the regular screens as described above.

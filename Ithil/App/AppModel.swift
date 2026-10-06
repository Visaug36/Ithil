import Foundation
import IthilCore
import Observation
import os

/// Where the app is in opening its library folder. `MainView` shows one screen per state.
enum LibraryState: Equatable {
    /// First launch: no folder chosen yet.
    case needsFolder
    case loading
    case ready
    /// The bookmark is broken or the folder is gone (moved, deleted, drive unplugged): "Locate or choose
    /// folder". Ithil never starts an empty calendar from here.
    case folderMissing(path: String)
    /// The folder exists but has no events.json and nothing to recover it from.
    case noLibrary(path: String)
    /// events.json is damaged and couldn't be recovered, or it is from a newer Ithil and couldn't be read.
    case unreadable(path: String, message: String)
}

private let logger = Logger(subsystem: "io.github.visaug36.Ithil", category: "AppModel")

/// The app's state: the open library, the clock and calendar math, navigation, and every change to
/// events and subjects. Injected once with `.environment(model)`.
///
/// - Changes update `library` at once and hand a snapshot to `LibrarySaveQueue`, which saves it on the
///   `LibraryStore` actor; the main thread never waits for the disk. While `isReadOnly` (a folder written
///   by a newer Ithil) or not `.ready`, changes are ignored.
/// - Queries leave out events of hidden subjects and are cached per library revision and day range, so
///   switching weeks and months stays instant with thousands of events.
/// - `now`, `today` and `math` are kept current by `ClockMonitor` (minute ticks, day changes, time zone
///   and locale changes, wake). `math` is also rebuilt when `AppSettings.firstWeekday` changes.
@Observable @MainActor
final class AppModel {
    // MARK: - Library

    private(set) var state: LibraryState = .loading
    private(set) var library = Library()
    /// The folder was written by a newer Ithil: shown, never changed.
    private(set) var isReadOnly = false
    /// Set after a recovery; the UI shows an alert, then sets nil.
    var recoveryNotice: RecoveryReport? = nil
    /// The last save failure; the UI shows an alert, then sets nil.
    var saveError: String? = nil
    /// Why the folder the user just chose can't be used; the UI shows an alert, then sets nil.
    var folderError: String? = nil
    /// The library folder, while `.ready`.
    private(set) var rootURL: URL? = nil
    let isDemo: Bool
    /// Bumped on every change to `library`.
    private(set) var libraryRevision = 0

    // MARK: - Clock and calendar

    private(set) var now: Date
    /// Display time zone and first weekday.
    private(set) var math: CalendarMath
    private(set) var today: CalendarDate
    var timeZone: TimeZone { math.timeZone }

    // MARK: - Navigation

    /// Default `.week`.
    var span: CalendarSpan = .week
    /// The day the views are centered on.
    var selectedDate: CalendarDate
    var selectedOccurrenceID: Occurrence.ID? = nil
    var searchText = ""
    /// Set by Quick Add ⌘↩: the calendar opens this occurrence's editor, then sets nil.
    var pendingEditorOccurrenceID: Occurrence.ID? = nil
    var visibleDays: [CalendarDate] { math.visibleDays(for: span, around: selectedDate) }

    // MARK: - Subjects

    /// Persisted per Mac, not in the library.
    private(set) var hiddenSubjectIDs: Set<UUID>

    // MARK: - Private state

    private let settings: AppSettings
    private let defaults: UserDefaults
    private let timeSource: any TimeSource
    private let safetyDirectory: URL
    @ObservationIgnored private var expander: OccurrenceExpander
    @ObservationIgnored private var clock: ClockMonitor?
    @ObservationIgnored private var hasStarted = false
    /// Bumped by every attempt to open a folder; results of older attempts are dropped.
    @ObservationIgnored private var loadGeneration = 0
    /// Bumped whenever a library opens; reports from an earlier library's save queue are dropped.
    @ObservationIgnored private var librarySession = 0
    @ObservationIgnored private var changeObservers: [WeakLibraryChangeObserver] = []
    @ObservationIgnored private var savedFolder: SavedFolder?
    /// The folder of the last open attempt, for "Start a New Calendar Here" and retries in demo mode.
    @ObservationIgnored private var attemptedRoot: URL?
    @ObservationIgnored private var attemptedSafetyDirectory: URL?
    /// The folder whose security scope was entered from a bookmark.
    @ObservationIgnored private var accessedFolder: URL?
    @ObservationIgnored private var saveQueue: LibrarySaveQueue?
    /// Numbers every snapshot handed to the save queue, retries included.
    @ObservationIgnored private var saveNumber = 0
    @ObservationIgnored private var lastFinishedSaveNumber = 0
    @ObservationIgnored private var occurrenceCache = OccurrenceCache()
    @ObservationIgnored private var cacheStamp: CacheStamp?
    @ObservationIgnored private var visibleEventsCache: [Event]?
    @ObservationIgnored private var upNextCache: (key: UpNextKey, value: [Occurrence])?
    @ObservationIgnored private var searchCache: (key: SearchKey, value: [Occurrence])?
    @ObservationIgnored private var eventPositions: [UUID: Int]?

    init(options: LaunchOptions, settings: AppSettings, defaults: UserDefaults) {
        let timeSource = options.timeSource
        let now = timeSource.now
        let math = CalendarMath(timeZone: .current, firstWeekday: settings.effectiveFirstWeekday)
        let today = math.today(now: now)
        self.isDemo = options.isDemo
        self.settings = settings
        self.defaults = defaults
        self.timeSource = timeSource
        self.safetyDirectory = URL.applicationSupportDirectory.appending(
            components: "Ithil", "SafetyCopies", directoryHint: .isDirectory)
        self.now = now
        self.math = math
        self.today = today
        self.selectedDate = today
        self.expander = OccurrenceExpander(displayTimeZone: math.timeZone)
        self.hiddenSubjectIDs = AppModel.storedHiddenSubjectIDs(in: defaults)
    }

    /// Starts the clock and opens the library: the demo folder, the saved folder, or `.needsFolder`.
    /// Call once at launch; later calls do nothing.
    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let clock = ClockMonitor(model: self)
        clock.start()
        self.clock = clock
        observeFirstWeekday()
        if isDemo {
            openDemoLibrary()
        } else if let saved = SavedFolder.load(from: defaults) {
            savedFolder = saved
            openSavedFolder(saved)
        } else {
            state = .needsFolder
        }
    }

    /// Whether the library can be changed right now.
    var canEdit: Bool { state == .ready && !isReadOnly }

    // MARK: - Navigation

    func goToToday() {
        selectedDate = today
    }

    /// Moves ‹ / › by the current span.
    func step(_ count: Int) {
        selectedDate = math.step(selectedDate, by: span, count: count)
    }

    func show(_ date: CalendarDate, span: CalendarSpan?) {
        selectedDate = date
        if let span, span != self.span {
            self.span = span
        }
    }

    // MARK: - Subjects

    /// Events without a subject are always visible.
    func isVisible(_ subjectID: UUID?) -> Bool {
        guard let subjectID else { return true }
        return !hiddenSubjectIDs.contains(subjectID)
    }

    func setVisible(_ visible: Bool, subjectID: UUID) {
        guard visible == hiddenSubjectIDs.contains(subjectID) else { return }
        if visible {
            hiddenSubjectIDs.remove(subjectID)
        } else {
            hiddenSubjectIDs.insert(subjectID)
        }
        storeHiddenSubjectIDs()
    }

    func subject(for event: Event) -> Subject? {
        library.subject(withID: event.subjectID)
    }

    /// Adds a subject, or replaces the one with the same ID.
    func addSubject(_ subject: Subject) {
        guard canEdit else { return }
        var updated = library
        if let index = updated.subjects.firstIndex(where: { $0.id == subject.id }) {
            updated.subjects[index] = subject
        } else {
            updated.subjects.append(subject)
        }
        let old = library
        commit(updated)
        notifyObservers(.subjectsChanged, from: old)
    }

    func updateSubject(_ subject: Subject) {
        guard canEdit, let index = library.subjects.firstIndex(where: { $0.id == subject.id }) else { return }
        guard library.subjects[index] != subject else { return }
        var updated = library
        updated.subjects[index] = subject
        let old = library
        commit(updated)
        notifyObservers(.subjectsChanged, from: old)
    }

    /// Removes the subject. Its events keep existing with no subject.
    func deleteSubject(id: UUID) {
        guard canEdit, library.subjects.contains(where: { $0.id == id }) else { return }
        var updated = library
        updated.subjects.removeAll { $0.id == id }
        let stamp = timeSource.now.roundedToSecond
        for index in updated.events.indices where updated.events[index].subjectID == id {
            updated.events[index].subjectID = nil
            updated.events[index].modifiedAt = stamp
        }
        let old = library
        commit(updated)
        notifyObservers(.subjectsChanged, from: old)
        if hiddenSubjectIDs.contains(id) {
            hiddenSubjectIDs.remove(id)
            storeHiddenSubjectIDs()
        }
    }

    // MARK: - Queries

    /// The occurrences that overlap `days` (from the earliest to the latest), visible subjects only,
    /// sorted.
    func occurrences(in days: [CalendarDate]) -> [Occurrence] {
        guard let first = days.min(), let last = days.max() else { return [] }
        return occurrences(from: first, through: last)
    }

    /// The occurrences that overlap `day`, visible subjects only, sorted. Filtered from the cached month
    /// grid around the day, so asking for every day of a month expands the events only once.
    func occurrences(on day: CalendarDate) -> [Occurrence] {
        let key = cacheKey(from: day, through: day)
        if let cached = occurrenceCache.value(for: key) { return cached }
        let candidates = occurrenceCache.value(covering: day, like: key) ?? occurrences(inMonthGridOf: day)
        let interval = math.interval(from: day, through: day)
        let result = candidates.filter { AppModel.overlaps($0, interval) }
        occurrenceCache.insert(result, for: key)
        return result
    }

    /// The next 4 occurrences that haven't started yet, visible subjects only.
    var upNext: [Occurrence] {
        let key = UpNextKey(stamp: currentCacheStamp(), now: now)
        if let cached = upNextCache, cached.key == key { return cached.value }
        let value = expander.upcoming(visibleEvents(), after: now, limit: 4, horizonDays: 60)
        upNextCache = (key, value)
        return value
    }

    /// `EventSearch` over `searchText`, visible subjects only. Empty for a blank query.
    var searchResults: [Occurrence] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        let key = SearchKey(stamp: currentCacheStamp(), now: now, query: query)
        if let cached = searchCache, cached.key == key { return cached.value }
        let visible = Library(id: library.id, subjects: library.subjects, events: visibleEvents())
        let value = EventSearch.search(visible, query: query, now: now, expander: expander)
        searchCache = (key, value)
        return value
    }

    /// The occurrence with this ID, whatever its subject's visibility. Nil if it no longer exists.
    func occurrence(id: Occurrence.ID) -> Occurrence? {
        guard let event = event(withID: id.eventID) else { return nil }
        return expander.occurrence(of: event, on: id.date)
    }

    private func occurrences(from first: CalendarDate, through last: CalendarDate) -> [Occurrence] {
        let key = cacheKey(from: first, through: last)
        if let cached = occurrenceCache.value(for: key) { return cached }
        let interval = math.interval(from: first, through: last)
        let result = expander.occurrences(of: visibleEvents(), in: interval)
        occurrenceCache.insert(result, for: key)
        return result
    }

    /// Every week of a month grid lies inside it, so the week and day views reuse it too.
    private func occurrences(inMonthGridOf day: CalendarDate) -> [Occurrence] {
        let grid = math.monthGrid(year: day.year, month: day.month)
        guard let first = grid.first, let last = grid.last, first <= day, day <= last else {
            return occurrences(from: day, through: day)
        }
        return occurrences(from: first, through: last)
    }

    /// The same overlap rule as `OccurrenceExpander`: an occurrence overlaps when it starts before the
    /// end and ends after the start; a zero-length one when it starts inside.
    private static func overlaps(_ occurrence: Occurrence, _ interval: DateInterval) -> Bool {
        if occurrence.end > occurrence.start {
            return occurrence.start < interval.end && occurrence.end > interval.start
        }
        return occurrence.start >= interval.start && occurrence.start < interval.end
    }

    private func cacheKey(from first: CalendarDate, through last: CalendarDate) -> OccurrenceCache.Key {
        let stamp = currentCacheStamp()
        return OccurrenceCache.Key(
            revision: stamp.revision, hiddenSubjectIDs: stamp.hiddenSubjectIDs, timeZone: stamp.timeZone,
            first: first, last: last)
    }

    /// What every cached query depends on. Reading it also registers those properties with Observation,
    /// so views that query the model update when any of them changes. A new stamp empties the caches.
    private func currentCacheStamp() -> CacheStamp {
        let stamp = CacheStamp(revision: libraryRevision, hiddenSubjectIDs: hiddenSubjectIDs, timeZone: math.timeZone)
        if stamp != cacheStamp {
            cacheStamp = stamp
            occurrenceCache.removeAll()
            visibleEventsCache = nil
            eventPositions = nil
        }
        return stamp
    }

    private func visibleEvents() -> [Event] {
        _ = currentCacheStamp()
        if let cached = visibleEventsCache { return cached }
        let hidden = hiddenSubjectIDs
        let events: [Event]
        if hidden.isEmpty {
            events = library.events
        } else {
            events = library.events.filter { event in
                guard let subjectID = event.subjectID else { return true }
                return !hidden.contains(subjectID)
            }
        }
        visibleEventsCache = events
        return events
    }

    private func event(withID id: UUID) -> Event? {
        _ = currentCacheStamp()
        let positions: [UUID: Int]
        if let cached = eventPositions {
            positions = cached
        } else {
            var built: [UUID: Int] = [:]
            built.reserveCapacity(library.events.count)
            for (position, event) in library.events.enumerated() {
                built[event.id] = position
            }
            eventPositions = built
            positions = built
        }
        guard let position = positions[id], library.events.indices.contains(position) else { return nil }
        return library.events[position]
    }

    // MARK: - Events

    /// A new one-hour timed event in the current time zone with the default alert, not yet added. It
    /// starts at `startMinute`, or else at the next whole hour today and at 9:00 on other days.
    func newEvent(on day: CalendarDate, startMinute: Int?) -> Event {
        let minute = startMinute.map { min(max($0, 0), 24 * 60 - 1) } ?? defaultStartMinute(on: day)
        let calendar = math.calendar
        let parts = DateComponents(
            year: day.year, month: day.month, day: day.day, hour: minute / 60, minute: minute % 60)
        let start = calendar.date(from: parts) ?? day.start(in: timeZone)
        let end = calendar.date(byAdding: .hour, value: 1, to: start) ?? start.addingTimeInterval(60 * 60)
        return Event(
            title: "", timing: .timed(start: start, end: end, timeZone: timeZone), alert: settings.defaultAlert,
            createdAt: timeSource.now)
    }

    private func defaultStartMinute(on day: CalendarDate) -> Int {
        guard day == today else { return 9 * 60 }
        let nextHour = math.minutesOfDay(now) / 60 + 1
        return min(nextHour, 23) * 60
    }

    func add(_ event: Event) {
        guard canEdit, !library.events.contains(where: { $0.id == event.id }) else { return }
        var updated = library
        updated.events.append(event)
        let old = library
        commit(updated)
        notifyObservers(.added(event), from: old)
    }

    func update(_ occurrence: Occurrence, with edited: Event, scope: SeriesEditing.Scope) {
        guard canEdit else { return }
        var updated = library
        SeriesEditing.update(occurrence, with: edited, scope: scope, in: &updated, now: timeSource.now)
        guard updated != library else { return }
        let old = library
        commit(updated)
        notifyObservers(.updated(occurrence, edited: edited, scope: scope), from: old)
        if selectedOccurrenceID == occurrence.id, self.occurrence(id: occurrence.id) == nil {
            // A rescheduled single event keeps its ID and moves to its new day.
            let moved = Occurrence.ID(eventID: occurrence.event.id, date: edited.timing.startDate)
            selectedOccurrenceID = self.occurrence(id: moved) != nil ? moved : nil
        }
    }

    func delete(_ occurrence: Occurrence, scope: SeriesEditing.Scope) {
        guard canEdit else { return }
        var updated = library
        SeriesEditing.delete(occurrence, scope: scope, from: &updated)
        guard updated != library else { return }
        let old = library
        commit(updated)
        notifyObservers(.deleted(occurrence, scope: scope), from: old)
        if let selected = selectedOccurrenceID, self.occurrence(id: selected) == nil {
            selectedOccurrenceID = nil
        }
    }

    /// Subjects are matched against the library as it is now; make a new parser after subjects change.
    func makeQuickAddParser() -> QuickAddParser {
        QuickAddParser(
            subjects: library.subjects, timeZone: timeZone, defaultDuration: 60 * 60,
            defaultAlert: settings.defaultAlert)
    }

    // MARK: - Saving

    /// Whether a change hasn't finished saving (successfully or not) yet.
    var hasPendingSaves: Bool { lastFinishedSaveNumber < saveNumber }

    /// Waits until every change handed to the save queue has been written, or `timeout` passes.
    func finishPendingSaves(timeout: Duration) async {
        let deadline = ContinuousClock.now + timeout
        while hasPendingSaves, ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: .milliseconds(20))
            } catch {
                return
            }
        }
    }

    /// Saves the current library again, after a failed save.
    func retrySave() {
        saveError = nil
        guard canEdit else { return }
        scheduleSave()
    }

    var showsRecoveryNotice: Bool {
        get { recoveryNotice != nil }
        set {
            if !newValue {
                recoveryNotice = nil
            }
        }
    }

    var showsSaveError: Bool {
        get { saveError != nil }
        set {
            if !newValue {
                saveError = nil
            }
        }
    }

    var showsFolderError: Bool {
        get { folderError != nil }
        set {
            if !newValue {
                folderError = nil
            }
        }
    }

    // MARK: - Change observers

    /// Registers an observer (held weakly) that hears about every library change from now on.
    func addChangeObserver(_ observer: any LibraryChangeObserver) {
        changeObservers.removeAll { $0.observer == nil || $0.observer === observer }
        changeObservers.append(WeakLibraryChangeObserver(observer: observer))
    }

    private func notifyObservers(_ change: LibraryChange, from old: Library) {
        changeObservers.removeAll { $0.observer == nil }
        let current = library
        for entry in changeObservers {
            entry.observer?.libraryDidChange(change, from: old, to: current)
        }
    }

    private func commit(_ updated: Library) {
        library = updated
        libraryRevision += 1
        scheduleSave()
    }

    private func scheduleSave() {
        guard let saveQueue else { return }
        let snapshot = library
        saveNumber += 1
        let number = saveNumber
        Task {
            await saveQueue.enqueue(snapshot, number: number)
        }
    }

    private func saveFinished(number: Int, error: (any Error)?, session: Int) {
        guard session == librarySession else { return }
        lastFinishedSaveNumber = max(lastFinishedSaveNumber, number)
        guard let error else { return }
        if (error as? LibraryStoreError) == .readOnly {
            isReadOnly = true
            saveQueue = nil
        }
        saveError = LibraryMessages.saveFailed(error)
    }

    // MARK: - Folders

    /// Uses the folder the user chose: `RootFolderPolicy` picks the folder itself (empty or already an
    /// Ithil folder) or an `Ithil` subfolder; it is bookmarked, then loaded or, if new, given an empty
    /// library. A folder that doesn't exist yet (from "Create Ithil Folder…") is created first.
    func useFolder(_ chosen: URL) {
        openChosenFolder(chosen, relocating: false)
    }

    /// "Locate Folder…": the same library in a new place. Only an Ithil folder (or one that contains an
    /// `Ithil` folder) is accepted, so a lost calendar is never quietly replaced by an empty one.
    func relocateFolder(_ chosen: URL) {
        openChosenFolder(chosen, relocating: true)
    }

    /// From `.noLibrary`: creates an empty library in that folder.
    func startFresh() {
        guard case .noLibrary = state, let root = attemptedRoot else { return }
        let safety = attemptedSafetyDirectory ?? safetyDirectory
        let generation = beginOpening()
        Task {
            await openLibrary(
                at: root, safetyDirectory: safety, knownLibraryID: nil, createsLibrary: true, generation: generation)
        }
    }

    /// Tries the last folder again, e.g. after reconnecting a drive.
    func retryLoad() {
        switch state {
        case .ready, .loading:
            return
        case .needsFolder, .folderMissing, .noLibrary, .unreadable:
            break
        }
        if isDemo {
            openDemoLibrary()
        } else if let saved = savedFolder ?? SavedFolder.load(from: defaults) {
            savedFolder = saved
            openSavedFolder(saved)
        } else {
            state = .needsFolder
        }
    }

    private func beginOpening() -> Int {
        loadGeneration += 1
        state = .loading
        return loadGeneration
    }

    private func openSavedFolder(_ saved: SavedFolder) {
        let generation = beginOpening()
        let bookmark = saved.bookmark
        Task {
            let resolution = await Task.detached(priority: .userInitiated) {
                FolderAccess.resolve(bookmark)
            }.value
            guard generation == loadGeneration else {
                // A newer attempt took over: leave the scope this one entered, so starts and stops balance.
                if case .available(let url, _, let isAccessing) = resolution, isAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
                return
            }
            switch resolution {
            case .unresolvable, .missing:
                state = .folderMissing(path: saved.path)
            case .available(let url, let refreshedBookmark, let isAccessing):
                var updated = saved
                updated.bookmark = refreshedBookmark ?? saved.bookmark
                updated.path = url.path
                if updated != saved {
                    rememberFolder(updated)
                }
                if isAccessing {
                    enterAccessedFolder(url)
                }
                await openLibrary(
                    at: url, safetyDirectory: safetyDirectory, knownLibraryID: saved.libraryID, createsLibrary: false,
                    generation: generation)
            }
        }
    }

    private func openChosenFolder(_ chosen: URL, relocating: Bool) {
        guard !isDemo else {
            folderError = LibraryMessages.demoCannotChangeFolder
            return
        }
        let previousState = state
        let generation = beginOpening()
        Task {
            let prepared: FolderAccess.PreparedFolder
            do {
                prepared = try await Task.detached(priority: .userInitiated) {
                    try FolderAccess.prepare(chosen, relocating: relocating)
                }.value
            } catch {
                guard generation == loadGeneration else { return }
                let reason = String(describing: error)
                logger.error("Could not use the chosen folder: \(reason, privacy: .private)")
                state = previousState == .loading ? .needsFolder : previousState
                folderError = LibraryMessages.cannotUseFolder(error)
                return
            }
            guard generation == loadGeneration else { return }
            let libraryID = relocating ? savedFolder?.libraryID : nil
            rememberFolder(SavedFolder(bookmark: prepared.bookmark, path: prepared.root.path, libraryID: libraryID))
            leaveAccessedFolder()
            await openLibrary(
                at: prepared.root, safetyDirectory: safetyDirectory, knownLibraryID: libraryID,
                createsLibrary: !prepared.hasLibrary, generation: generation)
        }
    }

    private func openDemoLibrary() {
        let generation = beginOpening()
        let demo = DemoLibrary.make(weekContaining: timeSource.now, timeZone: timeZone)
        Task {
            let folders: FolderAccess.DemoFolders
            do {
                folders = try await Task.detached(priority: .userInitiated) {
                    try FolderAccess.makeDemoFolders()
                }.value
            } catch {
                guard generation == loadGeneration else { return }
                state = .unreadable(path: "", message: LibraryMessages.couldNotSetUpDemo(error))
                return
            }
            guard generation == loadGeneration else { return }
            let store = makeStore(root: folders.root, safetyDirectory: folders.safetyCopies, knownLibraryID: nil)
            attemptedRoot = folders.root
            attemptedSafetyDirectory = folders.safetyCopies
            do {
                try await store.create(demo)
            } catch {
                guard generation == loadGeneration else { return }
                state = .unreadable(path: folders.root.path, message: LibraryMessages.couldNotSetUpDemo(error))
                return
            }
            guard generation == loadGeneration else { return }
            didOpen(LibraryLoad(library: demo, recovery: nil), store: store, root: folders.root, readOnly: false)
        }
    }

    /// Loads the library in `root`, or creates an empty one there, and moves to the matching state.
    private func openLibrary(
        at root: URL,
        safetyDirectory: URL,
        knownLibraryID: UUID?,
        createsLibrary: Bool,
        generation: Int
    ) async {
        attemptedRoot = root
        attemptedSafetyDirectory = safetyDirectory
        await Task.detached(priority: .userInitiated) {
            FolderAccess.prepareSafetyDirectory(safetyDirectory)
        }.value
        guard generation == loadGeneration else { return }
        let store = makeStore(root: root, safetyDirectory: safetyDirectory, knownLibraryID: knownLibraryID)
        if createsLibrary {
            let fresh = Library()
            do {
                try await store.create(fresh)
            } catch {
                guard generation == loadGeneration else { return }
                let reason = String(describing: error)
                logger.error("Could not create a library: \(reason, privacy: .private)")
                state = .unreadable(path: root.path, message: LibraryMessages.couldNotCreate(error))
                return
            }
            guard generation == loadGeneration else { return }
            didOpen(LibraryLoad(library: fresh, recovery: nil), store: store, root: root, readOnly: false)
            return
        }
        do {
            let load = try await store.load()
            guard generation == loadGeneration else { return }
            didOpen(load, store: store, root: root, readOnly: false)
        } catch let error as LibraryStoreError {
            guard generation == loadGeneration else { return }
            await loadFailed(error, store: store, root: root, generation: generation)
        } catch {
            guard generation == loadGeneration else { return }
            let reason = String(describing: error)
            logger.error("Could not load the library: \(reason, privacy: .private)")
            state = .unreadable(path: root.path, message: LibraryMessages.couldNotOpen(error))
        }
    }

    private func loadFailed(_ error: LibraryStoreError, store: LibraryStore, root: URL, generation: Int) async {
        switch error {
        case .noLibrary:
            let exists = await Task.detached(priority: .userInitiated) {
                FolderAccess.folderExists(at: root)
            }.value
            guard generation == loadGeneration else { return }
            state = exists ? .noLibrary(path: root.path) : .folderMissing(path: root.path)
        case .newerSchema(let found, let supported):
            logger.notice("Library schema \(found, privacy: .public) is newer than \(supported, privacy: .public)")
            let newer = await Task.detached(priority: .userInitiated) {
                FolderAccess.readLibraryFromNewerVersion(at: root)
            }.value
            guard generation == loadGeneration else { return }
            if let newer {
                didOpen(LibraryLoad(library: newer, recovery: nil), store: store, root: root, readOnly: true)
            } else {
                state = .unreadable(path: root.path, message: LibraryMessages.newerVersion)
            }
        case .unreadable(let detail):
            logger.error("The library is damaged and couldn't be recovered: \(detail, privacy: .private)")
            state = .unreadable(path: root.path, message: LibraryMessages.damaged)
        case .readOnly:
            state = .unreadable(path: root.path, message: LibraryMessages.newerVersion)
        }
    }

    private func didOpen(_ load: LibraryLoad, store: LibraryStore, root: URL, readOnly: Bool) {
        librarySession += 1
        let session = librarySession
        let old = library
        library = load.library
        libraryRevision += 1
        lastFinishedSaveNumber = saveNumber
        isReadOnly = readOnly
        rootURL = root
        recoveryNotice = load.recovery
        saveError = nil
        selectedOccurrenceID = nil
        pendingEditorOccurrenceID = nil
        if readOnly {
            saveQueue = nil
        } else {
            saveQueue = LibrarySaveQueue(store: store) { [weak self] number, error in
                self?.saveFinished(number: number, error: error, session: session)
            }
        }
        if !isDemo, !readOnly, var saved = savedFolder, saved.libraryID != load.library.id {
            saved.libraryID = load.library.id
            rememberFolder(saved)
        }
        state = .ready
        notifyObservers(.opened(root: root), from: old)
    }

    private func makeStore(root: URL, safetyDirectory: URL, knownLibraryID: UUID?) -> LibraryStore {
        LibraryStore(
            root: root, safetyDirectory: safetyDirectory, knownLibraryID: knownLibraryID,
            fileSystem: LocalFileSystem(), timeSource: timeSource, backupInterval: 15 * 60, maxBackups: 50)
    }

    private func rememberFolder(_ folder: SavedFolder) {
        savedFolder = folder
        guard !isDemo else { return }
        folder.save(to: defaults)
    }

    /// Records a folder whose security scope `FolderAccess.resolve` just entered. Entering the same folder
    /// again (a retry) leaves the extra scope at once, so every start is balanced by a stop.
    private func enterAccessedFolder(_ url: URL) {
        if accessedFolder == url {
            url.stopAccessingSecurityScopedResource()
            return
        }
        leaveAccessedFolder()
        accessedFolder = url
    }

    /// Leaves the current folder's security scope once its pending saves are written.
    private func leaveAccessedFolder() {
        guard let previous = accessedFolder else { return }
        accessedFolder = nil
        let queue = saveQueue
        Task {
            while let queue, await queue.isBusy {
                do {
                    try await Task.sleep(for: .milliseconds(50))
                } catch {
                    break
                }
            }
            previous.stopAccessingSecurityScopedResource()
        }
    }

    // MARK: - Clock

    /// Re-reads the clock (minute ticks, day changes, clock changes). If the day changed while the
    /// views were on today, they follow to the new today.
    func refreshClock() {
        let current = timeSource.now
        guard current != now else { return }
        let previousToday = today
        now = current
        updateToday(from: previousToday)
    }

    /// Rebuilds the calendar math for the current time zone, locale and first-weekday setting, then
    /// re-reads the clock (time zone and locale changes, wake, Settings).
    func refreshCalendar() {
        NSTimeZone.resetSystemTimeZone()
        let zone = TimeZone.current
        let weekday = settings.effectiveFirstWeekday
        let previousToday = today
        if zone != math.timeZone || weekday != math.firstWeekday {
            math = CalendarMath(timeZone: zone, firstWeekday: weekday)
            expander = OccurrenceExpander(displayTimeZone: zone)
        }
        let current = timeSource.now
        if current != now {
            now = current
        }
        updateToday(from: previousToday)
    }

    private func updateToday(from previousToday: CalendarDate) {
        let newToday = math.today(now: now)
        guard newToday != today else { return }
        today = newToday
        if selectedDate == previousToday {
            selectedDate = newToday
        }
    }

    /// Rebuilds `math` whenever the first-weekday setting changes.
    private func observeFirstWeekday() {
        withObservationTracking {
            _ = settings.firstWeekday
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.refreshCalendar()
                self?.observeFirstWeekday()
            }
        }
    }

    // MARK: - Hidden subjects

    private enum Key {
        static let hiddenSubjectIDs = "hiddenSubjectIDs"
    }

    private static func storedHiddenSubjectIDs(in defaults: UserDefaults) -> Set<UUID> {
        let strings = defaults.stringArray(forKey: Key.hiddenSubjectIDs) ?? []
        return Set(strings.compactMap { UUID(uuidString: $0) })
    }

    private func storeHiddenSubjectIDs() {
        defaults.set(hiddenSubjectIDs.map(\.uuidString).sorted(), forKey: Key.hiddenSubjectIDs)
    }

    // MARK: - Previews

    /// The demo library in memory, with no folder and no clock, for SwiftUI previews.
    static var preview: AppModel {
        let settings = AppSettings.preview
        let defaults = UserDefaults(suiteName: "io.github.visaug36.Ithil.preview") ?? .standard
        let options = LaunchOptions(isDemo: true, pinnedNow: nil)
        let model = AppModel(options: options, settings: settings, defaults: defaults)
        model.library = DemoLibrary.make(weekContaining: model.now, timeZone: model.timeZone)
        model.libraryRevision += 1
        model.state = .ready
        return model
    }
}

/// What every cached query depends on besides its own arguments.
private struct CacheStamp: Hashable {
    var revision: Int
    var hiddenSubjectIDs: Set<UUID>
    var timeZone: TimeZone
}

private struct UpNextKey: Hashable {
    var stamp: CacheStamp
    var now: Date
}

private struct SearchKey: Hashable {
    var stamp: CacheStamp
    var now: Date
    var query: String
}

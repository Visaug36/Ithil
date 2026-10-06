import Foundation
import IthilCore
import Testing

struct LibraryCodecTests {
    @Test func currentSchemaIsVersionOne() {
        #expect(LibraryCodec.currentSchemaVersion == 1)
        #expect(LibraryCodec.schemaMigrator.currentVersion == 1)
    }

    @Test func roundTripKeepsEveryField() throws {
        let library = StorageFixtures.sampleLibrary()
        let data = try LibraryCodec.encode(library, savedAt: StorageFixtures.start)
        let decoded = try LibraryCodec.decode(data)
        #expect(decoded.library == library)
        #expect(decoded.savedAt == StorageFixtures.start)
        #expect(decoded.schemaVersion == 1)
    }

    @Test func emptyLibraryRoundTrips() throws {
        let library = Library()
        let decoded = try LibraryCodec.decode(LibraryCodec.encode(library, savedAt: StorageFixtures.start))
        #expect(decoded.library == library)
    }

    @Test func fiveThousandEventsRoundTrip() throws {
        let zone = StorageFixtures.timeZone("America/New_York")
        var events: [Event] = []
        for index in 0..<5000 {
            let start = StorageFixtures.start.addingTimeInterval(Double(index) * 60 * 60)
            let timing = EventTiming.timed(start: start, end: start.addingTimeInterval(45 * 60), timeZone: zone)
            events.append(Event(title: "Event \(index)", timing: timing, createdAt: StorageFixtures.start))
        }
        let library = Library(events: events)
        let decoded = try LibraryCodec.decode(LibraryCodec.encode(library, savedAt: StorageFixtures.start))
        #expect(decoded.library == library)
    }

    @Test func savedAtIsRoundedToWholeSeconds() throws {
        let library = Library()
        let data = try LibraryCodec.encode(library, savedAt: StorageFixtures.start.addingTimeInterval(0.6))
        let decoded = try LibraryCodec.decode(data)
        #expect(decoded.savedAt == StorageFixtures.start.addingTimeInterval(1))
    }

    @Test func fileIsPrettyJSONWithSchemaVersionOne() throws {
        let library = StorageFixtures.sampleLibrary()
        let data = try LibraryCodec.encode(library, savedAt: StorageFixtures.start)
        let parsed = try JSONSerialization.jsonObject(with: data, options: [])
        let object = try #require(parsed as? [String: Any])
        let version = object["schemaVersion"] as? Int
        let savedAt = object["savedAt"] as? String
        let id = object["id"] as? String
        let events = object["events"] as? [Any]
        let subjects = object["subjects"] as? [Any]
        #expect(version == 1)
        #expect(savedAt == "2026-10-06T11:50:00Z")
        #expect(id == library.id.uuidString)
        #expect(events?.count == 3)
        #expect(subjects?.count == 2)

        let text = String(decoding: data, as: UTF8.self)
        #expect(text.hasPrefix("{\n  \""))
        #expect(text.contains("https://example.com/physics/week-6"))
        #expect(text.contains("Room B/204"))
        #expect(!text.contains("\\/"))
    }

    @Test func topLevelKeysAreSorted() throws {
        let library = Library(subjects: [Subject(name: "Physics", color: .palette(.teal))])
        let data = try LibraryCodec.encode(library, savedAt: StorageFixtures.start)
        let text = String(decoding: data, as: UTF8.self)
        let keys = ["\"events\"", "\"id\"", "\"savedAt\"", "\"schemaVersion\"", "\"subjects\""]
        let positions = keys.compactMap { text.range(of: $0)?.lowerBound }
        #expect(positions.count == keys.count)
        #expect(positions == positions.sorted())
    }

    @Test func timedEventsKeepTheirTimeZoneAndAllDayEventsTheirDates() throws {
        let library = StorageFixtures.sampleLibrary()
        let decoded = try LibraryCodec.decode(LibraryCodec.encode(library, savedAt: StorageFixtures.start))
        let lecture = try #require(decoded.library.events.first)
        #expect(lecture.timing.timeZone?.identifier == "Europe/Amsterdam")
        let trip = try #require(decoded.library.events.dropFirst().first)
        let tripDays = EventTiming.allDay(
            start: CalendarDate(year: 2026, month: 10, day: 9), end: CalendarDate(year: 2026, month: 10, day: 11))
        #expect(trip.timing == tripDays)
    }

    @Test func newerSchemaIsRefused() {
        let data = Data(#"{"schemaVersion": 2, "id": "8C0F3E0A-7B6B-4F43-9C5E-2D2B9D1C7A11"}"#.utf8)
        #expect(throws: LibraryStoreError.newerSchema(found: 2, supported: 1)) {
            _ = try LibraryCodec.decode(data)
        }
    }

    @Test func damagedFilesAreUnreadable() {
        let samples = [
            "",
            "not json",
            "[]",
            "{\"schemaVersion\": 1, \"events\": [",
            #"{"id": "8C0F3E0A-7B6B-4F43-9C5E-2D2B9D1C7A11"}"#,
            #"{"schemaVersion": "1", "id": "8C0F3E0A-7B6B-4F43-9C5E-2D2B9D1C7A11"}"#,
            #"{"schemaVersion": 0, "id": "8C0F3E0A-7B6B-4F43-9C5E-2D2B9D1C7A11"}"#,
            #"{"schemaVersion": 1}"#,
            #"{"schemaVersion": 1, "id": "8C0F3E0A-7B6B-4F43-9C5E-2D2B9D1C7A11", "events": [{"id": 5}]}"#,
        ]
        for sample in samples {
            var caught: (any Error)?
            do {
                _ = try LibraryCodec.decode(Data(sample.utf8))
            } catch {
                caught = error
            }
            #expect(storageErrorIsUnreadable(caught), "\(sample)")
        }
    }

    @Test func missingOptionalFieldsUseDefaults() throws {
        let timing = #"{"kind": "allDay", "startDate": "2026-10-09", "endDate": "2026-10-09"}"#
        let essay = #"{"id": "1B8B7C4E-3F2A-4D5E-8A9B-0C1D2E3F4A5B", "title": "Essay due", "timing": \#(timing)}"#
        let json = #"{"schemaVersion": 1, "id": "8C0F3E0A-7B6B-4F43-9C5E-2D2B9D1C7A11", "events": [\#(essay)]}"#
        let decoded = try LibraryCodec.decode(Data(json.utf8))
        #expect(decoded.savedAt == nil)
        #expect(decoded.library.subjects.isEmpty)
        let event = try #require(decoded.library.events.first)
        #expect(event.title == "Essay due")
        #expect(event.notes.isEmpty)
        #expect(event.alert == nil)
    }

    @Test func injectedMigrationsRunInOrderBeforeDecoding() throws {
        let library = StorageFixtures.sampleLibrary()
        let current = try LibraryCodec.encode(library, savedAt: StorageFixtures.start)
        let parsed = try JSONSerialization.jsonObject(with: current, options: [])
        var object = try #require(parsed as? [String: Any])
        // An imaginary version 1 called the events "items"; version 2 called them "entries".
        object["items"] = object.removeValue(forKey: "events")
        object["schemaVersion"] = 1
        let old = try JSONSerialization.data(withJSONObject: object, options: [])

        let toVersion2: SchemaMigrator.Step = { json in
            json["entries"] = json.removeValue(forKey: "items")
        }
        let toVersion3: SchemaMigrator.Step = { json in
            json["events"] = json.removeValue(forKey: "entries")
        }
        let migrator = SchemaMigrator(currentVersion: 3, steps: [1: toVersion2, 2: toVersion3])
        let decoded = try LibraryCodec.decode(old, migrator: migrator)
        #expect(decoded.library == library)
        #expect(decoded.schemaVersion == 1)
        #expect(decoded.savedAt == StorageFixtures.start)
    }

    @Test func injectedMigratorRefusesNewerFiles() throws {
        let data = Data(#"{"schemaVersion": 4, "id": "8C0F3E0A-7B6B-4F43-9C5E-2D2B9D1C7A11"}"#.utf8)
        let migrator = SchemaMigrator(currentVersion: 3, steps: [:])
        #expect(throws: LibraryStoreError.newerSchema(found: 4, supported: 3)) {
            _ = try LibraryCodec.decode(data, migrator: migrator)
        }
    }

    @Test func failingMigrationIsUnreadable() {
        let data = Data(#"{"schemaVersion": 1, "id": "8C0F3E0A-7B6B-4F43-9C5E-2D2B9D1C7A11"}"#.utf8)
        let failing: SchemaMigrator.Step = { _ in
            throw CocoaError(.featureUnsupported)
        }
        let migrator = SchemaMigrator(currentVersion: 2, steps: [1: failing])
        var caught: (any Error)?
        do {
            _ = try LibraryCodec.decode(data, migrator: migrator)
        } catch {
            caught = error
        }
        #expect(storageErrorIsUnreadable(caught))
    }
}

struct SchemaMigratorTests {
    private let migrator = SchemaMigrator(
        currentVersion: 3, steps: [1: SchemaMigratorTests.log("1to2"), 2: SchemaMigratorTests.log("2to3")])

    /// A step that appends `entry` to the object's "log" array, to record which steps ran in which order.
    private static func log(_ entry: String) -> SchemaMigrator.Step {
        return { json in
            var entries = json["log"] as? [String] ?? []
            entries.append(entry)
            json["log"] = entries
        }
    }

    @Test func stepsRunInOrderFromTheObjectsVersion() throws {
        var object: [String: Any] = ["schemaVersion": 1]
        let started = try migrator.migrate(&object)
        let version = object["schemaVersion"] as? Int
        let log = object["log"] as? [String]
        #expect(started == 1)
        #expect(version == 3)
        #expect(log == ["1to2", "2to3"])
    }

    @Test func onlyTheMissingStepsRun() throws {
        var object: [String: Any] = ["schemaVersion": 2]
        let started = try migrator.migrate(&object)
        let log = object["log"] as? [String]
        #expect(started == 2)
        #expect(log == ["2to3"])
    }

    @Test func currentObjectsAreLeftAlone() throws {
        var object: [String: Any] = ["schemaVersion": 3, "keep": "me"]
        let started = try migrator.migrate(&object)
        let keep = object["keep"] as? String
        #expect(started == 3)
        #expect(!object.keys.contains("log"))
        #expect(keep == "me")
    }

    @Test func newerObjectsAreRefused() {
        var object: [String: Any] = ["schemaVersion": 4]
        var caught: (any Error)?
        do {
            try migrator.migrate(&object)
        } catch {
            caught = error
        }
        #expect(caught as? LibraryStoreError == LibraryStoreError.newerSchema(found: 4, supported: 3))
    }

    @Test func missingStepIsUnreadable() {
        let gappy = SchemaMigrator(currentVersion: 3, steps: [2: SchemaMigratorTests.log("2to3")])
        var object: [String: Any] = ["schemaVersion": 1]
        var caught: (any Error)?
        do {
            try gappy.migrate(&object)
        } catch {
            caught = error
        }
        #expect(storageErrorIsUnreadable(caught))
    }

    @Test func missingVersionIsUnreadable() {
        var object: [String: Any] = ["id": "8C0F3E0A-7B6B-4F43-9C5E-2D2B9D1C7A11"]
        var caught: (any Error)?
        do {
            try migrator.migrate(&object)
        } catch {
            caught = error
        }
        #expect(storageErrorIsUnreadable(caught))
    }
}

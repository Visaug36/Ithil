import Foundation

/// Reads and writes events.json: a versioned envelope around the `Library`.
///
/// ```json
/// { "schemaVersion": 1, "savedAt": "2026-10-06T11:50:00Z", "id": "…", "subjects": […], "events": […] }
/// ```
///
/// Files are pretty-printed with sorted keys, so they diff cleanly and stay readable in a text editor.
public enum LibraryCodec {
    /// The schema this version of Ithil writes. Bump it (and add a step to `schemaMigrator`) whenever
    /// the format changes in a way older files need converting for.
    public static let currentSchemaVersion: Int = 1

    /// The migrations `decode(_:)` applies to files written with an older schema. Step `n` turns
    /// version `n` into `n + 1`. Empty while version 1 is the only one.
    public static let schemaMigrator = SchemaMigrator(currentVersion: currentSchemaVersion, steps: [:])

    /// The library as events.json bytes, stamped with the current schema version and `savedAt`
    /// (rounded to whole seconds).
    public static func encode(_ library: Library, savedAt: Date) throws -> Data {
        let envelope = LibraryCodecWriteEnvelope(
            schemaVersion: currentSchemaVersion, savedAt: savedAt.roundedToSecond, id: library.id,
            subjects: library.subjects, events: library.events)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(envelope)
    }

    /// Decodes events.json, migrating older schemas in memory.
    ///
    /// Throws `LibraryStoreError.newerSchema` for a file written by a newer Ithil and
    /// `LibraryStoreError.unreadable` for anything else that can't be decoded.
    public static func decode(_ data: Data) throws -> DecodedLibrary {
        try decode(data, migrator: schemaMigrator)
    }

    /// Decodes events.json with a specific set of migrations; `migrator.currentVersion` is the newest
    /// schema accepted. `decode(_:)` uses `schemaMigrator`; tests inject their own.
    public static func decode(_ data: Data, migrator: SchemaMigrator) throws -> DecodedLibrary {
        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw LibraryStoreError.unreadable("Not valid JSON: \(error.localizedDescription)")
        }
        guard var object = parsed as? [String: Any] else {
            throw LibraryStoreError.unreadable("The top level is not a JSON object")
        }

        let foundVersion: Int
        do {
            foundVersion = try migrator.migrate(&object)
        } catch let error as LibraryStoreError {
            throw error
        } catch {
            throw LibraryStoreError.unreadable("Migration failed: \(String(describing: error))")
        }

        // Unchanged files are decoded from the original bytes; migrated ones are re-serialized first.
        var json = data
        if foundVersion != migrator.currentVersion {
            guard JSONSerialization.isValidJSONObject(object) else {
                throw LibraryStoreError.unreadable("A migration produced a value JSON can't hold")
            }
            do {
                json = try JSONSerialization.data(withJSONObject: object, options: [])
            } catch {
                throw LibraryStoreError.unreadable("Migration output: \(error.localizedDescription)")
            }
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            let envelope = try decoder.decode(LibraryCodecReadEnvelope.self, from: json)
            return DecodedLibrary(library: envelope.library, savedAt: envelope.savedAt, schemaVersion: foundVersion)
        } catch {
            throw LibraryStoreError.unreadable("Not a valid library: \(String(describing: error))")
        }
    }
}

/// The result of decoding events.json.
public struct DecodedLibrary: Hashable, Sendable {
    public var library: Library
    /// When the file was written, if it says.
    public var savedAt: Date?
    /// The schema version the file was written with, before any migration.
    public var schemaVersion: Int

    public init(library: Library, savedAt: Date?, schemaVersion: Int) {
        self.library = library
        self.savedAt = savedAt
        self.schemaVersion = schemaVersion
    }
}

/// Brings an events.json object written with an older schema up to `currentVersion`, one version at
/// a time, before it is decoded.
///
/// Steps work on the raw JSON object (`[String: Any]` from `JSONSerialization`); step `n` turns
/// version `n` into `n + 1`, and the migrator updates `schemaVersion` after each one. Migration happens
/// in memory only: the file is rewritten in the current schema at the next save.
public struct SchemaMigrator: Sendable {
    public typealias Step = @Sendable (inout [String: Any]) throws -> Void

    /// The newest schema version; files with a higher one are refused as `newerSchema`.
    public let currentVersion: Int
    private let steps: [Int: Step]

    public init(currentVersion: Int, steps: [Int: Step]) {
        self.currentVersion = currentVersion
        self.steps = steps
    }

    /// Runs every step from the object's `schemaVersion` up to `currentVersion`, in order.
    ///
    /// Returns the version the object started at. Throws `LibraryStoreError.unreadable` if
    /// `schemaVersion` is missing, not a whole number or below 1, or a step is missing;
    /// `LibraryStoreError.newerSchema` if it is above `currentVersion`; and rethrows a failing step's
    /// error.
    @discardableResult
    public func migrate(_ object: inout [String: Any]) throws -> Int {
        guard let foundVersion = object[Self.versionKey] as? Int else {
            throw LibraryStoreError.unreadable("schemaVersion is missing or not a whole number")
        }
        guard foundVersion >= 1 else {
            throw LibraryStoreError.unreadable("Unsupported schemaVersion \(foundVersion)")
        }
        guard foundVersion <= currentVersion else {
            throw LibraryStoreError.newerSchema(found: foundVersion, supported: currentVersion)
        }
        var version = foundVersion
        while version < currentVersion {
            guard let step = steps[version] else {
                throw LibraryStoreError.unreadable("No migration from schemaVersion \(version)")
            }
            try step(&object)
            version += 1
            object[Self.versionKey] = version
        }
        return foundVersion
    }

    static let versionKey = "schemaVersion"
}

/// What `LibraryCodec.encode` writes. The keys are sorted on output.
private struct LibraryCodecWriteEnvelope: Encodable {
    var schemaVersion: Int
    var savedAt: Date
    var id: UUID
    var subjects: [Subject]
    var events: [Event]
}

/// What `LibraryCodec.decode` reads: the library itself plus the save time. `schemaVersion` has been
/// handled by then.
private struct LibraryCodecReadEnvelope: Decodable {
    var savedAt: Date?
    var library: Library

    private enum CodingKeys: String, CodingKey {
        case savedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // A damaged timestamp shouldn't cost the user their events: treat it as unknown.
        savedAt = try? container.decodeIfPresent(Date.self, forKey: .savedAt)
        library = try Library(from: decoder)
    }
}

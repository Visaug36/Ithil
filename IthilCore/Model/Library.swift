import Foundation

/// Everything stored in one Ithil folder's `.ithil/events.json`: its subjects and events.
public struct Library: Hashable, Codable, Sendable {
    /// Identifies this Ithil folder, e.g. to name its safety copy in Application Support.
    public var id: UUID
    public var subjects: [Subject]
    public var events: [Event]

    public init(id: UUID = UUID(), subjects: [Subject] = [], events: [Event] = []) {
        self.id = id
        self.subjects = subjects
        self.events = events
    }

    private enum CodingKeys: String, CodingKey {
        case id, subjects, events
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try container.decode(UUID.self, forKey: .id),
            subjects: try container.decodeIfPresent([Subject].self, forKey: .subjects) ?? [],
            events: try container.decodeIfPresent([Event].self, forKey: .events) ?? [])
    }

    public func subject(withID id: UUID?) -> Subject? {
        guard let id else { return nil }
        return subjects.first { $0.id == id }
    }

    public func event(withID id: UUID) -> Event? {
        events.first { $0.id == id }
    }
}

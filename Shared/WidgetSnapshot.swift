import Foundation

struct WidgetSnapshot: Codable, Equatable {
    static let group = "group.com.hgsldswk.initiativetracker"
    static let key = "resumeEncounter"
    var id: UUID
    var round: Int
    var current: String?
    var next: String?

    var url: URL { URL(string: "initiativeboard://resume/\(id.uuidString)")! }

    static func load() -> Self? {
        guard let data = UserDefaults(suiteName: group)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(Self.self, from: data)
    }

    static func save(_ snapshot: Self?) {
        let defaults = UserDefaults(suiteName: group)
        defaults?.set(snapshot.flatMap { try? JSONEncoder().encode($0) }, forKey: key)
    }
}

import Foundation

struct TextTemplate: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var body: String
    var createdAt: Date
    var lastUsedAt: Date?

    init(
        id: UUID = UUID(),
        name: String,
        body: String,
        createdAt: Date = Date(),
        lastUsedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.body = body
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }
}

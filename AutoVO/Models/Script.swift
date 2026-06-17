import Foundation

struct Script: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    var title: String
    var body: String
    var createdAt: Date = Date()
    var hasCustomTitle: Bool = false

    init(id: UUID = UUID(), title: String = "", body: String = "", createdAt: Date = Date()) {
        self.id = id
        self.title = title.isEmpty ? Self.derivedTitle(from: body) : title
        self.body = body
        self.createdAt = createdAt
    }

    static func derivedTitle(from body: String) -> String {
        let firstLine = body.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "Untitled Script" }
        return trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
    }

    mutating func updateTitle() {
        guard !hasCustomTitle else { return }
        title = Self.derivedTitle(from: body)
    }
}

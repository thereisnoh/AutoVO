import Foundation

struct Script: Identifiable, Codable, Equatable, Hashable {
    var id: UUID = UUID()
    /// The user's own title. Empty means "automatic": the cue is named after the
    /// first words of its body (see `displayTitle`).
    var title: String
    var body: String
    var createdAt: Date = Date()

    init(id: UUID = UUID(), title: String = "", body: String = "", createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.body = body
        self.createdAt = createdAt
    }

    // MARK: - Title

    /// True when no custom title is set, so the name follows the body.
    var isTitleAutomatic: Bool {
        title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// What to show everywhere a cue is named: the custom title, or a name derived
    /// from the first words of the body.
    var displayTitle: String {
        isTitleAutomatic ? Self.autoTitle(from: body) : title
    }

    private static let autoTitleMaxWords = 6
    private static let autoTitleMaxChars = 40

    /// The first few words of the first non-blank line, with an ellipsis if cut.
    static func autoTitle(from body: String) -> String {
        let firstLine = body
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        let words = firstLine.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let first = words.first else { return "New Cue" }

        var taken = [first]
        var length = first.count
        for word in words.dropFirst() {
            guard taken.count < autoTitleMaxWords,
                  length + 1 + word.count <= autoTitleMaxChars else { break }
            taken.append(word)
            length += 1 + word.count
        }
        let name = taken.joined(separator: " ")
        return taken.count < words.count ? name + "…" : name
    }

    // MARK: - Codable (with legacy migration)

    private enum CodingKeys: String, CodingKey {
        case id, title, body, createdAt
        /// Legacy flag from before "empty title = automatic". Read for migration, never written.
        case hasCustomTitle
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        body = try c.decode(String.self, forKey: .body)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        var decodedTitle = try c.decode(String.self, forKey: .title)
        // Older files stored a materialised derived title ("New Cue" or the first line)
        // alongside hasCustomTitle == false. Clear it so those cues stay automatic.
        if let hasCustomTitle = try c.decodeIfPresent(Bool.self, forKey: .hasCustomTitle),
           hasCustomTitle == false {
            decodedTitle = ""
        }
        title = decodedTitle
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(body, forKey: .body)
        try c.encode(createdAt, forKey: .createdAt)
    }
}

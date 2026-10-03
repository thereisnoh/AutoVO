import Foundation

enum ProjectFileError: LocalizedError {
    case unsupportedVersion(found: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let found, let supported):
            return "This project was saved by a newer version of AutoVO (file format \(found); this version reads up to \(supported)). Update AutoVO to open it."
        }
    }
}

final class ProjectManager {
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func save(_ project: Project, to url: URL) throws {
        let file = ProjectFile(project: project)
        let data = try encoder.encode(file)
        try data.write(to: url, options: .atomicWrite)
    }

    func load(from url: URL) throws -> Project {
        let data = try Data(contentsOf: url)
        // Peek at the version before decoding the payload so a newer format produces a
        // clear message instead of an opaque decoding error.
        struct Envelope: Decodable { let version: Int }
        let envelope = try decoder.decode(Envelope.self, from: data)
        guard envelope.version <= ProjectFile.currentVersion else {
            throw ProjectFileError.unsupportedVersion(found: envelope.version,
                                                      supported: ProjectFile.currentVersion)
        }
        let file = try decoder.decode(ProjectFile.self, from: data)
        return file.project
    }
}

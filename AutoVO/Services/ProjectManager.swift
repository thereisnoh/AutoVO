import Foundation

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
        let file = try decoder.decode(ProjectFile.self, from: data)
        return file.project
    }
}

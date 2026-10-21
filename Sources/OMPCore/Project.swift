import Foundation

/// A project the user has opened in the app.
public struct Project: Codable, Identifiable, Sendable, Equatable {
    public var id: String
    /// The absolute path of the project directory.
    public var path: String
    /// The display name; the directory's name by default.
    public var name: String
    public var createdAt: Date

    public init(id: String = "p\(UUID().uuidString.prefix(8))", path: String, name: String? = nil, createdAt: Date = Date()) {
        self.id = id
        self.path = path
        self.name = name ?? (path as NSString).lastPathComponent
        self.createdAt = createdAt
    }

    /// The path with the home directory written as `~`.
    public var displayPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}

/// The list of projects, kept in the app's support directory.
public struct ProjectStore: Sendable {
    private struct File: Codable {
        var projects: [Project]
        var activeID: String?
    }

    public let url: URL

    public init(url: URL? = nil) {
        if let url {
            self.url = url
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.url = base.appendingPathComponent("omp-ui", isDirectory: true).appendingPathComponent("projects.json")
        }
    }

    public func load() -> (projects: [Project], activeID: String?) {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url),
              let file = try? decoder.decode(File.self, from: data) else { return ([], nil) }
        return (file.projects, file.activeID)
    }

    public func save(projects: [Project], activeID: String?) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(File(projects: projects, activeID: activeID))
        try data.write(to: url, options: .atomic)
    }
}

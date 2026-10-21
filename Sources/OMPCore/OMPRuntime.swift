import Foundation

/// Finding the `omp` executable.
public enum OMPBinary {
    /// Points at an explicit omp executable, bypassing the search.
    public static let overrideVariable = "OMP_UI_OMP_BIN"

    /// Locations searched when omp is not on PATH.
    static let fallbacks = [
        "~/.bun/bin/omp",
        "~/.local/bin/omp",
        "/opt/homebrew/bin/omp",
        "/usr/local/bin/omp",
        "/usr/bin/omp",
    ]

    /// The absolute path of the omp executable.
    public static func resolve() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let raw = environment[overrideVariable], !raw.isEmpty {
            return FileManager.default.fileExists(atPath: raw) ? raw : nil
        }
        for directory in (environment["PATH"] ?? "").split(separator: ":") {
            let candidate = "\(directory)/omp"
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        for candidate in fallbacks {
            let path = (candidate as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

/// One of the session files omp keeps for a project.
public struct SessionFile: Identifiable, Sendable, Equatable {
    public var id: String { path }
    public var path: String
    public var title: String
    public var modified: Date

    public init(path: String, title: String, modified: Date) {
        self.path = path
        self.title = title
        self.modified = modified
    }
}

/// The sessions recorded for a project directory, newest first.
public enum SessionFiles {
    /// The directory omp keeps its sessions in.
    public static func root() -> URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omp/agent/sessions", isDirectory: true)
    }

    /// The sessions whose working directory is `path`.
    ///
    /// The store keeps one bucket per working directory, named after it.
    public static func sessions(for path: String) -> [SessionFile] {
        guard let root = root() else { return [] }
        let bucket = root.appendingPathComponent(encoding(for: path), isDirectory: true)
        let manager = FileManager.default
        guard let files = try? manager.contentsOfDirectory(at: bucket, includingPropertiesForKeys: [.contentModificationDateKey]) else { return [] }

        var found: [SessionFile] = []
        for file in files where file.pathExtension == "jsonl" {
            let values = try? file.resourceValues(forKeys: [.contentModificationDateKey])
            found.append(SessionFile(path: file.path, title: title(from: file), modified: values?.contentModificationDate ?? .distantPast))
        }
        return found.sorted { $0.modified > $1.modified }
    }

    /// The title omp gave a session, read from its first lines.
    static func title(from file: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return file.lastPathComponent }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 16 * 1024)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        for line in text.split(separator: "\n").prefix(40) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if let name = object["sessionName"] as? String, !name.isEmpty { return name }
            if let title = object["title"] as? String, !title.isEmpty { return title }
        }
        return file.deletingPathExtension().lastPathComponent
    }

    /// The directory name omp gives a working directory.
    ///
    /// The layout is documented as: `-<relative>` for directories under home,
    /// `-tmp-<relative>` for directories under the temp root, and
    /// `--<encoded-absolute>--` for anything else, with the path separators
    /// turned into dashes.
    static func encoding(for path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "-" }
        if path.hasPrefix(home + "/") {
            return "-" + path.dropFirst(home.count + 1).replacingOccurrences(of: "/", with: "-")
        }
        for root in ["/tmp", NSTemporaryDirectory()] {
            let root = root.hasSuffix("/") ? String(root.dropLast()) : root
            if path.hasPrefix(root + "/") {
                return "-tmp-" + path.dropFirst(root.count + 1).replacingOccurrences(of: "/", with: "-")
            }
        }
        return "--" + path.dropFirst().replacingOccurrences(of: "/", with: "-") + "--"
    }
}

import Foundation

// What the composer's menu brings into a message: files and folders named so
// omp reads them, images it is shown, the rules it works under, the state of
// git, and the commands it knows.

// MARK: - Images

/// An image sent with a message, the way omp's `prompt` carries one.
public struct ImageAttachment: Sendable, Equatable, Identifiable {
    public var id: String { name + String(data.count) }
    public var name: String
    public var mimeType: String
    /// The image, base64-encoded.
    public var data: String

    public init(name: String, mimeType: String, data: String) {
        self.name = name
        self.mimeType = mimeType
        self.data = data
    }

    /// The kinds of image omp passes to a model.
    public static let mimeTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp"]

    /// Whether a file is an image omp can be shown, by its extension.
    public static func isImage(_ url: URL) -> Bool {
        mimeTypes[url.pathExtension.lowercased()] != nil
    }

    /// Reads an image file; nil when it is not one omp takes, or unreadable.
    public init?(contentsOf url: URL) {
        guard let mimeType = Self.mimeTypes[url.pathExtension.lowercased()],
              let bytes = try? Data(contentsOf: url) else { return nil }
        self.init(name: url.lastPathComponent, mimeType: mimeType, data: bytes.base64EncodedString())
    }

    var json: JSONValue {
        .object(["type": .string("image"), "data": .string(data), "mimeType": .string(mimeType)])
    }
}

// MARK: - Mentions

/// Naming a file or folder in a message so that omp reads it.
///
/// omp expands `@path` in a prompt into the file's contents, or a folder's
/// listing, when the path names something that exists; a path with spaces is
/// quoted, which its pattern also accepts.
public enum Mention {
    public static func token(_ path: String) -> String {
        path.contains(where: \.isWhitespace) ? "@\"\(path)\"" : "@\(path)"
    }
}

// MARK: - The project's files

/// The files and folders of a project, relative to it.
public struct ProjectListing: Sendable, Equatable {
    public var files: [String]
    public var directories: [String]

    public init(files: [String], directories: [String]) {
        self.files = files
        self.directories = directories
    }
}

public enum ProjectFiles {
    /// Folders never worth offering: dependencies and build output.
    static let skipped: Set<String> = ["node_modules", ".build", "build", "dist", "target", "vendor", "Pods", "DerivedData", "__pycache__", ".venv", "venv"]

    /// Lists a project, at most `limit` files. In a git repository the list is
    /// git's own — tracked files and untracked ones that are not ignored — so
    /// it follows the project's ignore rules; elsewhere the folder is walked,
    /// leaving out hidden files, dependencies and build output.
    public static func list(in root: String, limit: Int = 20_000) -> ProjectListing {
        var files: [String]
        if FileManager.default.fileExists(atPath: (root as NSString).appendingPathComponent(".git")),
           let output = Shell.run(["git", "-C", root, "ls-files", "--cached", "--others", "--exclude-standard"]) {
            files = output.split(separator: "\n").map(String.init)
        } else {
            files = walk(root, limit: limit)
        }
        files = Array(Set(files)).sorted()
        if files.count > limit { files = Array(files.prefix(limit)) }
        var directories: Set<String> = []
        for file in files {
            var parent = (file as NSString).deletingLastPathComponent
            while !parent.isEmpty, directories.insert(parent).inserted {
                parent = (parent as NSString).deletingLastPathComponent
            }
        }
        return ProjectListing(files: files, directories: directories.sorted())
    }

    private static func walk(_ root: String, limit: Int) -> [String] {
        let base = URL(fileURLWithPath: root)
        guard let walker = FileManager.default.enumerator(
            at: base, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }
        var files: [String] = []
        let prefix = base.standardizedFileURL.path + "/"
        for case let url as URL in walker {
            if skipped.contains(url.lastPathComponent) {
                walker.skipDescendants()
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            let path = url.standardizedFileURL.path
            if path.hasPrefix(prefix) { files.append(String(path.dropFirst(prefix.count))) }
            if files.count >= limit { break }
        }
        return files
    }
}

// MARK: - Rules

/// A file of instructions omp works under.
public struct RuleFile: Sendable, Equatable, Identifiable {
    public var id: String { path }
    public var path: String
    /// Where it applies: this project, or everywhere.
    public var scope: String

    public init(path: String, scope: String) {
        self.path = path
        self.scope = scope
    }
}

public enum RuleFiles {
    /// The places omp reads rules and instructions from, relative to a folder.
    static let projectFiles = [
        ".omp/RULES.md", ".omp/AGENTS.md", "AGENTS.md", "CLAUDE.md", ".claude/CLAUDE.md",
        ".cursorrules", ".clinerules", ".windsurfrules", ".github/copilot-instructions.md", ".gemini/GEMINI.md",
    ]
    static let projectFolders = [
        ".omp/rules", ".agent/rules", ".agents/rules", ".cursor/rules", ".windsurf/rules", ".github/instructions", ".clinerules",
    ]
    static let userFiles = [
        ".omp/agent/RULES.md", ".omp/agent/AGENTS.md", ".claude/CLAUDE.md", ".codex/AGENTS.md", ".gemini/GEMINI.md",
    ]
    static let userFolders = [".omp/agent/rules", ".agent/rules", ".agents/rules"]

    /// The rule files that exist for a project: in it and in the folders above
    /// it up to its repository's root, then the user's own.
    public static func find(for project: String, home: String = NSHomeDirectory()) -> [RuleFile] {
        var found: [RuleFile] = []
        var seen: Set<String> = []
        func add(_ path: String, scope: String) {
            let path = (path as NSString).standardizingPath
            guard seen.insert(path).inserted else { return }
            found.append(RuleFile(path: path, scope: scope))
        }
        for folder in ancestors(of: project, home: home) {
            for name in projectFiles where isFile((folder as NSString).appendingPathComponent(name)) {
                add((folder as NSString).appendingPathComponent(name), scope: "project")
            }
            for name in projectFolders {
                for file in ruleFiles(in: (folder as NSString).appendingPathComponent(name)) { add(file, scope: "project") }
            }
        }
        for name in userFiles where isFile((home as NSString).appendingPathComponent(name)) {
            add((home as NSString).appendingPathComponent(name), scope: "everywhere")
        }
        for name in userFolders {
            for file in ruleFiles(in: (home as NSString).appendingPathComponent(name)) { add(file, scope: "everywhere") }
        }
        return found
    }

    /// The project and the folders above it, stopping at the repository's
    /// root, or at the home folder.
    static func ancestors(of project: String, home: String) -> [String] {
        var folders: [String] = []
        var folder = (project as NSString).standardizingPath
        while true {
            folders.append(folder)
            let isRoot = FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent(".git"))
            let parent = (folder as NSString).deletingLastPathComponent
            if isRoot || folder == home || parent == folder { break }
            folder = parent
        }
        return folders
    }

    private static func ruleFiles(in folder: String) -> [String] {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder) else { return [] }
        return names.sorted()
            .filter { $0.hasSuffix(".md") || $0.hasSuffix(".mdc") }
            .map { (folder as NSString).appendingPathComponent($0) }
    }

    private static func isFile(_ path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}

// MARK: - Git

/// Something in a repository a message can point at.
public struct GitReference: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case changes, staged, branch, commit }
    public var id: String { "\(kind.rawValue):\(name)" }
    public var kind: Kind
    public var name: String
    public var detail: String

    public init(kind: Kind, name: String, detail: String) {
        self.kind = kind
        self.name = name
        self.detail = detail
    }

    /// How the message names it, in words the agent can act on with git.
    public var phrase: String {
        switch kind {
        case .changes: "the uncommitted changes (`git diff HEAD`)"
        case .staged: "the staged changes (`git diff --cached`)"
        case .branch: "the `\(name)` branch"
        case .commit: "commit `\(name)` (\u{201C}\(detail)\u{201D})"
        }
    }
}

public enum GitReferences {
    /// The working changes, the branches and the recent commits of a
    /// repository; nothing when the folder is not one.
    public static func list(in path: String, commits: Int = 30) -> [GitReference] {
        guard let status = Shell.run(["git", "-C", path, "status", "--porcelain"]) else { return [] }
        var references: [GitReference] = []
        let changed = status.split(separator: "\n").count
        if changed > 0 {
            references.append(GitReference(kind: .changes, name: "Uncommitted changes", detail: "\(changed) file\(changed == 1 ? "" : "s")"))
        }
        let staged = Shell.run(["git", "-C", path, "diff", "--cached", "--name-only"])?.split(separator: "\n").count ?? 0
        if staged > 0 {
            references.append(GitReference(kind: .staged, name: "Staged changes", detail: "\(staged) file\(staged == 1 ? "" : "s")"))
        }
        let current = Git.branch(of: path)
        for branch in (Shell.run(["git", "-C", path, "branch", "--format=%(refname:short)"]) ?? "").split(separator: "\n").prefix(20) {
            let name = String(branch)
            references.append(GitReference(kind: .branch, name: name, detail: name == current ? "current branch" : "branch"))
        }
        for line in (Shell.run(["git", "-C", path, "log", "-\(commits)", "--format=%h%x09%s"]) ?? "").split(separator: "\n") {
            let parts = line.split(separator: "\t", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            references.append(GitReference(kind: .commit, name: parts[0], detail: parts[1]))
        }
        return references
    }
}

// MARK: - Codemaps

/// omp has no map of code of its own, so a codemap is asked of the agent: it
/// reads the code and draws how it fits together.
public enum Codemap {
    public static func prompt(for directory: String?) -> String {
        let subject = directory.map { "\(Mention.token($0)) (the `\($0)` folder)" } ?? "this project"
        return """
        Make me a codemap of \(subject): its entry points, the main flows through the code, \
        the key files and what each is responsible for, and how they connect. Draw the flows \
        as a mermaid diagram, then list each file with one line on its job.
        """
    }
}

// MARK: - Running a program

enum Shell {
    /// Runs a program found on the PATH and returns what it printed, or nil
    /// when it could not run or failed.
    static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}

import Foundation

/// Finding the `omp` executable.
public enum OMPBinary {
    /// Points at an explicit omp executable, bypassing the search.
    public static let overrideVariable = "OMP_UI_OMP_BIN"
    /// Where the reader pointed the app at omp themselves; an app opened from
    /// the Dock cannot be handed an environment variable.
    public static let chosenKey = "omp-ui.omp-path"

    /// Locations searched when omp is not on PATH: where omp's installer puts
    /// it with Bun and without, and where Homebrew does.
    static let fallbacks = [
        "~/.bun/bin/omp",
        "~/.local/bin/omp",
        "/opt/homebrew/bin/omp",
        "/usr/local/bin/omp",
        "/usr/bin/omp",
    ]

    /// The absolute path of the omp executable: the environment's override,
    /// then the one the reader chose, then the PATH, then the usual places.
    public static func resolve(
        chosen: String? = UserDefaults.standard.string(forKey: chosenKey),
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String? {
        if let raw = environment[overrideVariable], !raw.isEmpty {
            return FileManager.default.fileExists(atPath: raw) ? raw : nil
        }
        if let chosen, FileManager.default.isExecutableFile(atPath: chosen) { return chosen }
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

/// The environment a Terminal window has.
///
/// An app opened from the Dock gets launchd's bare environment, without what
/// the reader's shell profile exports — API keys such as `OPENROUTER_API_KEY`,
/// and PATH additions — so an omp started with it can use fewer providers
/// than the omp the reader runs in Terminal. The login shell is asked for its
/// environment instead, as editors do.
public enum ShellEnvironment {
    static let marker = "__OMP_UI_ENVIRONMENT__"

    /// The login shell's environment over the app's own, or the app's own
    /// when the shell does not answer in time.
    public static func load(
        shell: String = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh",
        base: [String: String] = ProcessInfo.processInfo.environment,
        timeout: Duration = .seconds(6)
    ) async -> [String: String] {
        guard let read = await read(shell: shell, from: base, timeout: timeout) else { return base }
        return base.merging(read) { _, fromShell in fromShell }
    }

    /// Runs the shell as Terminal does — login and interactive, so both
    /// profiles are read — and prints its environment between markers, past
    /// anything the profiles print themselves.
    /// It starts from `base`, the app's own environment, as a Terminal window
    /// starts from the login session's.
    static func read(shell: String, from base: [String: String], timeout: Duration) async -> [String: String]? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: shell)
        process.arguments = ["-l", "-i", "-c", "printf '%s' \(marker); /usr/bin/env -0; printf '%s' \(marker)"]
        process.environment = base
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let reading = Task.detached { output.fileHandleForReading.readDataToEndOfFile() }
        let deadline = ContinuousClock.now + timeout
        while process.isRunning, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(25))
        }
        if process.isRunning {
            process.terminate()
            return nil
        }
        return parse(await reading.value)
    }

    /// The variables between the markers: `NAME=value` pairs separated by
    /// NUL, so a value may hold newlines and `=`.
    static func parse(_ data: Data) -> [String: String]? {
        let text = String(decoding: data, as: UTF8.self)
        let parts = text.components(separatedBy: marker)
        guard parts.count >= 3 else { return nil }
        var environment: [String: String] = [:]
        for entry in parts[1].split(separator: "\0") {
            guard let equals = entry.firstIndex(of: "="), equals != entry.startIndex else { continue }
            environment[String(entry[..<equals])] = String(entry[entry.index(after: equals)...])
        }
        // What describes the shell itself, not the reader's settings.
        for name in ["PWD", "OLDPWD", "SHLVL", "_"] { environment[name] = nil }
        return environment.isEmpty ? nil : environment
    }
}

/// Installing omp the ways its own README gives for a Mac.
public enum OMPInstaller {
    /// The official installer: Bun when it is there, the prebuilt binary,
    /// checked against its SHA-256, when it is not.
    public static let command = "curl -fsSL https://omp.sh/install | sh"
    public static let homebrew = "brew install can1357/tap/omp"
    public static let bun = "bun install -g @oh-my-pi/pi-coding-agent"

    /// Runs a shell command, handing over each line it prints as it prints
    /// it, and returns its exit status. The places Bun and Homebrew live are
    /// put on the PATH, in case the environment given lacks them.
    public static func run(
        _ command: String = command,
        environment base: [String: String] = ProcessInfo.processInfo.environment,
        onLine: @Sendable (String) async -> Void
    ) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        var environment = base
        let home = NSHomeDirectory()
        environment["PATH"] = ["\(home)/.bun/bin", "\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin",
                               environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"].joined(separator: ":")
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            await onLine("The installer could not start: \(error.localizedDescription)")
            return -1
        }
        do {
            for try await line in output.fileHandleForReading.bytes.lines { await onLine(line) }
        } catch {
            await onLine("Reading the installer's output failed: \(error.localizedDescription)")
        }
        while process.isRunning { try? await Task.sleep(for: .milliseconds(50)) }
        return process.terminationStatus
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

    /// The title omp gave a session, read from its first lines; for one it
    /// has not titled, the first thing the reader said in it.
    static func title(from file: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return file.lastPathComponent }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: 64 * 1024)) ?? Data()
        let text = String(decoding: data, as: UTF8.self)
        var firstMessage: String?
        for line in text.split(separator: "\n").prefix(200) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if let name = object["sessionName"] as? String, !name.isEmpty { return name }
            if let title = object["title"] as? String, !title.isEmpty { return title }
            if firstMessage == nil, let message = object["message"] as? [String: Any], message["role"] as? String == "user" {
                let said = Self.text(of: message["content"]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !said.isEmpty { firstMessage = said }
            }
        }
        if let firstMessage {
            let line = firstMessage.split(whereSeparator: \.isNewline).first.map(String.init) ?? firstMessage
            return line.count > 80 ? String(line.prefix(79)) + "…" : line
        }
        return "Untitled conversation"
    }

    /// The text of a message's content: a string, or the text parts of a
    /// list.
    private static func text(of content: Any?) -> String {
        if let text = content as? String { return text }
        let parts = content as? [[String: Any]] ?? []
        return parts.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }.joined(separator: " ")
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

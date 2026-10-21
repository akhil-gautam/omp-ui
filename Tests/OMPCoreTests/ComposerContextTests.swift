import Foundation
import Testing
@testable import OMPCore

@Suite("What the composer's menu brings into a message", .serialized)
struct ComposerContextTests {
    /// A scratch folder, removed by the caller.
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-context-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ text: String, to path: String, in root: URL) throws {
        let url = root.appendingPathComponent(path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    private func git(_ arguments: String..., in root: URL) {
        _ = Shell.run(["git", "-C", root.path, "-c", "user.name=omp-ui", "-c", "user.email=omp-ui@example.com"] + arguments)
    }

    @Test("a path with spaces is quoted so omp still reads it as one mention")
    func mentionsQuoteSpaces() {
        #expect(Mention.token("src/app/main.py") == "@src/app/main.py")
        #expect(Mention.token("/Users/me/My Notes/plan.md") == "@\"/Users/me/My Notes/plan.md\"")
    }

    @Test("a repository's listing follows its ignore rules and keeps untracked files")
    func listingFollowsGit() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("print(1)", to: "src/app/main.py", in: root)
        try write("secret", to: "build/out.txt", in: root)
        try write("build/\n", to: ".gitignore", in: root)
        git("init", "-q", in: root)
        git("add", "src/app/main.py", ".gitignore", in: root)
        try write("new", to: "notes/todo.md", in: root)

        let listing = ProjectFiles.list(in: root.path)
        #expect(listing.files == [".gitignore", "notes/todo.md", "src/app/main.py"])
        #expect(listing.directories == ["notes", "src", "src/app"])
    }

    @Test("a folder outside git is walked without hidden files or dependencies")
    func listingWalksAFolder() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("x", to: "index.js", in: root)
        try write("x", to: "node_modules/left-pad/index.js", in: root)
        try write("x", to: ".env", in: root)
        #expect(ProjectFiles.list(in: root.path).files == ["index.js"])
    }

    @Test("rules are found in the project and above it up to the repository's root")
    func rulesStopAtTheRepository() throws {
        let home = try folder()
        defer { try? FileManager.default.removeItem(at: home) }
        let repo = home.appendingPathComponent("work/repo")
        try write("x", to: "work/AGENTS.md", in: home)              // above the repository: not read
        try write("x", to: "work/repo/AGENTS.md", in: home)
        try write("x", to: "work/repo/.omp/rules/style.md", in: home)
        try write("x", to: "work/repo/.cursor/rules/api.mdc", in: home)
        try write("x", to: "work/repo/app/CLAUDE.md", in: home)
        try write("x", to: ".omp/agent/RULES.md", in: home)
        try FileManager.default.createDirectory(at: repo.appendingPathComponent(".git"), withIntermediateDirectories: true)

        let rules = RuleFiles.find(for: repo.appendingPathComponent("app").path, home: home.path)
        let relative = rules.map { String($0.path.dropFirst(home.standardizedFileURL.path.count + 1)) }
        #expect(relative == [
            "work/repo/app/CLAUDE.md",
            "work/repo/AGENTS.md",
            "work/repo/.omp/rules/style.md",
            "work/repo/.cursor/rules/api.mdc",
            ".omp/agent/RULES.md",
        ])
        #expect(rules.last?.scope == "everywhere")
    }

    @Test("git offers the working changes, the branch and the commits")
    func gitReferences() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        git("init", "-q", "-b", "main", in: root)
        try write("one", to: "a.txt", in: root)
        git("add", "a.txt", in: root)
        git("commit", "-q", "-m", "Add the first file", in: root)
        try write("two", to: "a.txt", in: root)

        let references = GitReferences.list(in: root.path)
        #expect(references.map(\.kind) == [.changes, .branch, .commit])
        #expect(references[0].phrase == "the uncommitted changes (`git diff HEAD`)")
        #expect(references[1].name == "main")
        #expect(references[1].detail == "current branch")
        #expect(references[2].detail == "Add the first file")
        #expect(references[2].phrase.hasPrefix("commit `"))
    }

    @Test("a folder that is not a repository offers nothing from git")
    func noRepositoryNoReferences() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(GitReferences.list(in: root.path).isEmpty)
    }

    @Test("images go with the prompt the way omp takes them")
    func promptCarriesImages() {
        let image = ImageAttachment(name: "swatch.png", mimeType: "image/png", data: "iVBORw0K")
        let payload = AgentProcess.prompt("what colour?", behavior: "steer", images: [image])
        #expect(payload["images"] == .array([.object([
            "type": .string("image"), "data": .string("iVBORw0K"), "mimeType": .string("image/png"),
        ])]))
        #expect(payload["streamingBehavior"] == .string("steer"))
        #expect(AgentProcess.prompt("hi", behavior: nil, images: [])["images"] == nil)
    }

    @Test("only the images omp passes to a model are attached")
    func onlyImagesAttach() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        try write("%PDF-1.7", to: "spec.pdf", in: root)
        try write("png", to: "shot.PNG", in: root)
        #expect(ImageAttachment(contentsOf: root.appendingPathComponent("spec.pdf")) == nil)
        #expect(ImageAttachment(contentsOf: root.appendingPathComponent("shot.PNG"))?.mimeType == "image/png")
    }

    @Test("a command run from the terminal shows in the history with its output")
    func terminalRunsAreShown() {
        let blocks = History.blocks(from: [
            .object(["role": .string("bashExecution"), "command": .string("make test"), "output": .string("1 failed"), "exitCode": .number(2)]),
            .object(["role": .string("bashExecution"), "command": .string("ls"), "output": .string("a.txt"), "exitCode": .number(0)]),
        ])
        #expect(blocks == [
            .tool(id: "m0", name: "terminal", args: .object(["command": .string("make test")]), output: "1 failed", isError: true, running: false),
            .tool(id: "m1", name: "terminal", args: .object(["command": .string("ls")]), output: "a.txt", isError: false, running: false),
        ])
    }
}

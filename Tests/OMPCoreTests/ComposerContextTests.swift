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
        // Changed at known times: main.py first, then .gitignore, then the notes.
        for (offset, path) in ["src/app/main.py", ".gitignore", "notes/todo.md"].enumerated() {
            try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: 1_700_000_000 + Double(offset) * 60)],
                                                  ofItemAtPath: root.appendingPathComponent(path).path)
        }

        let listing = ProjectFiles.list(in: root.path)
        // The most recently changed first: what the reader is working on.
        #expect(listing.files == ["notes/todo.md", ".gitignore", "src/app/main.py"])
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
        #expect(references[2].when?.hasSuffix("ago") == true)
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

@Suite("What omp asks for")
struct AskingTests {
    @Test("a key, a token or a password is asked for in a hidden field; a sign-in code is not")
    func secretsAreHidden() {
        let key = UIRequest(json: .object(["id": .string("1"), "method": .string("input"), "title": .string("Paste your DeepSeek API key"), "placeholder": .string("sk-...")]))
        let code = UIRequest(json: .object(["id": .string("2"), "method": .string("input"), "title": .string("Paste the authorization code (or full redirect URL):")]))
        #expect(key?.isSecret == true)
        #expect(code?.isSecret == false)
    }

    @Test("a page to open is taken from omp's launch address, or else its address")
    func pageAddress() {
        let both = UIRequest(json: .object(["id": .string("1"), "method": .string("open_url"), "url": .string("https://auth.openai.com/x"), "launchUrl": .string("http://localhost:1455/launch")]))
        let only = UIRequest(json: .object(["id": .string("2"), "method": .string("open_url"), "url": .string("https://platform.deepseek.com/api_keys")]))
        #expect(both?.launchURL == "http://localhost:1455/launch")
        #expect(only?.launchURL == "https://platform.deepseek.com/api_keys")
    }
}

@Suite("Finding things by a few letters")
struct FuzzyMatchTests {
    private let paths = ["Sources/OMPApp/ComposerMenu.swift", "docs/menu-notes.md", "Tests/OMPAppTests/SkyTests.swift"]

    @Test("a match at the start of a name beats one inside a word, and the rest are left out")
    func ranking() {
        let ranked = FuzzyMatch.rank(paths, query: "menu") { [($0 as NSString).lastPathComponent, $0] }
        #expect(ranked == ["docs/menu-notes.md", "Sources/OMPApp/ComposerMenu.swift"])
    }

    @Test("letters are matched in order, with gaps")
    func inOrder() {
        #expect(FuzzyMatch.score("cmenu", in: "ComposerMenu.swift") != nil)
        #expect(FuzzyMatch.score("unem", in: "menu") == nil)
    }

    @Test("nothing typed keeps the list as it was")
    func emptyQuery() {
        #expect(FuzzyMatch.rank(paths, query: "  ") { [$0] } == paths)
    }
}

@Suite("Naming a conversation")
struct ConversationTitleTests {
    private func file(_ lines: [String]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-title-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("omp's title, else the first thing said, else untitled")
    func titles() throws {
        let titled = try file([#"{"type":"title","title":"Fix the upload limit"}"#,
                               #"{"type":"message","message":{"role":"user","content":"hi"}}"#])
        let untitled = try file([#"{"type":"session","id":"s"}"#,
                                 #"{"type":"message","message":{"role":"user","content":[{"type":"text","text":"Why does the 50 MB upload fail?\nIt says too large."}]}}"#])
        let long = try file([#"{"type":"message","message":{"role":"user","content":"\#(String(repeating: "word ", count: 30))"}}"#])
        let empty = try file([#"{"type":"session","id":"s"}"#])
        defer { for url in [titled, untitled, long, empty] { try? FileManager.default.removeItem(at: url) } }

        #expect(SessionFiles.title(from: titled) == "Fix the upload limit")
        #expect(SessionFiles.title(from: untitled) == "Why does the 50 MB upload fail?")
        #expect(SessionFiles.title(from: long).count == 80)
        #expect(SessionFiles.title(from: long).hasSuffix("…"))
        #expect(SessionFiles.title(from: empty) == "Untitled conversation")
    }
}

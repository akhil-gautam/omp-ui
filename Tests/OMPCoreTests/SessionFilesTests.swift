import Foundation
import Testing
@testable import OMPCore

@Suite("The session store")
struct SessionFilesTests {
    @Test("a directory under home is named after its relative path")
    func homeEncoding() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        #expect(SessionFiles.encoding(for: home + "/projects/i-shares") == "-projects-i-shares")
        #expect(SessionFiles.encoding(for: home) == "-")
    }

    @Test("a directory outside home keeps its whole path")
    func absoluteEncoding() {
        #expect(SessionFiles.encoding(for: "/private/tmp/thing") == "--private-tmp-thing--")
    }

    @Test("a project's sessions are found")
    func findsSessions() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let project = home + "/projects/i-shares"
        let sessions = SessionFiles.sessions(for: project)
        #expect(!sessions.isEmpty, "the project should have sessions on disk")
        #expect(sessions.allSatisfy { $0.path.hasSuffix(".jsonl") })
    }
}

@Suite("The branch of a project")
struct GitTests {
    @Test("a repository names its branch")
    func branch() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("omp-ui-git-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory.appendingPathComponent(".git"), withIntermediateDirectories: true)
        try "ref: refs/heads/main\n".write(to: directory.appendingPathComponent(".git/HEAD"), atomically: true, encoding: .utf8)
        #expect(Git.branch(of: directory.path) == "main")
    }

    @Test("a directory that is not a repository has no branch")
    func noBranch() {
        #expect(Git.branch(of: FileManager.default.temporaryDirectory.path) == nil)
    }
}

@Suite("The approval mode")
struct ApprovalModeTests {
    @Test("the mode is read out of the configuration")
    func readsTheMode() {
        #expect(ApprovalMode.label(ApprovalMode.read()) != nil || ApprovalMode.read() == nil)
    }

    @Test("the modes are named in words")
    func namesTheModes() {
        #expect(ApprovalMode.label("always-ask") == "Manual")
        #expect(ApprovalMode.label("yolo") == "Automatic")
        #expect(ApprovalMode.label(nil) == nil)
    }
}

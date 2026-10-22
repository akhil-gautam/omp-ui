import Foundation
import Testing
@testable import OMPCore

@Suite("The environment a Terminal window has")
struct ShellEnvironmentTests {
    private let marker = ShellEnvironment.marker

    @Test("the variables are read between the markers, past what the profiles print")
    func readsBetweenMarkers() {
        let output = "Last login: Tue\nwelcome!\(marker)KEY=a=b\0NOTE=two\nlines\0PWD=/tmp\0\(marker)bye"
        let environment = ShellEnvironment.parse(Data(output.utf8))
        #expect(environment == ["KEY": "a=b", "NOTE": "two\nlines"])
    }

    @Test("output without both markers is not taken for an environment")
    func needsBothMarkers() {
        #expect(ShellEnvironment.parse(Data("\(marker)KEY=value".utf8)) == nil)
    }

    /// A stand-in shell that prints a greeting, exports what a profile
    /// would, then runs the command it was given the way `sh -c` does.
    private func shell(_ body: String) throws -> (URL, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appendingPathComponent("shell")
        try "#!/bin/sh\n\(body)\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return (url, root)
    }

    @Test("what the shell's profile exports reaches omp, over the app's own")
    func profileWins() async throws {
        let (url, root) = try shell("echo 'Welcome back'; export OPENROUTER_API_KEY=from-profile; export PATH=/profile/bin; eval \"$4\"")
        defer { try? FileManager.default.removeItem(at: root) }
        let environment = await ShellEnvironment.load(shell: url.path, base: ["PATH": "/usr/bin", "OMP_UI_ONLY_IN_APP": "kept"])
        #expect(environment["OPENROUTER_API_KEY"] == "from-profile")
        #expect(environment["PATH"] == "/profile/bin")
        #expect(environment["OMP_UI_ONLY_IN_APP"] == "kept")
    }

    @Test("a shell that does not answer in time leaves the app's own environment")
    func slowShellFallsBack() async throws {
        let (url, root) = try shell("sleep 5")
        defer { try? FileManager.default.removeItem(at: root) }
        let started = ContinuousClock.now
        let environment = await ShellEnvironment.load(shell: url.path, base: ["PATH": "/usr/bin"], timeout: .milliseconds(300))
        #expect(environment == ["PATH": "/usr/bin"])
        #expect(ContinuousClock.now - started < .seconds(3))
    }
}

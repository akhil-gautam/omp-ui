import Foundation
import Testing
@testable import OMPApp
import OMPCore

/// A stand-in for omp that answers every command, on disk as an executable.
/// A prompt is refused the way OpenRouter refuses one without credits: the
/// turn ends with the reason, and the failed reply stays out of the history.
private func makeFakeOMP(in directory: URL) throws -> URL {
    let script = """
    #!/usr/bin/python3
    import json, sys
    def say(frame):
        print(json.dumps(frame), flush=True)
    say({"type": "ready", "protocolVersion": 1, "supportedProtocolVersions": [1, 2], "maxFrameBytes": 1048576})
    messages = []
    for line in sys.stdin:
        try:
            message = json.loads(line)
        except Exception:
            continue
        kind = message.get("type")
        data = {}
        if kind == "negotiate_protocol":
            data = {"protocolVersion": 2}
        elif kind == "get_messages":
            data = {"messages": messages}
        say({"id": message.get("id"), "type": "response", "command": kind, "success": True, "data": data})
        if kind == "prompt":
            user = {"role": "user", "content": message.get("message", "")}
            messages.append(user)
            failed = {"role": "assistant", "content": [], "stopReason": "error", "errorMessage": "402 This request requires more credits"}
            say({"type": "agent_start"})
            say({"type": "agent_end", "messages": [user, failed]})
    """
    let url = directory.appendingPathComponent("omp")
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

@Suite("Keeping omp running", .serialized)
@MainActor
struct LifecycleTests {
    /// A store working on one project, with the fake omp behind it.
    private func makeStore() async throws -> (AppStore, ProjectSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-lifecycle-\(UUID().uuidString)")
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fake = try makeFakeOMP(in: root)
        setenv(OMPBinary.overrideVariable, fake.path, 1)
        let store = AppStore(store: ProjectStore(url: root.appendingPathComponent("projects.json")))
        unsetenv(OMPBinary.overrideVariable)
        await store.addProject(path: project.path)
        let session = try #require(store.active)
        return (store, session, root)
    }

    @Test("a message to a project whose omp has gone starts it again")
    func restartsOnSend() async throws {
        let (store, session, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(await session.process?.isRunning() == true)

        // The process is still attached but omp is gone, the way it is after
        // a crash or a start that failed.
        await session.process?.stop()
        #expect(await session.process?.isRunning() == false)

        await store.send("hello")
        #expect(store.banner == nil)
        #expect(session.status != .error)
        #expect(await session.process?.isRunning() == true)
        await store.close(session.project.id)
    }

    @Test("opening a project that is running leaves its omp alone")
    func openingDoesNotRestart() async throws {
        let (store, session, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try #require(session.process)

        await store.open(session.project.id)
        #expect(session.process === first)
        #expect(await first.isRunning())
        await store.close(session.project.id)
    }

    @Test("a closed project stays closed")
    func closingStops() async throws {
        let (store, session, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        await store.close(session.project.id)
        #expect(session.process == nil)
        #expect(session.status == .stopped)
    }

    @Test("a turn the provider refuses is shown with its reason")
    func aRefusedTurnSaysWhy() async throws {
        let (store, session, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        await store.send("why is it failing?")
        // The reason arrives with the end of the turn, and the transcript is
        // read again after it.
        var reason: String?
        for _ in 0..<50 where reason == nil {
            try await Task.sleep(for: .milliseconds(100))
            for block in session.blocks {
                if case .failure(_, let text) = block { reason = text }
            }
        }
        #expect(reason == "402 This request requires more credits")
        // It follows the message it answered.
        let ids = session.blocks.map(\.id)
        #expect(ids.last?.hasPrefix("failure-") == true)
        await store.close(session.project.id)
    }
}

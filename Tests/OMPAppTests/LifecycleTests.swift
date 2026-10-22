import Foundation
import Testing
@testable import OMPApp
import OMPCore

/// A stand-in for omp that answers every command, on disk as an executable.
/// A prompt is refused the way OpenRouter refuses one without credits: the
/// turn ends with the reason, and the failed reply stays out of the history.
/// Like omp, it echoes the message it was sent, settles a slash command
/// itself, and ends each prompt it ran with a `prompt_result`; a message
/// saying "slow" waits a second before its turn starts.
private func makeFakeOMP(in directory: URL) throws -> URL {
    let script = """
    #!/usr/bin/python3
    import json, sys, time
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
        text = message.get("message", "")
        local = kind == "prompt" and text.startswith("/")
        data = {}
        if kind == "negotiate_protocol":
            data = {"protocolVersion": 2}
        elif kind == "get_messages":
            data = {"messages": messages}
        elif kind == "prompt":
            data = {"agentInvoked": not local}
        say({"id": message.get("id"), "type": "response", "command": kind, "success": True, "data": data})
        if kind == "prompt" and not local:
            user = {"role": "user", "content": text}
            messages.append(user)
            say({"type": "message_start", "messageId": "u%d" % len(messages), "message": user})
            if "slow" in text:
                time.sleep(1)
            failed = {"role": "assistant", "content": [], "stopReason": "error", "errorMessage": "402 This request requires more credits"}
            say({"type": "agent_start"})
            say({"type": "agent_end", "messages": [user, failed]})
            say({"type": "prompt_result", "id": message.get("id"), "agentInvoked": True, "status": "error",
                 "error": {"message": "402 This request requires more credits", "retryable": False}, "sessionSettled": True})
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
        let store = AppStore(store: ProjectStore(url: root.appendingPathComponent("projects.json")), locate: { fake.path })
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

    @Test("a sent message is shown once, and the turn is working until it ends")
    func sendingShowsOnceAndWorks() async throws {
        let (store, session, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        await store.send("a slow question")
        // omp has taken the message but has not started the turn yet.
        #expect(session.isWorking)
        #expect(session.status != .busy)
        // omp's echo takes over the copy shown the moment it was sent.
        for _ in 0..<20 where !session.blocks.contains(where: { $0.id == "u1" }) {
            try await Task.sleep(for: .milliseconds(50))
        }
        #expect(session.blocks.contains { $0.id == "u1" })
        #expect(session.blocks.filter { $0.text == "a slow question" }.count == 1)
        #expect(session.isWorking)

        for _ in 0..<60 where session.isWorking {
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!session.isWorking)
        await store.close(session.project.id)
    }

    @Test("a command omp settles itself ends the wait at once")
    func aLocalCommandEndsTheWait() async throws {
        let (store, session, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        await store.send("/model")
        #expect(!session.isWorking)
        await store.close(session.project.id)
    }
}

@Suite("A Mac without omp", .serialized)
@MainActor
struct SetupTests {
    /// A store whose omp is wherever `place` says, once something is there.
    private func makeStore(place: URL) async throws -> (AppStore, URL) {
        let root = place.deletingLastPathComponent()
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let store = AppStore(
            store: ProjectStore(url: root.appendingPathComponent("projects.json")),
            locate: { FileManager.default.isExecutableFile(atPath: place.path) ? place.path : nil }
        )
        await store.addProject(path: project.path)
        return (store, root)
    }

    private func scratch() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-setup-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test("without omp the setup screen takes over, and nothing is reported as an error")
    func missingIsNotAnError() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, _) = try await makeStore(place: root.appendingPathComponent("bin/omp"))
        #expect(store.ompMissing)
        #expect(store.banner == nil)
        #expect(store.active?.error == nil)
        #expect(store.active?.status == .stopped)
    }

    @Test("omp installed while the app is open is found without a relaunch")
    func foundWithoutRelaunch() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let place = root.appendingPathComponent("omp")
        let (store, _) = try await makeStore(place: place)
        #expect(store.ompMissing)

        try FileManager.default.copyItem(at: try makeFakeOMP(in: try scratch()), to: place)
        await store.checkForOMP()
        #expect(!store.ompMissing)
        #expect(await store.active?.process?.isRunning() == true)
        await store.close(store.active!.project.id)
    }

    @Test("the installer's output is shown as it runs, and a failed install says so")
    func failedInstallSaysSo() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, _) = try await makeStore(place: root.appendingPathComponent("omp"))

        await store.installOMP(command: "echo fetching omp; echo checksum failed >&2; exit 3")
        #expect(store.installLog == ["$ echo fetching omp; echo checksum failed >&2; exit 3", "fetching omp", "checksum failed"])
        #expect(store.installFailure?.contains("status 3") == true)
        #expect(!store.installing)
        #expect(store.ompMissing)
    }

    @Test("an install that leaves omp where the app looks starts the project")
    func installStartsTheProject() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let place = root.appendingPathComponent("omp")
        let (store, _) = try await makeStore(place: place)
        let fake = try makeFakeOMP(in: try scratch())

        await store.installOMP(command: "cp '\(fake.path)' '\(place.path)' && chmod +x '\(place.path)' && echo installed")
        #expect(store.installFailure == nil)
        #expect(!store.ompMissing)
        #expect(store.installLog.last == "installed")
        #expect(await store.active?.process?.isRunning() == true)
        await store.close(store.active!.project.id)
    }

    @Test("an install that leaves omp somewhere the app does not look says so")
    func installOutOfSight() async throws {
        let root = try scratch()
        defer { try? FileManager.default.removeItem(at: root) }
        let (store, _) = try await makeStore(place: root.appendingPathComponent("omp"))
        await store.installOMP(command: "echo installed elsewhere")
        #expect(store.ompMissing)
        #expect(store.installFailure?.contains("Choose omp") == true)
    }
}

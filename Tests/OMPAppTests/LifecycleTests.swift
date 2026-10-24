import Foundation
import Testing
@testable import OMPApp
import OMPCore

/// A stand-in for omp that answers every command, on disk as an executable.
/// A prompt is refused the way OpenRouter refuses one without credits: the
/// turn ends with the reason, and the failed reply stays out of the history.
/// Like omp, it echoes the message it was sent, settles a slash command
/// itself, and ends each prompt it ran with a `prompt_result`; a message
/// saying "slow" waits a second before its turn starts. It signs in the way
/// omp does: the page to open and a note first, then the answer; it can use
/// a model only once signed in, and refuses a provider that takes a key.
private func makeFakeOMP(in directory: URL) throws -> URL {
    let script = """
    #!/usr/bin/python3
    import json, os, sys, time
    def say(frame):
        print(json.dumps(frame), flush=True)
    say({"type": "ready", "protocolVersion": 1, "supportedProtocolVersions": [1, 2], "maxFrameBytes": 1048576})
    messages = []
    signed_in = set()
    claude = {"id": "claude-opus-5-5", "name": "Claude Opus 5.5", "provider": "anthropic"}
    gateway = {"id": "anthropic/claude-opus-5.5", "name": "Claude Opus 5.5", "provider": "openrouter"}
    # Like an API key a shell profile exports: present only if it reached omp.
    keyed = bool(os.environ.get("OMP_UI_TEST_OPENROUTER_KEY"))
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
        elif kind == "get_state":
            # The conversation it has open, written to disk as omp writes one:
            # the one it resumed, or its own.
            os.makedirs("\(directory.path)/conversations", exist_ok=True)
            argv = sys.argv[1:]
            session = argv[argv.index("--resume") + 1] if "--resume" in argv else "\(directory.path)/conversations/%d.jsonl" % os.getpid()
            open(session, "a").close()
            data = {"sessionFile": session, "argv": argv}
        elif kind == "get_available_models":
            data = {"models": ([claude] if "anthropic" in signed_in else []) + ([gateway] if keyed else [])}
        elif kind == "get_login_providers":
            data = {"providers": [
                {"id": "vault", "name": "Key Vault", "available": True, "authenticated": False},
                {"id": "openrouter", "name": "OpenRouter", "available": True, "authenticated": keyed},
                {"id": "anthropic", "name": "Anthropic (Claude Pro/Max)", "available": True, "authenticated": "anthropic" in signed_in},
                {"id": "retired", "name": "Retired", "available": False, "authenticated": False},
            ]}
        elif kind == "get_logout_accounts":
            data = {"accounts": [{"credentialId": 7, "provider": "anthropic", "label": "me@example.com", "detail": "", "type": "oauth", "active": True}] if "anthropic" in signed_in else []}
        elif kind == "logout":
            if message.get("credentialId") == 7:
                signed_in.discard(message.get("providerId"))
        elif kind == "login":
            provider = message.get("providerId")
            if provider == "vault":
                say({"id": message.get("id"), "type": "response", "command": kind, "success": False,
                     "error": "Provider 'vault' requires secret input, which is not supported in RPC mode. Use the terminal UI to log in."})
                continue
            say({"type": "extension_ui_request", "id": "page", "method": "open_url", "url": "https://claude.ai/oauth/authorize?code=true", "instructions": "Approve omp in your browser"})
            say({"type": "extension_ui_request", "id": "note", "method": "notify", "message": "Waiting for the browser"})
            time.sleep(0.3)
            signed_in.add(provider)
            data = {"providerId": provider}
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
        let store = AppStore(store: ProjectStore(url: root.appendingPathComponent("projects.json")), locate: { _ in fake.path })
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
            locate: { _ in FileManager.default.isExecutableFile(atPath: place.path) ? place.path : nil }
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

@Suite("Signing in through omp", .serialized)
@MainActor
struct SignInTests {
    /// Pages the store asked to open, kept instead of opened.
    private final class Browser {
        var opened: [URL] = []
    }

    private func makeStore() async throws -> (AppStore, ProjectSession, Browser, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-signin-\(UUID().uuidString)")
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fake = try makeFakeOMP(in: root)
        let browser = Browser()
        let store = AppStore(
            store: ProjectStore(url: root.appendingPathComponent("projects.json")),
            locate: { _ in fake.path },
            openURL: { browser.opened.append($0) }
        )
        await store.addProject(path: project.path)
        return (store, try #require(store.active), browser, root)
    }

    @Test("with no model to use, signing in opens the provider's page and brings the models")
    func signingInBringsModels() async throws {
        let (store, session, browser, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(session.needsSignIn)

        await store.loadProviders()
        // The well-known subscription first; one omp cannot offer is left out.
        #expect(store.providers.map(\.id) == ["anthropic", "vault", "openrouter"])

        await store.signIn(to: store.providers[0])
        #expect(browser.opened == [URL(string: "https://claude.ai/oauth/authorize?code=true")!])
        #expect(store.signIn == nil)
        #expect(!session.needsSignIn)
        #expect(session.model?.selector == "anthropic/claude-opus-5-5")
        #expect(store.providers.first?.authenticated == true)
        await store.close(session.project.id)
    }

    @Test("a provider omp will only sign in to in its own interface says so")
    func keyProvidersSayWhere() async throws {
        let (store, session, browser, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        await store.loadProviders()

        await store.signIn(to: try #require(store.providers.first { $0.id == "vault" }))
        #expect(browser.opened.isEmpty)
        #expect(store.signIn?.failure == "Key Vault asks for its key in a way omp only accepts in its own interface: run omp in Terminal and type /login.")
        store.dismissSignIn()
        #expect(store.signIn == nil)
        await store.close(session.project.id)
    }

    @Test("signing out removes the saved sign-in and the models with it")
    func signingOut() async throws {
        let (store, session, _, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        await store.loadProviders()
        await store.signIn(to: store.providers[0])
        #expect(!session.needsSignIn)

        await store.signOut(of: store.providers[0])
        #expect(store.providers.first?.authenticated == false)
        #expect(session.needsSignIn)
        await store.close(session.project.id)
    }
}

@Suite("omp started with the reader's shell environment", .serialized)
@MainActor
struct EnvironmentTests {
    private func makeStore(shell: [String: String]) async throws -> (AppStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-environment-\(UUID().uuidString)")
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fake = try makeFakeOMP(in: root)
        let store = AppStore(
            store: ProjectStore(url: root.appendingPathComponent("projects.json")),
            locate: { _ in fake.path },
            readEnvironment: { ["PATH": "/usr/bin:/bin"].merging(shell) { _, new in new } }
        )
        await store.loadEnvironment()
        await store.addProject(path: project.path)
        return (store, root)
    }

    @Test("a key the shell profile exports gives omp that provider's models")
    func profileKeyBringsModels() async throws {
        let (store, root) = try await makeStore(shell: ["OMP_UI_TEST_OPENROUTER_KEY": "from-profile"])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try #require(store.active)
        #expect(session.modelList.map(\.selector) == ["openrouter/anthropic/claude-opus-5.5"])
        #expect(store.providers.first { $0.id == "openrouter" }?.authenticated == true)
        await store.close(session.project.id)
    }

    @Test("without the key, that provider is offered to sign in to instead")
    func noKeyNoModels() async throws {
        let (store, root) = try await makeStore(shell: [:])
        defer { try? FileManager.default.removeItem(at: root) }
        let session = try #require(store.active)
        #expect(session.modelList.isEmpty)
        #expect(store.providers.first { $0.id == "openrouter" }?.authenticated == false)
        await store.close(session.project.id)
    }
}

@Suite("Idle projects sleep", .serialized)
@MainActor
struct IdleTests {
    private func makeStore() async throws -> (AppStore, ProjectSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-idle-\(UUID().uuidString)")
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fake = try makeFakeOMP(in: root)
        let store = AppStore(store: ProjectStore(url: root.appendingPathComponent("projects.json")), locate: { _ in fake.path })
        store.stopIdleAfterMinutes = 10
        await store.addProject(path: project.path)
        let session = try #require(store.active)
        await store.send("hello")
        for _ in 0..<50 where session.isWorking { try await Task.sleep(for: .milliseconds(50)) }
        await store.refresh(session)
        return (store, session, root)
    }

    private let later = Date().addingTimeInterval(11 * 60)

    @Test("a project idle for the time set is put to sleep, keeping what it shows")
    func idleSleeps() async throws {
        let (store, session, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let shown = session.blocks
        #expect(!shown.isEmpty)

        await store.stopIdleAgents(at: Date().addingTimeInterval(5 * 60))
        #expect(session.status == .idle)

        await store.stopIdleAgents(at: later)
        #expect(session.status == .asleep)
        #expect(session.process == nil)
        #expect(session.blocks == shown)
    }

    @Test("a message wakes a sleeping project, in the conversation it had open")
    func messageWakes() async throws {
        let (store, session, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let conversation = try #require(session.sessionFile)
        await store.stopIdleAgents(at: later)
        #expect(session.status == .asleep)

        // Looking at it does not wake it.
        await store.open(session.project.id)
        #expect(session.status == .asleep)
        #expect(session.process == nil)

        await store.send("again")
        let process = try #require(session.process)
        #expect(await process.isRunning())
        let argv = try await process.state()["argv"].array.map(\.string)
        #expect(argv.suffix(2) == ["--resume", conversation])
        await store.close(session.project.id)
    }

    @Test("a conversation omp never wrote is not resumed; omp starts afresh")
    func unwrittenStartsAfresh() async throws {
        let (store, session, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        await store.stopIdleAgents(at: later)
        // omp writes a conversation only once a reply comes.
        session.sessionFile = "/nonexistent/omp-ui/never-written.jsonl"

        await store.send("again")
        let argv = try await #require(session.process).state()["argv"].array.map(\.string)
        #expect(!argv.contains("--resume"))
        await store.close(session.project.id)
    }

    @Test("a project with something going on is left running")
    func busyStaysAwake() async throws {
        let (store, session, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        session.pendingRequest = UIRequest(id: "q", method: "confirm", title: "Go ahead?")
        await store.stopIdleAgents(at: later)
        #expect(session.process != nil)
        session.pendingRequest = nil

        session.settled = false
        await store.stopIdleAgents(at: later)
        #expect(session.process != nil)
        session.settled = true

        session.queue = Queue(steering: [], followUp: ["and then"])
        await store.stopIdleAgents(at: later)
        #expect(session.process != nil)
        session.queue = Queue(steering: [], followUp: [])

        session.blocks.append(.tool(id: "t", name: "terminal", args: nil, output: nil, isError: false, running: true))
        await store.stopIdleAgents(at: later)
        #expect(session.process != nil)
        session.blocks.removeLast()

        store.stopIdleAfterMinutes = 0
        await store.stopIdleAgents(at: later)
        #expect(session.process != nil)
        await store.close(session.project.id)
    }
}

@Suite("Many conversations in a project", .serialized)
@MainActor
struct ConversationTests {
    private func makeStore() async throws -> (AppStore, ProjectSession, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-conversations-\(UUID().uuidString)")
        let project = root.appendingPathComponent("project")
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        let fake = try makeFakeOMP(in: root)
        let store = AppStore(store: ProjectStore(url: root.appendingPathComponent("projects.json")), locate: { _ in fake.path })
        await store.addProject(path: project.path)
        return (store, try #require(store.active), root)
    }

    @Test("a new conversation gets its own omp, starting afresh, and the first keeps running")
    func newConversationRunsBeside() async throws {
        let (store, first, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstProcess = try #require(first.process)

        await store.newConversation()
        let second = try #require(store.active)
        #expect(second !== first)
        #expect(second.project.id == first.project.id)
        #expect(store.sessions(of: first.project.id).count == 2)
        #expect(first.process === firstProcess)
        #expect(await firstProcess.isRunning())
        let argv = try await #require(second.process).state()["argv"].array.map(\.string)
        #expect(!argv.contains("--resume"))
        #expect(second.sessionFile != first.sessionFile)

        // A message goes to the conversation that is open, and only to it.
        await store.send("only here")
        #expect(second.blocks.contains { $0.text == "only here" })
        #expect(!first.blocks.contains { $0.text == "only here" })
        await store.close(first.project.id)
        #expect(first.process == nil && second.process == nil)
    }

    @Test("each conversation is listed once, newest first, named by what was said in it")
    func theListNamesEach() async throws {
        let (store, first, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        await store.newConversation()
        let second = try #require(store.active)
        await store.send("fix the upload limit\nand the tests")

        let listed = store.conversations(in: first.project.id)
        #expect(listed.count == 2)
        #expect(listed.first?.session === second)
        #expect(listed.first?.title == "fix the upload limit")
        #expect(listed.last?.session === first)
        #expect(listed.last?.title == "New conversation")
        #expect(store.activeTitle == "fix the upload limit")
        await store.close(first.project.id)
    }

    @Test("going back to a conversation shows the same one, with its omp left alone")
    func goingBackKeepsIt() async throws {
        let (store, first, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstProcess = try #require(first.process)
        await store.newConversation()
        let second = try #require(store.active)

        let entry = try #require(store.conversations(in: first.project.id).first { $0.session === first })
        await store.openConversation(entry)
        #expect(store.active === first)
        #expect(first.process === firstProcess)
        #expect(store.sessions(of: first.project.id).count == 2)

        // Opening the project again returns to the conversation last open.
        await store.openConversation(try #require(store.conversations(in: first.project.id).first { $0.session === second }))
        await store.open(first.project.id)
        #expect(store.active === second)
        await store.close(first.project.id)
    }

    @Test("a conversation on disk opens with omp resuming it")
    func aWrittenConversationResumes() async throws {
        let (store, first, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("earlier.jsonl").path
        FileManager.default.createFile(atPath: file, contents: Data())

        await store.openConversation(Conversation(id: file, projectID: first.project.id, title: "Earlier",
                                                  date: .distantPast, path: file, session: nil))
        let opened = try #require(store.active)
        #expect(opened !== first)
        let argv = try await #require(opened.process).state()["argv"].array.map(\.string)
        #expect(argv.suffix(2) == ["--resume", file])

        // Opened a second time, it is the same conversation, not another omp.
        await store.openConversation(Conversation(id: file, projectID: first.project.id, title: "Earlier",
                                                  date: .distantPast, path: file, session: nil))
        #expect(store.active === opened)
        #expect(store.sessions(of: first.project.id).count == 2)
        await store.close(first.project.id)
    }

    @Test("stopping one conversation leaves the others running")
    func stoppingOne() async throws {
        let (store, first, root) = try await makeStore()
        defer { try? FileManager.default.removeItem(at: root) }
        await store.newConversation()
        let second = try #require(store.active)

        await store.stop(first)
        #expect(first.process == nil)
        #expect(first.status == .stopped)
        #expect(await second.process?.isRunning() == true)
        await store.close(first.project.id)
    }
}

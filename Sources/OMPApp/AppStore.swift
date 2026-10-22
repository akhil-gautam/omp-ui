import AppKit
import Foundation
import Observation
import OMPCore

/// What the session is doing.
public enum SessionStatus: String, Sendable {
    case starting, idle, busy, stopped, error
}

/// A message from omp or one of its extensions.
public struct Notice: Identifiable, Sendable, Equatable {
    public var id: String
    public var level: String
    public var message: String

    public init(id: String = UUID().uuidString, level: String, message: String) {
        self.id = id
        self.level = level
        self.message = message
    }
}

/// One project, and everything the interface shows about it.
@MainActor
@Observable
public final class ProjectSession {
    public let project: Project
    public var status: SessionStatus = .stopped
    public var blocks: [Block] = []
    public var queue = Queue()
    public var commands: [SlashCommand] = []
    public var model: ModelInfo?
    public var thinkingLevel = "off"
    public var contextUsage: ContextUsage?
    public var todoPhases: [TodoPhase] = []
    public var pendingRequest: UIRequest?
    public var notices: [Notice] = []
    public var statusText: String?
    public var branch: String?
    public var error: String?
    public var mode: SessionMode = .interactive
    public var modelList: [ModelInfo] = []
    /// When the turn in progress began: from the moment a message was sent,
    /// not from omp's `agent_start`, which can come seconds later.
    public var turnStarted: Date?

    @ObservationIgnored public var process: AgentProcess?
    /// The start in progress, so a second caller waits for it instead of
    /// starting another omp.
    @ObservationIgnored public var starting: Task<Void, Never>?
    /// The turns that failed, and where each one belongs. omp leaves them out
    /// of the history it returns, so they are kept here.
    public var failures: [History.Failure] = []
    /// Reasons that have arrived but are not yet placed in the transcript.
    @ObservationIgnored public var unplacedFailures: [String] = []
    /// The failures the resumed session file records, until the history
    /// they belong to has been read.
    @ObservationIgnored public var recordedFailures: (failures: [History.Failure], turns: Int)?

    public init(project: Project) {
        self.project = project
    }

    public var isBusy: Bool { status == .busy }
    /// Whether a turn is under way, including the wait before omp starts it.
    public var isWorking: Bool { isBusy || turnStarted != nil }
    public var hasTodos: Bool { todoPhases.contains { !$0.tasks.isEmpty } }
    /// Whether omp has said which models it can use, at least once.
    public var modelsLoaded = false
    /// omp is up but can use no model: nothing is signed in.
    public var needsSignIn: Bool { modelsLoaded && modelList.isEmpty }
}

/// A sign-in under way: the page omp sent, what it has said since, and why it
/// stopped, if it did.
public struct SignIn: Equatable {
    public let token = UUID()
    public var provider: LoginProvider
    public var url: String?
    public var instructions: String?
    public var progress: String?
    public var failure: String?
}

/// The app's root store: the projects, their sessions, and what the reader
/// is looking at.
@MainActor
@Observable
public final class AppStore {
    public var projects: [Project] = []
    public var activeID: String?
    public var sessions: [String: ProjectSession] = [:]
    public var banner: String?
    /// Text for the composer to take up — from a starter on the empty page —
    /// and focus on. The composer clears it once taken.
    public var pendingDraft: String?
    public var isLoading = true
    /// The reader's name, for the greeting.
    public var userName: String = NSFullUserName()
    /// The projects that have been opened, most recent first.
    public var history: [String] = []
    /// Where the reader is in that history.
    public var historyIndex: Int = 0
    /// Whether there is somewhere to go back to.
    public var canGoBack: Bool { historyIndex > 0 }
    /// Whether there is somewhere to go forward to.
    public var canGoForward: Bool { historyIndex + 1 < history.count }
    /// The name of the chosen theme.
    public var themeName: String = UserDefaults.standard.string(forKey: "omp-ui.theme") ?? "Paper" {
        didSet { UserDefaults.standard.set(themeName, forKey: "omp-ui.theme") }
    }
    /// The colours the interface is drawn with.
    public var palette: Palette { Theme.palette(named: themeName) }
    /// Whether the sidebar is shown.
    public var sidebarOpen = true

    @ObservationIgnored private let store: ProjectStore
    /// Finds omp in an environment. Asked at every start, so omp installed
    /// while the app is open is found without a relaunch.
    @ObservationIgnored private let locate: ([String: String]) -> String?
    /// Reads the environment omp should start with.
    @ObservationIgnored private let readEnvironment: () async -> [String: String]
    /// The environment omp starts with: the reader's login shell's, read at
    /// launch, so omp sees the same keys and PATH it sees in Terminal.
    @ObservationIgnored public private(set) var environment = ProcessInfo.processInfo.environment

    /// Whether omp was missing the last time it was looked for; the window
    /// then shows how to install it instead of a conversation.
    public var ompMissing = false
    /// What the installer has printed so far.
    public var installLog: [String] = []
    public var installing = false
    /// Why the last install did not leave a usable omp behind.
    public var installFailure: String?

    /// What omp can sign in to, as the open project's omp lists it.
    public var providers: [LoginProvider] = []
    /// The sign-in under way, or the one that just failed.
    public var signIn: SignIn?
    /// Whether the reader asked to see the accounts, from Settings.
    public var showingAccounts = false
    /// Opens a page in the browser.
    @ObservationIgnored private let openURL: (URL) -> Void

    public init(
        store: ProjectStore = ProjectStore(),
        locate: @escaping ([String: String]) -> String? = { OMPBinary.resolve(environment: $0) },
        readEnvironment: @escaping () async -> [String: String] = { await ShellEnvironment.load() },
        openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }
    ) {
        self.store = store
        self.locate = locate
        self.readEnvironment = readEnvironment
        self.openURL = openURL
    }

    /// Reads the reader's shell environment, for every omp started after.
    public func loadEnvironment() async {
        environment = await readEnvironment()
    }

    public var active: ProjectSession? {
        guard let activeID else { return nil }
        return sessions[activeID]
    }

    /// How omp asks before it acts, as configured.
    public var approvalLabel: String? { ApprovalMode.label(ApprovalMode.read()) }

    /// Asks the reader for a project directory.
    public func addProjectPicker() async {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        panel.message = "Choose a project for omp to work in."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        await addProject(path: url.path)
    }

    // MARK: - Life

    public func restore() async {
        let (projects, activeID) = store.load()
        self.projects = projects
        self.activeID = activeID
        await loadEnvironment()
        isLoading = false
        ompMissing = locate(environment) == nil
        if let activeID, projects.contains(where: { $0.id == activeID }) {
            await open(activeID)
        }
    }

    /// Opens a project: shows it, and starts its omp unless it is already up.
    public func open(_ id: String, record: Bool = true) async {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        activeID = id
        if record {
            history.removeAll { $0 == id }
            history.insert(id, at: 0)
            if history.count > 24 { history.removeLast() }
            historyIndex = 0
        }

        let session = sessions[id] ?? ProjectSession(project: project)
        sessions[id] = session
        // A project that is already up is only shown: starting it again would
        // put a second omp on the same session and drop the first.
        if let process = session.process, await process.isRunning() { return }
        await start(session)
    }

    /// Starts a project's omp — once, however many ask at the same time.
    private func start(_ session: ProjectSession) async {
        if let starting = session.starting {
            await starting.value
            return
        }
        let task = Task { await self.boot(session) }
        session.starting = task
        await task.value
        session.starting = nil
    }

    private func boot(_ session: ProjectSession) async {
        let project = session.project
        session.status = .starting
        session.error = nil
        if let stale = session.process {
            session.process = nil
            await stale.stop()
        }

        guard let executable = locate(environment) else {
            // Not a failure of the project: the setup screen takes over.
            session.status = .stopped
            ompMissing = true
            return
        }
        ompMissing = false

        let id = project.id
        let process = AgentProcess(project: project, executable: executable, environment: environment) { [weak self] frame in
            await MainActor.run { self?.apply(frame, to: id) }
        }
        session.process = process

        do {
            // A project that has been worked on before picks up where it
            // left off.
            let resume = SessionFiles.sessions(for: project.path).first?.path
            try await process.start(resuming: resume)
            if let resume {
                session.recordedFailures = await Task.detached {
                    History.failures(inSessionFile: URL(fileURLWithPath: resume))
                }.value
            }
            try await process.setMode(session.mode)
            session.status = .idle
            await refresh(id)
        } catch {
            // A start that failed leaves nothing behind, so the next message
            // starts omp again instead of talking to a process that is gone.
            session.process = nil
            await process.stop()
            session.status = .error
            session.error = error.localizedDescription
        }
    }

    // MARK: - Installing omp

    /// Looks for omp again — after it was installed, or pointed at — and
    /// starts the open project with it.
    public func checkForOMP() async {
        ompMissing = locate(environment) == nil
        guard !ompMissing else { return }
        installFailure = nil
        if let activeID { await open(activeID) }
    }

    /// Uses an omp the reader chose, and remembers it.
    public func chooseOMP(at path: String) async {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            installFailure = "\(path) is not a program the app can run."
            return
        }
        UserDefaults.standard.set(path, forKey: OMPBinary.chosenKey)
        await checkForOMP()
        if ompMissing {
            installFailure = "The app still cannot use \(path)."
        }
    }

    /// Runs omp's official installer, showing what it prints, then starts
    /// the open project with the omp it installed.
    public func installOMP(command: String = OMPInstaller.command) async {
        guard !installing else { return }
        installing = true
        installFailure = nil
        installLog = ["$ \(command)"]
        let status = await OMPInstaller.run(command, environment: environment) { line in
            await MainActor.run { self.installLog.append(line) }
        }
        installing = false
        guard status == 0 else {
            installFailure = "The installer stopped with status \(status). Its output is above."
            return
        }
        await checkForOMP()
        if ompMissing {
            installFailure = "omp was installed, but not where the app looks for it. Use Choose omp… to point at it."
        }
    }

    /// The project's omp, started again if it has stopped.
    private func liveProcess(_ session: ProjectSession) async -> AgentProcess? {
        if let process = session.process, await process.isRunning() { return process }
        await start(session)
        if let process = session.process, await process.isRunning() { return process }
        banner = session.error ?? "omp could not start for \(session.project.name)."
        return nil
    }

    /// Goes back through the projects that have been open.
    public func goBack() async {
        await travel(to: historyIndex - 1)
    }

    /// Goes forward through the projects that have been open.
    public func goForward() async {
        await travel(to: historyIndex + 1)
    }

    private func travel(to index: Int) async {
        guard history.indices.contains(index) else { return }
        historyIndex = index
        await open(history[index], record: false)
    }

    /// Ends a project's omp, which gives its memory back.
    public func close(_ id: String) async {
        guard let session = sessions[id] else { return }
        // A start in progress finishes first, so it cannot attach a process
        // after the project has been closed.
        if let starting = session.starting { await starting.value }
        let process = session.process
        session.process = nil
        session.status = .stopped
        await process?.stop()
    }

    public func addProject(path: String) async {
        let project = Project(path: path)
        projects.append(project)
        persist()
        await open(project.id)
    }

    public func removeProject(_ id: String) async {
        await close(id)
        sessions.removeValue(forKey: id)
        projects.removeAll { $0.id == id }
        history.removeAll { $0 == id }
        historyIndex = min(historyIndex, max(history.count - 1, 0))
        if activeID == id { activeID = projects.first?.id }
        persist()
    }

    private func persist() {
        try? store.save(projects: projects, activeID: activeID)
    }

    // MARK: - Reading

    /// Reads everything the interface shows about a project.
    public func refresh(_ id: String) async {
        guard let session = sessions[id], let process = session.process else { return }
        if let path = project(id)?.path {
            session.branch = Git.branch(of: path)
        }

        do {
            let state = try await process.state()
            session.model = ModelInfo(json: state["model"])
            session.thinkingLevel = state["thinkingLevel"].optionalString ?? "off"
            session.contextUsage = ContextUsage(json: state["contextUsage"])
            session.todoPhases = state["todoPhases"].array.compactMap(TodoPhase.init(json:))
            let history = try await process.history()
            let turns = history.reduce(0) { count, block in
                if case .user = block { return count + 1 }
                return count
            }
            if let recorded = session.recordedFailures {
                // The file holds every failure of the session, so it replaces
                // what was kept from before omp was started again.
                session.failures = History.align(recorded, toHistoryTurns: turns)
                session.recordedFailures = nil
            }
            if !session.unplacedFailures.isEmpty {
                // A failure belongs to the turn that just ended: the last
                // thing the reader said.
                session.failures += session.unplacedFailures.map { History.Failure(turn: turns, text: $0) }
                session.unplacedFailures = []
            }
            session.blocks = History.weave(session.failures, into: history)
            session.commands = (try? await process.availableCommands()) ?? session.commands
            if let models = try? await process.availableModels() {
                session.modelList = models
                session.modelsLoaded = true
            }
            // Which providers are signed in, for the picker's list of the
            // ones that are not.
            if let providers = try? await process.loginProviders() {
                self.providers = LoginProvider.ordered(providers)
            }
        } catch {
            session.error = error.localizedDescription
        }
    }

    private func project(_ id: String) -> Project? {
        projects.first { $0.id == id }
    }

    // MARK: - Signing in

    /// Reads which providers omp can sign in to, through the open project.
    public func loadProviders() async {
        guard let session = active, let process = await liveProcess(session) else { return }
        if let providers = try? await process.loginProviders() {
            self.providers = LoginProvider.ordered(providers)
        }
    }

    /// Signs in to a provider through omp. omp sends the page to finish on,
    /// which opens in the browser; once omp confirms, every open project
    /// reads its models again, and one that has no model is given one.
    public func signIn(to provider: LoginProvider) async {
        guard signIn == nil || signIn?.failure != nil else { return }
        guard let session = active, let process = await liveProcess(session) else { return }
        let flow = SignIn(provider: provider)
        signIn = flow
        do {
            try await process.login(provider: provider.id)
            // A sign-in the reader walked away from is not reported.
            guard signIn?.token == flow.token else { return }
            signIn = nil
            await loadProviders()
            for (id, other) in sessions where other.process != nil {
                await refresh(id)
            }
            if session.model == nil, let model = session.modelList.first(where: { $0.provider == provider.id }) ?? session.modelList.first {
                await setModel(model)
            }
        } catch {
            guard signIn?.token == flow.token else { return }
            signIn?.failure = LoginProvider.explain(error.localizedDescription, provider: provider.name)
        }
    }

    /// Stops waiting on a sign-in; omp gives up on its own in time.
    public func dismissSignIn() {
        signIn = nil
    }

    /// Opens the sign-in page again.
    public func reopenSignInPage() {
        if let address = signIn?.url, let url = URL(string: address) { openURL(url) }
    }

    /// Removes every saved sign-in for a provider.
    public func signOut(of provider: LoginProvider) async {
        guard let session = active, let process = await liveProcess(session) else { return }
        do {
            for account in try await process.loginAccounts(provider: provider.id) {
                try await process.logout(provider: provider.id, account: account.credentialID)
            }
            await loadProviders()
            for (id, other) in sessions where other.process != nil {
                await refresh(id)
            }
        } catch {
            banner = error.localizedDescription
        }
    }

    // MARK: - Talking to omp

    public func send(_ text: String, behavior: String? = nil, images: [ImageAttachment] = []) async {
        guard let session = active else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || !images.isEmpty else { return }
        // Show the message straight away; omp's echo takes this copy over.
        let attached = images.isEmpty ? "" : "\n\n" + images.map { "🖼 \($0.name)" }.joined(separator: "  ")
        session.blocks.append(.user(id: "\(Transcript.shownPrefix)\(UUID().uuidString)", text: trimmed + attached))
        if session.turnStarted == nil { session.turnStarted = .now }
        guard let process = await liveProcess(session) else {
            settleUnstartedTurn(session)
            return
        }
        do {
            let started = try await process.send(trimmed, behavior: behavior, images: images)
            if !started { settleUnstartedTurn(session) }
        } catch {
            banner = error.localizedDescription
            settleUnstartedTurn(session)
        }
    }

    /// Runs a shell command in the open project through omp, which keeps its
    /// output in the session for the agent to read. The command shows as a
    /// card while it runs and holds its output when it ends.
    public func runInTerminal(_ command: String) async {
        guard let session = active else { return }
        let command = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return }
        let id = "terminal-\(UUID().uuidString)"
        let args: JSONValue = .object(["command": .string(command)])
        session.blocks.append(.tool(id: id, name: "terminal", args: args, output: nil, isError: false, running: true))
        guard let process = await liveProcess(session) else { return }
        do {
            let result = try await process.bash(command)
            if let index = session.blocks.firstIndex(where: { $0.id == id }) {
                session.blocks[index] = .tool(id: id, name: "terminal", args: args, output: result.output, isError: result.failed, running: false)
            }
        } catch {
            session.blocks.removeAll { $0.id == id }
            banner = error.localizedDescription
        }
    }

    /// The open project's conversations, newest first.
    public func conversations() -> [SessionFile] {
        guard let session = active else { return [] }
        return SessionFiles.sessions(for: session.project.path)
    }

    /// Switches the open project to one of its earlier conversations.
    public func openConversation(_ file: SessionFile) async {
        guard let session = active, let process = await liveProcess(session) else { return }
        do {
            guard try await process.switchSession(path: file.path) else {
                banner = "omp would not open \u{201C}\(file.title)\u{201D}: it was recorded in another folder."
                return
            }
            // The failures kept belonged to the conversation being left; the
            // new one's are read from its file.
            session.failures = []
            session.unplacedFailures = []
            session.recordedFailures = await Task.detached {
                History.failures(inSessionFile: URL(fileURLWithPath: file.path))
            }.value
            await refresh(session.project.id)
        } catch {
            banner = error.localizedDescription
        }
    }

    /// Ends the wait for a turn omp is not going to run.
    private func settleUnstartedTurn(_ session: ProjectSession) {
        if !session.isBusy { session.turnStarted = nil }
    }

    public func abort() async {
        guard let session = active, let process = session.process else { return }
        do {
            try await process.abort()
        } catch {
            banner = error.localizedDescription
        }
    }

    public func setMode(_ mode: SessionMode) async {
        guard let session = active else { return }
        session.mode = mode
        guard let process = session.process else { return }
        do {
            try await process.setMode(mode)
        } catch {
            banner = error.localizedDescription
        }
    }

    public func setModel(_ model: ModelInfo) async {
        guard let session = active, let process = await liveProcess(session) else { return }
        do {
            try await process.setModel(provider: model.provider, modelID: model.id)
            session.model = model
        } catch {
            banner = error.localizedDescription
        }
    }

    public func setThinking(_ level: String) async {
        guard let session = active, let process = await liveProcess(session) else { return }
        do {
            try await process.setThinking(level)
            session.thinkingLevel = level
        } catch {
            banner = error.localizedDescription
        }
    }

    public func answer(_ request: UIRequest, value: String, cancelled: Bool = false) async {
        guard let session = active, let process = await liveProcess(session) else { return }
        session.pendingRequest = nil
        do {
            try await process.answer(request, value: value, cancelled: cancelled)
        } catch {
            banner = error.localizedDescription
        }
    }

    public func removeQueued(_ text: String, queue: String) async {
        guard let session = active, let process = session.process else { return }
        do {
            try await process.removeQueued(text, queue: queue)
        } catch {
            banner = error.localizedDescription
        }
    }

    public func newSession() async {
        guard let session = active, let process = session.process else { return }
        do {
            try await process.newSession()
            session.blocks.removeAll()
        } catch {
            banner = error.localizedDescription
        }
    }

    // MARK: - The event stream

    private func apply(_ frame: JSONValue, to id: String) {
        guard let session = sessions[id] else { return }
        switch frame["type"].string {
        case "agent_start":
            session.status = .busy
            if session.turnStarted == nil { session.turnStarted = .now }
        case "agent_end":
            session.status = .idle
            session.turnStarted = nil
            session.unplacedFailures += History.failureReasons(in: frame)
            Task { await self.refresh(id) }
        case "message_start":
            let messageID = frame["messageId"].string
            let role = frame["message"]["role"].string
            if role == "user" {
                let text = History.plainText(frame["message"]["content"])
                if !text.isEmpty { Transcript.receive(userMessage: messageID, text: text, into: &session.blocks) }
            }
        case "message_update":
            applyDelta(frame, to: session)
        case "tool_execution_start":
            session.blocks.append(.tool(
                id: frame["toolCallId"].string,
                name: frame["toolName"].string,
                args: frame["args"],
                output: nil,
                isError: false,
                running: true
            ))
        case "tool_execution_end":
            let callID = frame["toolCallId"].string
            let output = History.plainText(frame["result"])
            let isError = frame["isError"].bool
            if let index = session.blocks.firstIndex(where: { block in
                if case .tool(let blockID, _, _, _, _, _) = block { return blockID == callID }
                return false
            }), case .tool(let blockID, let name, let args, _, _, _) = session.blocks[index] {
                session.blocks[index] = .tool(id: blockID, name: name, args: args, output: output, isError: isError, running: false)
            }
        case "queue_update":
            session.queue = Queue(
                steering: frame["steering"].array.compactMap(\.optionalString),
                followUp: frame["followUp"].array.compactMap(\.optionalString)
            )
        case "notice":
            session.notices.append(Notice(level: frame["level"].string, message: frame["message"].string))
            if session.notices.count > 20 { session.notices.removeFirst(session.notices.count - 20) }
        case "extension_ui_request":
            let method = frame["method"].string
            if method == "cancel" {
                if session.pendingRequest?.id == frame["targetId"].string { session.pendingRequest = nil }
            } else if method == "notify" {
                // During a sign-in, omp's notes say how it is going.
                if signIn != nil { signIn?.progress = frame["message"].string }
            } else if method == "open_url", signIn != nil, let request = UIRequest(json: frame) {
                // The page a sign-in finishes on opens in the browser rather
                // than waiting in a dialog; omp does not wait on it.
                signIn?.url = request.launchURL
                signIn?.instructions = request.instructions
                if let address = request.launchURL, let url = URL(string: address) { openURL(url) }
            } else if let request = UIRequest(json: frame) {
                session.pendingRequest = request
            }
        case "extension_ui_request_cancelled":
            session.pendingRequest = nil
        case "available_commands_update":
            session.commands = frame["commands"].array.compactMap(SlashCommand.init(json:))
        case "prompt_result":
            // A turn that ran and failed arrives in the transcript; one that
            // failed before reaching the agent has nowhere else to be said.
            if frame["status"].string == "error", !frame["agentInvoked"].bool {
                let message = frame["error"]["message"].string
                banner = message.isEmpty ? "omp could not start the turn." : message
            }
            if !frame["agentInvoked"].bool { settleUnstartedTurn(session) }
        case "disconnected":
            session.status = .stopped
            session.turnStarted = nil
            session.error = frame["reason"].optionalString
        default:
            break
        }
    }

    private func applyDelta(_ frame: JSONValue, to session: ProjectSession) {
        let messageID = frame["messageId"].string
        let event = frame["assistantMessageEvent"]
        let delta = event["delta"].optionalString ?? ""
        guard !delta.isEmpty else { return }
        switch event["type"].string {
        case "text_delta":
            append(to: session, id: messageID, text: delta, kind: .text)
        case "thinking_delta":
            append(to: session, id: messageID, text: delta, kind: .thinking)
        default:
            break
        }
    }

    private enum Channel { case text, thinking }

    private func append(to session: ProjectSession, id: String, text: String, kind: Channel) {
        if let index = session.blocks.firstIndex(where: { $0.id == id }) {
            switch session.blocks[index] {
            case .text(let blockID, let body):
                session.blocks[index] = .text(id: blockID, text: body + text)
            case .thinking(let blockID, let body):
                session.blocks[index] = .thinking(id: blockID, text: body + text)
            default:
                break
            }
            return
        }
        switch kind {
        case .text: session.blocks.append(.text(id: id, text: text))
        case .thinking: session.blocks.append(.thinking(id: id, text: text))
        }
    }
}

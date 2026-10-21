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
    public var inventory: Inventory?
    public var branch: String?
    public var error: String?
    public var mode: SessionMode = .interactive
    public var modelList: [ModelInfo] = []

    @ObservationIgnored public var process: AgentProcess?

    public init(project: Project) {
        self.project = project
    }

    public var isBusy: Bool { status == .busy }
    public var hasTodos: Bool { todoPhases.contains { !$0.tasks.isEmpty } }
}

/// The pages the main column can show.
public enum AppView: String, CaseIterable, Sendable {
    case transcript, overview, tools, skills, extensions, prompts

    public var title: String {
        switch self {
        case .transcript: "Transcript"
        case .overview: "Overview"
        case .tools: "Tools"
        case .skills: "Skills"
        case .extensions: "Extensions"
        case .prompts: "Prompts"
        }
    }
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
    public var view: AppView = .transcript
    public var isLoading = true
    /// The reader's name, for the greeting.
    public var userName: String = NSFullUserName()
    /// The name of the chosen theme.
    public var themeName: String = UserDefaults.standard.string(forKey: "omp-ui.theme") ?? "Void" {
        didSet { UserDefaults.standard.set(themeName, forKey: "omp-ui.theme") }
    }
    /// The colours the interface is drawn with.
    public var palette: Palette { Theme.palette(named: themeName) }
    /// Whether the sidebar is shown.
    public var sidebarOpen = true

    @ObservationIgnored private let store: ProjectStore
    @ObservationIgnored private let executable: String?

    public init(store: ProjectStore = ProjectStore()) {
        self.store = store
        self.executable = OMPBinary.resolve()
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
        isLoading = false
        if let activeID, projects.contains(where: { $0.id == activeID }) {
            await open(activeID)
        }
    }

    /// Opens a project: starts its omp, and reads what it has.
    public func open(_ id: String) async {
        guard let project = projects.first(where: { $0.id == id }) else { return }
        activeID = id
        view = .transcript

        let session = sessions[id] ?? ProjectSession(project: project)
        sessions[id] = session
        session.status = .starting

        guard let executable else {
            session.status = .error
            session.error = "omp was not found. Install it (https://omp.sh) or set \(OMPBinary.overrideVariable)."
            return
        }

        let process = AgentProcess(project: project, executable: executable) { [weak self] frame in
            await MainActor.run { self?.apply(frame, to: id) }
        }
        session.process = process

        do {
            // A project that has been worked on before picks up where it
            // left off.
            let resume = SessionFiles.sessions(for: project.path).first?.path
            try await process.start(resuming: resume)
            try await process.setMode(session.mode)
            session.status = .idle
            await refresh(id)
        } catch {
            session.status = .error
            session.error = error.localizedDescription
        }
    }

    /// Ends a project's omp, which gives its memory back.
    public func close(_ id: String) async {
        guard let session = sessions[id] else { return }
        await session.process?.stop()
        session.process = nil
        session.status = .stopped
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
            session.blocks = try await process.history()
            session.commands = (try? await process.availableCommands()) ?? session.commands
            session.modelList = (try? await process.availableModels()) ?? session.modelList
        } catch {
            session.error = error.localizedDescription
        }
    }

    private func project(_ id: String) -> Project? {
        projects.first { $0.id == id }
    }

    // MARK: - Talking to omp

    public func send(_ text: String, behavior: String? = nil) async {
        guard let session = active, let process = session.process else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Show the message straight away; omp's own transcript catches up.
        session.blocks.append(.user(id: "local-\(UUID().uuidString)", text: trimmed))
        do {
            try await process.send(trimmed, behavior: behavior)
        } catch {
            banner = error.localizedDescription
        }
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
        guard let session = active, let process = session.process else { return }
        do {
            try await process.setModel(provider: model.provider, modelID: model.id)
            session.model = model
        } catch {
            banner = error.localizedDescription
        }
    }

    public func setThinking(_ level: String) async {
        guard let session = active, let process = session.process else { return }
        do {
            try await process.setThinking(level)
            session.thinkingLevel = level
        } catch {
            banner = error.localizedDescription
        }
    }

    public func answer(_ request: UIRequest, value: String, cancelled: Bool = false) async {
        guard let session = active, let process = session.process else { return }
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
        case "agent_end":
            session.status = .idle
            Task { await self.refresh(id) }
        case "message_start":
            let messageID = frame["messageId"].string
            let role = frame["message"]["role"].string
            if role == "user" {
                let text = History.plainText(frame["message"]["content"])
                if !text.isEmpty { session.blocks.append(.user(id: messageID, text: text)) }
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
            } else if let request = UIRequest(json: frame) {
                session.pendingRequest = request
            }
        case "extension_ui_request_cancelled":
            session.pendingRequest = nil
        case "available_commands_update":
            session.commands = frame["commands"].array.compactMap(SlashCommand.init(json:))
        case "disconnected":
            session.status = .stopped
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

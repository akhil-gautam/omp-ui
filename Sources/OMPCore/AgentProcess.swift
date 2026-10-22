import Foundation

/// One project, and the omp process that works on it.
///
/// The process stays alive for as long as the project is open, so omp keeps
/// its session, its queued messages and any background work between visits.
public actor AgentProcess {
    public typealias FrameHandler = @Sendable (JSONValue) async -> Void

    private let project: Project
    private let executable: String
    /// The environment omp starts with: the reader's shell's, so it sees the
    /// keys and PATH it sees in Terminal.
    private let environment: [String: String]
    private let onFrame: FrameHandler
    private var connection: RPCConnection?

    public init(
        project: Project,
        executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        onFrame: @escaping FrameHandler
    ) {
        self.project = project
        self.executable = executable
        self.environment = environment
        self.onFrame = onFrame
    }

    public var directory: String { project.path }

    // MARK: - Life

    /// Starts omp, optionally resuming a session.
    public func start(resuming session: String? = nil) async throws {
        guard connection == nil else { return }
        let connection = RPCConnection(onEvent: { [onFrame] frame in await onFrame(frame) })
        var arguments = ["--mode", "rpc-ui", "--no-title"]
        if let session { arguments += ["--resume", session] }
        // omp's own tools have to be findable, and they sit next to omp.
        var environment = self.environment
        let directory = (executable as NSString).deletingLastPathComponent
        let path = environment["PATH"] ?? ""
        environment["PATH"] = directory.isEmpty ? path : "\(directory):\(path)"
        try await connection.start(executable: executable, arguments: arguments, directory: project.path, environment: environment)
        self.connection = connection
        // Protocol v2 carries the frames v1 cannot.
        _ = try? await connection.negotiateProtocol()
    }

    public func stop() async {
        let connection = self.connection
        self.connection = nil
        await connection?.close()
    }

    /// Whether omp is up and answering: a connection whose process has exited
    /// does not count.
    public func isRunning() async -> Bool {
        await connection?.isConnected ?? false
    }

    // MARK: - Commands

    /// Sends a message, with any images it carries. While the agent is
    /// working, `behavior` decides whether the message steers the running
    /// turn or waits in the queue.
    ///
    /// Returns whether omp handed it to the agent. A message omp settles
    /// itself — a slash command — starts no turn and gets no `prompt_result`.
    @discardableResult
    public func send(_ text: String, behavior: String? = nil, images: [ImageAttachment] = []) async throws -> Bool {
        let ack = try await call("prompt", Self.prompt(text, behavior: behavior, images: images))
        if case .bool(let invoked) = ack["agentInvoked"] { return invoked }
        return true
    }

    /// The `prompt` command's parameters.
    static func prompt(_ text: String, behavior: String?, images: [ImageAttachment]) -> [String: JSONValue] {
        var payload: [String: JSONValue] = ["message": .string(text)]
        if let behavior { payload["streamingBehavior"] = .string(behavior) }
        if !images.isEmpty { payload["images"] = .array(images.map(\.json)) }
        return payload
    }

    /// Runs a shell command in the project the way omp's own `!command` does:
    /// its output goes into the session, where the agent reads it.
    public func bash(_ command: String) async throws -> BashResult {
        BashResult(json: try await call("bash", ["command": .string(command)], timeout: .seconds(600)))
    }

    public func abort() async throws {
        _ = try await call("abort")
    }

    public func setModel(provider: String, modelID: String) async throws {
        _ = try await call("set_model", ["provider": .string(provider), "modelId": .string(modelID)])
    }

    public func setThinking(_ level: String) async throws {
        _ = try await call("set_thinking_level", ["level": .string(level)])
    }

    /// Applies a session mode to omp.
    ///
    /// The follow-up queue always holds every message, so a second and a third
    /// message are not lost; the modes differ in whether a steer lands on the
    /// running turn.
    public func setMode(_ mode: SessionMode) async throws {
        let steering = mode == .autopilot ? "all" : "one-at-a-time"
        let interrupt = mode == .autopilot ? "wait" : "immediate"
        _ = try await call("set_steering_mode", ["mode": .string(steering)])
        _ = try await call("set_follow_up_mode", ["mode": .string("all")])
        _ = try await call("set_interrupt_mode", ["mode": .string(interrupt)])
    }

    public func state() async throws -> JSONValue {
        try await call("get_state")
    }

    public func availableModels() async throws -> [ModelInfo] {
        // omp may first finish asking providers for their models.
        let response = try await call("get_available_models", timeout: .seconds(180))
        let entries = response["models"].array.isEmpty ? response.array : response["models"].array
        return entries.compactMap(ModelInfo.init(json:))
    }

    public func availableCommands() async throws -> [SlashCommand] {
        let response = try await call("get_available_commands")
        return response["commands"].array.compactMap(SlashCommand.init(json:))
    }

    /// The session's messages, as transcript blocks.
    public func history() async throws -> [Block] {
        let response = try await call("get_messages")
        let messages = response["messages"].array.isEmpty ? response.array : response["messages"].array
        return History.blocks(from: messages)
    }

    public func answer(_ request: UIRequest, value: String, cancelled: Bool = false) async throws {
        var payload = request.answer(value, cancelled: cancelled)
        payload["id"] = .string(request.id)
        _ = try await call("extension_ui_response", payload)
    }

    /// Switches to another of the project's sessions. Returns false when omp
    /// refused: it will not switch to a session recorded in another folder.
    @discardableResult
    public func switchSession(path: String) async throws -> Bool {
        let reply = try await call("switch_session", ["sessionPath": .string(path)])
        return !reply["cancelled"].bool
    }

    /// The providers omp can sign in to, and which it is signed in to.
    public func loginProviders() async throws -> [LoginProvider] {
        try await call("get_login_providers")["providers"].array.compactMap(LoginProvider.init(json:))
    }

    /// Signs in to a provider. omp sends the page to open as it goes, and
    /// answers only once the reader has finished there, so the wait is long.
    public func login(provider: String) async throws {
        _ = try await call("login", ["providerId": .string(provider)], timeout: .seconds(900))
    }

    /// The saved sign-ins for a provider.
    public func loginAccounts(provider: String) async throws -> [LoginAccount] {
        try await call("get_logout_accounts", ["providerId": .string(provider)])["accounts"].array.compactMap(LoginAccount.init(json:))
    }

    /// Removes a saved sign-in.
    public func logout(provider: String, account: Int) async throws {
        _ = try await call("logout", ["providerId": .string(provider), "credentialId": .number(Double(account))])
    }

    public func newSession() async throws {
        _ = try await call("new_session")
    }

    public func compact() async throws {
        _ = try await call("compact")
    }

    /// Removes a message that is waiting in the queue.
    public func removeQueued(_ text: String, queue: String) async throws {
        _ = try await call("remove_queued_message", ["message": .string(text), "queue": .string(queue)])
    }

    private func call(_ type: String, _ payload: [String: JSONValue] = [:], timeout: Duration = .seconds(60)) async throws -> JSONValue {
        guard let connection else { throw RPCError.disconnected("omp is not running for \(project.name).") }
        return try await connection.call(type, payload, timeout: timeout)
    }
}

/// Turning a session's messages into transcript blocks.
public enum History {
    public static func blocks(from messages: [JSONValue]) -> [Block] {
        let recovered = recoveredFailures(in: messages)
        var blocks: [Block] = []
        for (index, message) in messages.enumerated() {
            let role = message["role"].string.isEmpty ? "assistant" : message["role"].string
            switch role {
            case "user", "developer":
                let text = plainText(message["content"])
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.user(id: "m\(index)", text: text))
                }
            case "bashExecution":
                // A command run from the composer's terminal: shown as the
                // card a tool call gets.
                let result = BashResult(json: message)
                blocks.append(.tool(
                    id: "m\(index)", name: "terminal", args: .object(["command": .string(message["command"].string)]),
                    output: result.output, isError: result.failed, running: false
                ))
            case "assistant":
                for (position, item) in message["content"].array.enumerated() {
                    let id = "m\(index)c\(position)"
                    switch item["type"].string {
                    case "text":
                        let text = item["text"].string
                        if !text.isEmpty { blocks.append(.text(id: id, text: text)) }
                    case "thinking":
                        let text = item["thinking"].string
                        if !text.isEmpty { blocks.append(.thinking(id: id, text: text)) }
                    case "toolCall":
                        let name = item["name"].string.isEmpty ? "tool" : item["name"].string
                        let callID = item["id"].optionalString ?? id
                        blocks.append(.tool(id: callID, name: name, args: item["arguments"], output: nil, isError: false, running: false))
                    default:
                        break
                    }
                }
                // A turn the provider refused leaves no content, only the
                // reason; without it the turn would look like silence. One
                // omp recovered from by retrying is not a failure.
                if message["stopReason"].string == "error", !recovered.contains(index) {
                    let reason = message["errorMessage"].string
                    blocks.append(.failure(id: "m\(index)f", text: reason.isEmpty ? "The model returned an error." : reason))
                }
            case "toolResult":
                let callID = message["toolCallId"].string
                let name = message["toolName"].string.isEmpty ? "tool" : message["toolName"].string
                let output = plainText(message["content"])
                let isError = message["isError"].bool
                // Fill in the call the result belongs to; keep it standalone
                // when the call itself was pruned from the transcript.
                if let index = blocks.firstIndex(where: { block in
                    if case .tool(let id, _, _, _, _, _) = block { return id == callID }
                    return false
                }), case .tool(let id, let toolName, let args, _, _, _) = blocks[index] {
                    blocks[index] = .tool(id: id, name: toolName, args: args, output: output, isError: isError, running: false)
                } else {
                    blocks.append(.tool(id: callID, name: name, args: nil, output: output, isError: isError, running: false))
                }
            default:
                break
            }
        }
        return blocks
    }

    /// Whether a message begins a turn: something the reader said.
    private static func beginsTurn(_ message: JSONValue) -> Bool {
        let role = message["role"].string
        guard role == "user" || role == "developer" else { return false }
        return !plainText(message["content"]).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The failed replies that are not how their turn ended: omp retried and
    /// a later reply in the same turn took their place.
    private static func recoveredFailures(in messages: [JSONValue]) -> Set<Int> {
        var recovered: Set<Int> = []
        var laterReply = false
        for (index, message) in messages.enumerated().reversed() {
            if beginsTurn(message) {
                laterReply = false
            } else if message["role"].string == "assistant" {
                if laterReply, message["stopReason"].string == "error" { recovered.insert(index) }
                laterReply = true
            }
        }
        return recovered
    }

    /// A turn that failed, and the message it answered: the failure belongs
    /// at the end of the turn that began with the `turn`-th thing the reader
    /// said, counting from one.
    public struct Failure: Sendable, Equatable {
        public var turn: Int
        public var text: String

        public init(turn: Int, text: String) {
            self.turn = turn
            self.text = text
        }
    }

    /// Why a finished turn failed, read from its `agent_end`: the reason its
    /// last reply gave, if that reply failed. A failure omp retried past is
    /// not how the turn ended.
    ///
    /// omp keeps a failed reply out of the session's messages — the model
    /// never sees it again — so the only place its reason arrives is the
    /// event that ends the turn.
    public static func failureReasons(in agentEnd: JSONValue) -> [String] {
        guard let last = agentEnd["messages"].array.last(where: { $0["role"].string == "assistant" }),
              last["stopReason"].string == "error" else { return [] }
        let reason = last["errorMessage"].string
        return [reason.isEmpty ? "The model returned an error." : reason]
    }

    /// The failures a session file records, numbered by the turns in that
    /// file, and how many turns the file holds.
    ///
    /// omp leaves a failed reply out of the messages it returns for a resumed
    /// session, so after a restart the file is the only place it survives.
    public static func failures(inSessionFile url: URL) -> (failures: [Failure], turns: Int) {
        guard let data = try? Data(contentsOf: url) else { return ([], 0) }
        var failures: [Failure] = []
        var turns = 0
        // The last reply of the turn so far, if it failed; a later reply in
        // the same turn means omp recovered.
        var ending: Failure?
        for line in data.split(separator: 10) {
            guard let entry = try? JSONDecoder().decode(JSONValue.self, from: Data(line)) else { continue }
            let message = entry["message"]
            if beginsTurn(message) {
                if let ending { failures.append(ending) }
                ending = nil
                turns += 1
            } else if message["role"].string == "assistant" {
                if message["stopReason"].string == "error" {
                    let reason = message["errorMessage"].string
                    ending = Failure(turn: turns, text: reason.isEmpty ? "The model returned an error." : reason)
                } else {
                    ending = nil
                }
            }
        }
        if let ending { failures.append(ending) }
        return (failures, turns)
    }

    /// Moves failures numbered by a session file onto the history omp
    /// returned. The two agree at their ends — older turns may have been
    /// compacted away — so the numbering is shifted by the difference.
    public static func align(_ recorded: (failures: [Failure], turns: Int), toHistoryTurns turns: Int) -> [Failure] {
        guard turns > 0 else { return [] }
        let shift = turns - recorded.turns
        return recorded.failures.compactMap { failure in
            let turn = failure.turn + shift
            return (1...turns).contains(turn) ? Failure(turn: turn, text: failure.text) : nil
        }
    }

    /// Puts failures back where they happened, after the turn they ended.
    /// A turn that already shows a failure is left as it is.
    public static func weave(_ failures: [Failure], into blocks: [Block]) -> [Block] {
        guard !failures.isEmpty else { return blocks }
        var result: [Block] = []
        var turn = 0
        var turnHasFailure = false

        func close() {
            guard !turnHasFailure else { return }
            for (position, failure) in failures.enumerated() where failure.turn == turn {
                result.append(.failure(id: "failure-\(turn)-\(position)", text: failure.text))
            }
        }

        for block in blocks {
            if case .user = block {
                close()
                turn += 1
                turnHasFailure = false
            }
            if case .failure = block { turnHasFailure = true }
            result.append(block)
        }
        close()
        return result
    }

    /// The text of a content value, which may be a string or a list of parts.
    public static func plainText(_ value: JSONValue) -> String {
        if case .string(let text) = value { return text }
        return value.array.compactMap { part -> String? in
            switch part["type"].string {
            case "text": return part["text"].string
            case "thinking": return part["thinking"].string
            default: return nil
            }
        }.joined()
    }
}

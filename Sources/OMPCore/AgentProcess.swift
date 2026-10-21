import Foundation

/// One project, and the omp process that works on it.
///
/// The process stays alive for as long as the project is open, so omp keeps
/// its session, its queued messages and any background work between visits.
public actor AgentProcess {
    public typealias FrameHandler = @Sendable (JSONValue) async -> Void

    private let project: Project
    private let executable: String
    private let onFrame: FrameHandler
    private var connection: RPCConnection?

    public init(project: Project, executable: String, onFrame: @escaping FrameHandler) {
        self.project = project
        self.executable = executable
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
        var environment = ProcessInfo.processInfo.environment
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

    public func isRunning() -> Bool { connection != nil }

    // MARK: - Commands

    /// Sends a message. While the agent is working, `behavior` decides whether
    /// the message steers the running turn or waits in the queue.
    public func send(_ text: String, behavior: String? = nil) async throws {
        var payload: [String: JSONValue] = ["message": .string(text)]
        if let behavior { payload["streamingBehavior"] = .string(behavior) }
        _ = try await call("prompt", payload)
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
        let response = try await call("get_available_models")
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

    public func switchSession(path: String) async throws {
        _ = try await call("switch_session", ["sessionPath": .string(path)])
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
        var blocks: [Block] = []
        for (index, message) in messages.enumerated() {
            let role = message["role"].string.isEmpty ? "assistant" : message["role"].string
            switch role {
            case "user", "developer":
                let text = plainText(message["content"])
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    blocks.append(.user(id: "m\(index)", text: text))
                }
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

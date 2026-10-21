@preconcurrency import Foundation
import Darwin

/// A client for omp's RPC protocol: newline-delimited JSON over stdio.
///
/// The server answers each command with a response frame carrying the same
/// id, and pushes everything else — status changes, message deltas, tool
/// calls, queue updates — as events. Protocol v2 splits oversized frames
/// into chunks, which are reassembled here.
public actor RPCConnection {
    public typealias EventHandler = @Sendable (JSONValue) async -> Void

    private struct Pending {
        let continuation: CheckedContinuation<JSONValue, any Error>
        let deadline: Task<Void, Never>?
    }

    /// A frame that arrived in pieces.
    private struct Assembly {
        var parts: [Int: Data] = [:]
        var count: Int = 0
        var length: Int = 0
    }

    private var process: Process?
    private var writer: PipeWriter?
    private var processGroup: pid_t?
    private var nextID = 0
    private var pending: [String: Pending] = [:]
    private var framer = LineFramer()
    private var assemblies: [String: Assembly] = [:]
    private var onEvent: EventHandler?
    private var stderr = Data()
    private var didDisconnect = false
    private var ready: JSONValue = .null
    private var readyWaiter: CheckedContinuation<Void, any Error>?

    public init(onEvent: @escaping EventHandler) {
        self.onEvent = onEvent
    }

    /// The server's ready frame, once it has arrived.
    public var serverReady: JSONValue { ready }

    public func hasPendingRequest(_ id: String) -> Bool { pending[id] != nil }

    // MARK: - Starting

    public func start(executable: String, arguments: [String], directory: String, environment: [String: String]? = nil) throws {
        try Task.checkCancellation()
        guard !didDisconnect else { throw RPCError.disconnected("The connection is closed.") }
        guard process == nil else { throw RPCError.protocolViolation("The connection is already started.") }

        let child = Process(), stdin = Pipe(), stdout = Pipe(), errors = Pipe()
        child.executableURL = URL(fileURLWithPath: executable)
        child.arguments = arguments
        child.currentDirectoryURL = URL(fileURLWithPath: directory)
        child.environment = environment ?? ProcessInfo.processInfo.environment
        child.standardInput = stdin
        child.standardOutput = stdout
        child.standardError = errors

        let pipeWriter = try PipeWriter(stdin.fileHandleForWriting)
        try child.run()
        process = child
        processGroup = ownedProcessGroup(child)
        writer = pipeWriter

        let out = stdout.fileHandleForReading, err = errors.fileHandleForReading
        // Blocking reads live on dedicated queues, never on the UI or the
        // Swift cooperative executor.
        DispatchQueue(label: "omp-ui.rpc.stdout.\(child.processIdentifier)").async { [weak self] in
            let bridge = DispatchSemaphore(value: 0)
            var remainingAfterExit: Int?
            do {
                while true {
                    let data = try readPipe(out, untilExit: child, remainingAfterExit: &remainingAfterExit)
                    if data.isEmpty { break }
                    Task { [weak self] in await self?.receive(data); bridge.signal() }
                    bridge.wait()
                }
                Task { [weak self] in await self?.end("omp closed its output.") }
            } catch {
                Task { [weak self] in await self?.end("omp output failed: \(error.localizedDescription)") }
            }
            try? out.close()
        }
        DispatchQueue(label: "omp-ui.rpc.stderr.\(child.processIdentifier)").async { [weak self] in
            let bridge = DispatchSemaphore(value: 0)
            var remainingAfterExit: Int?
            while let data = try? readPipe(err, untilExit: child, remainingAfterExit: &remainingAfterExit), !data.isEmpty {
                Task { [weak self] in await self?.log(data); bridge.signal() }
                bridge.wait()
            }
            try? err.close()
        }
    }

    /// Waits for the server's ready frame.
    public func waitForReady(timeout: Duration = .seconds(15)) async throws {
        if ready["type"].string == "ready" { return }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            readyWaiter = continuation
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                await self?.failReady(RPCError.timeout("omp did not announce itself in time."))
            }
        }
    }

    private func failReady(_ error: any Error) {
        guard let waiter = readyWaiter else { return }
        readyWaiter = nil
        waiter.resume(throwing: error)
    }

    /// Asks for protocol v2, which can carry frames the v1 ceiling cannot.
    ///
    /// The server answers with the version it settled on.
    public func negotiateProtocol() async throws -> Int {
        try await waitForReady()
        let supported = ready["supportedProtocolVersions"].array.compactMap(\.exactInteger)
        guard supported.contains(2) else { return 1 }
        let response = try await call("negotiate_protocol", ["protocolVersion": .number(2)], timeout: .seconds(10))
        return response["data"]["protocolVersion"].exactInteger ?? 2
    }

    // MARK: - Calling

    /// Sends a command and waits for its response.
    public func call(_ type: String, _ payload: [String: JSONValue] = [:], timeout: Duration? = .seconds(60)) async throws -> JSONValue {
        try Task.checkCancellation()
        guard writer != nil, !didDisconnect else { throw RPCError.disconnected("omp is not running.") }
        nextID += 1
        let id = "req_\(nextID)"
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let deadline: Task<Void, Never>? = timeout.map { duration in
                    Task { [weak self] in
                        do { try await Task.sleep(for: duration) } catch { return }
                        await self?.fail(id, error: RPCError.timeout("omp did not answer \(type) in time."))
                    }
                }
                pending[id] = Pending(continuation: continuation, deadline: deadline)
                do {
                    var message = payload
                    message["id"] = .string(id)
                    message["type"] = .string(type)
                    try write(message)
                } catch {
                    fail(id, error: error)
                }
            }
        } onCancel: {
            Task { await self.fail(id, error: CancellationError()) }
        }
    }

    public func close() async {
        await end("The connection was closed.", report: false)
    }

    /// Whatever omp wrote to stderr, for diagnostics.
    public func diagnostics() -> String { String(decoding: stderr, as: UTF8.self) }

    // MARK: - The wire

    private func write(_ message: [String: JSONValue]) throws {
        guard let writer, !didDisconnect else { throw RPCError.disconnected("omp is not running.") }
        var bytes = try JSONEncoder().encode(JSONValue.object(message))
        bytes.append(10)
        try writer.enqueue(bytes) { [weak self] result in
            if case .failure(let error) = result {
                Task { [weak self] in await self?.end("omp input failed: \(error.localizedDescription)") }
            }
        }
    }

    private func receive(_ data: Data) async {
        do {
            for line in try framer.append(data) {
                guard let frame = try? JSONDecoder().decode(JSONValue.self, from: line) else { continue }
                await handle(frame)
            }
        } catch {
            await end("omp sent a frame the app could not read: \(error.localizedDescription)")
        }
    }

    private func handle(_ frame: JSONValue) async {
        // A chunked frame: collect the parts and carry on.
        if frame["type"].string == "rpc_chunk" {
            guard let chunkID = frame["chunkId"].optionalString else { return }
            let index = frame["index"].exactInteger ?? 0
            let count = frame["count"].exactInteger ?? 0
            let data = Data(base64Encoded: frame["data"].string) ?? Data()
            var assembly = assemblies[chunkID] ?? Assembly()
            assembly.parts[index] = data
            assembly.count = count
            assembly.length += data.count
            assemblies[chunkID] = assembly
            guard assembly.parts.count == count else { return }
            assemblies.removeValue(forKey: chunkID)
            var whole = Data()
            for position in 0..<count { whole.append(assembly.parts[position] ?? Data()) }
            guard let decoded = try? JSONDecoder().decode(JSONValue.self, from: whole) else { return }
            await handle(decoded)
            return
        }

        if frame["type"].string == "ready" {
            ready = frame
            readyWaiter?.resume()
            readyWaiter = nil
            return
        }

        // A response to one of our commands.
        if frame["type"].string == "response", let id = frame["id"].optionalString {
            if frame["success"].bool {
                succeed(id, with: frame["data"])
            } else {
                let message = frame["error"].string.isEmpty ? "omp refused the command." : frame["error"].string
                fail(id, error: RPCError.remote(message))
            }
            return
        }

        // Everything else is an event.
        await onEvent?(frame)
    }

    // MARK: - Pending commands

    private func succeed(_ id: String, with data: JSONValue) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.deadline?.cancel()
        entry.continuation.resume(returning: data)
    }

    private func fail(_ id: String, error: any Error) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.deadline?.cancel()
        entry.continuation.resume(throwing: error)
    }

    private func log(_ data: Data) {
        stderr.append(data)
        if stderr.count > 256 * 1024 { stderr.removeFirst(stderr.count - 256 * 1024) }
    }

    private func end(_ reason: String, report: Bool = true) async {
        guard !didDisconnect else { return }
        didDisconnect = true
        writer?.close()
        writer = nil
        // The process goes with the connection: a child left running would
        // keep its session, and its memory, alive.
        if let process, process.isRunning {
            let group = processGroup
            if let group { Darwin.kill(-group, SIGTERM) } else { process.terminate() }
        }
        process = nil
        processGroup = nil
        for entry in pending.values {
            entry.deadline?.cancel()
            entry.continuation.resume(throwing: RPCError.disconnected(reason))
        }
        pending.removeAll()
        failReady(RPCError.disconnected(reason))
        if report {
            await onEvent?(["type": "disconnected", "reason": .string(reason)])
        }
    }
}

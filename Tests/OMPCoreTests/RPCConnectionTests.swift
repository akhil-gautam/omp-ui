import Foundation
import Testing
@testable import OMPCore

/// A stand-in for omp: it answers commands and pushes an event.
private func makeServer() throws -> URL {
    let script = """
    import json, sys
    print(json.dumps({"type": "ready", "protocolVersion": 1, "supportedProtocolVersions": [1, 2], "maxFrameBytes": 1048576}), flush=True)
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            message = json.loads(line)
        except Exception:
            continue
        kind = message.get("type")
        if kind == "negotiate_protocol":
            answer = {"protocolVersion": 2}
        elif kind == "get_state":
            answer = {"sessionId": "s1", "tokensPerSecond": None}
        elif kind == "boom":
            print(json.dumps({"id": message["id"], "type": "response", "command": "boom", "success": False, "error": "no such thing"}), flush=True)
            continue
        else:
            answer = {"ok": True}
        print(json.dumps({"id": message["id"], "type": "response", "command": kind, "success": True, "data": answer}), flush=True)
        print(json.dumps({"type": "notice", "message": "hello"}), flush=True)
    """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-fake-\(UUID().uuidString).py")
    try script.write(to: url, atomically: true, encoding: .utf8)
    return url
}

@Suite("The protocol client")
struct RPCConnectionTests {
    @Test("a command is answered with its data")
    func answersCommands() async throws {
        let server = try makeServer()
        defer { try? FileManager.default.removeItem(at: server) }

        let connection = RPCConnection(onEvent: { _ in })
        try await connection.start(executable: "/usr/bin/python3", arguments: [server.path], directory: NSTemporaryDirectory())

        let state = try await connection.call("get_state")
        await connection.close()
        #expect(state["sessionId"].string == "s1")
        #expect(state["tokensPerSecond"].isNull)
    }

    @Test("a refused command throws")
    func refusesCommands() async throws {
        let server = try makeServer()
        defer { try? FileManager.default.removeItem(at: server) }

        let connection = RPCConnection(onEvent: { _ in })
        try await connection.start(executable: "/usr/bin/python3", arguments: [server.path], directory: NSTemporaryDirectory())

        await #expect(throws: RPCError.self) {
            _ = try await connection.call("boom")
        }
        await connection.close()
    }

    @Test("the events the server pushes are delivered")
    func deliversEvents() async throws {
        let server = try makeServer()
        defer { try? FileManager.default.removeItem(at: server) }

        let received = Received()
        let connection = RPCConnection(onEvent: { frame in
            if frame["type"].string == "notice" { await received.add(frame["message"].string) }
        })
        try await connection.start(executable: "/usr/bin/python3", arguments: [server.path], directory: NSTemporaryDirectory())

        _ = try await connection.call("get_state")
        // The event follows the response; give it a moment to arrive.
        try await Task.sleep(for: .milliseconds(200))
        await connection.close()
        #expect(await received.messages.contains("hello"))
    }

    @Test("the protocol is negotiated before the first command")
    func negotiatesTheProtocol() async throws {
        let server = try makeServer()
        defer { try? FileManager.default.removeItem(at: server) }

        let connection = RPCConnection(onEvent: { _ in })
        try await connection.start(executable: "/usr/bin/python3", arguments: [server.path], directory: NSTemporaryDirectory())

        let version = try await connection.negotiateProtocol()
        await connection.close()
        #expect(version == 2)
    }
}

/// A place to collect the events, from the client's own task.
private actor Received {
    var messages: [String] = []

    func add(_ message: String) {
        messages.append(message)
    }
}

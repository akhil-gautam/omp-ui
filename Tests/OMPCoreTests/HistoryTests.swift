import Foundation
import Testing
@testable import OMPCore

@Suite("Reading a session's history")
struct HistoryTests {
    @Test("a turn the provider refused says why")
    func aFailedTurnSaysWhy() {
        let blocks = History.blocks(from: [
            .object(["role": .string("user"), "content": .string("why is it failing?")]),
            .object([
                "role": .string("assistant"),
                "content": .array([]),
                "stopReason": .string("error"),
                "errorMessage": .string("402 This request requires more credits"),
            ]),
        ])
        #expect(blocks.count == 2)
        guard case .failure(_, let text) = blocks.last else {
            Issue.record("the failed turn left no block: \(blocks)")
            return
        }
        #expect(text == "402 This request requires more credits")
    }

    @Test("a turn the reader stopped is not a failure")
    func anInterruptedTurnIsNotAFailure() {
        let blocks = History.blocks(from: [
            .object([
                "role": .string("assistant"),
                "content": .array([.object(["type": .string("text"), "text": .string("Half an answer")])]),
                "stopReason": .string("aborted"),
                "errorMessage": .string("Interrupted by user"),
            ]),
        ])
        #expect(blocks.count == 1)
        if case .failure = blocks.first { Issue.record("an interruption was shown as a failure") }
    }

    @Test("a failure goes at the end of the turn it ended")
    func failuresGoAtTheEndOfTheirTurn() {
        let blocks: [Block] = [
            .user(id: "u1", text: "first"),
            .text(id: "t1", text: "an answer"),
            .user(id: "u2", text: "second"),
        ]
        let first = History.weave([History.Failure(turn: 1, text: "402")], into: blocks)
        #expect(first.map(\.id) == ["u1", "t1", "failure-1-0", "u2"])

        let last = History.weave([History.Failure(turn: 2, text: "402")], into: blocks)
        #expect(last.map(\.id) == ["u1", "t1", "u2", "failure-2-0"])
    }

    @Test("a turn that already shows its failure is not given a second one")
    func aFailureIsNotRepeated() {
        let blocks: [Block] = [
            .user(id: "u1", text: "first"),
            .failure(id: "m1f", text: "402"),
        ]
        let woven = History.weave([History.Failure(turn: 1, text: "402")], into: blocks)
        #expect(woven.map(\.id) == ["u1", "m1f"])
    }

    @Test("the reason comes from the turn's end, not from its successes")
    func reasonsComeFromTheEnd() {
        let end: JSONValue = .object(["messages": .array([
            .object(["role": .string("user"), "content": .string("hi")]),
            .object(["role": .string("assistant"), "stopReason": .string("stop"), "content": .array([])]),
            .object(["role": .string("assistant"), "stopReason": .string("error"), "errorMessage": .string("402 more credits")]),
        ])])
        #expect(History.failureReasons(in: end) == ["402 more credits"])
    }

    /// A dropped connection omp retried past, as i-shares recorded it.
    private let dropped: JSONValue = .object([
        "role": .string("assistant"), "content": .array([]), "stopReason": .string("error"),
        "errorMessage": .string("The socket connection was closed unexpectedly before the response completed"),
    ])
    private let answered: JSONValue = .object([
        "role": .string("assistant"), "stopReason": .string("stop"),
        "content": .array([.object(["type": .string("text"), "text": .string("Done.")])]),
    ])

    @Test("a failure omp retried past is not how the turn ended")
    func aRecoveredFailureIsNotShown() {
        let ask: JSONValue = .object(["role": .string("user"), "content": .string("fix it")])
        let blocks = History.blocks(from: [ask, dropped, answered])
        #expect(!blocks.contains { if case .failure = $0 { true } else { false } })
        #expect(History.failureReasons(in: .object(["messages": .array([ask, dropped, answered])])).isEmpty)
        // Retries that all failed show the last reason once.
        let refused: JSONValue = .object(["role": .string("assistant"), "stopReason": .string("error"), "errorMessage": .string("402")])
        let failures = History.blocks(from: [ask, dropped, refused]).filter { if case .failure = $0 { true } else { false } }
        #expect(failures.map(\.text) == ["402"])
    }

    @Test("a session file's recovered failure is not read back")
    func aRecoveredFailureIsNotRecorded() throws {
        let lines = [
            #"{"type":"message","message":{"role":"user","content":"fix it"}}"#,
            #"{"type":"message","message":{"role":"assistant","content":[],"stopReason":"error","errorMessage":"The socket connection was closed"}}"#,
            #"{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"Done."}],"stopReason":"stop"}}"#,
            #"{"type":"message","message":{"role":"user","content":"and again"}}"#,
            #"{"type":"message","message":{"role":"assistant","content":[],"stopReason":"error","errorMessage":"402 more credits"}}"#,
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-session-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorded = History.failures(inSessionFile: url)
        #expect(recorded.failures == [History.Failure(turn: 2, text: "402 more credits")])
    }

    @Test("a resumed session's failures are read from its file")
    func failuresSurviveARestart() throws {
        let lines = [
            #"{"type":"session","id":"s1"}"#,
            #"{"type":"message","message":{"role":"user","content":"first"}}"#,
            #"{"type":"message","message":{"role":"assistant","content":[{"type":"text","text":"fine"}],"stopReason":"stop"}}"#,
            #"{"type":"message","message":{"role":"user","content":"why is it failing?"}}"#,
            #"{"type":"message","message":{"role":"assistant","content":[],"stopReason":"error","errorMessage":"402 more credits"}}"#,
        ]
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("omp-ui-session-\(UUID().uuidString).jsonl")
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let recorded = History.failures(inSessionFile: url)
        #expect(recorded.turns == 2)
        #expect(recorded.failures == [History.Failure(turn: 2, text: "402 more credits")])
    }

    @Test("failures are lined up with the history from its end")
    func alignmentKeepsTheEnd() {
        let recorded = (failures: [History.Failure(turn: 2, text: "old"), History.Failure(turn: 5, text: "new")], turns: 5)
        // Three turns were compacted away: the history holds the last two.
        #expect(History.align(recorded, toHistoryTurns: 2) == [History.Failure(turn: 2, text: "new")])
        // Nothing compacted: the numbering stands.
        #expect(History.align(recorded, toHistoryTurns: 5).map(\.turn) == [2, 5])
        #expect(History.align(recorded, toHistoryTurns: 0).isEmpty)
    }
}

import Testing
@testable import OMPCore

@Suite("A sent message and omp's echo of it")
struct TranscriptTests {
    private let shown = Transcript.shownPrefix

    @Test("the echo takes over the copy already shown")
    func echoReplacesTheShownCopy() {
        var blocks: [Block] = [.text(id: "a", text: "done"), .user(id: "\(shown)1", text: "continue")]
        Transcript.receive(userMessage: "m7", text: "continue", into: &blocks)
        #expect(blocks == [.text(id: "a", text: "done"), .user(id: "m7", text: "continue")])
    }

    @Test("an echo omp changed takes over the oldest message still waiting")
    func anExpandedCommandStillReplaces() {
        var blocks: [Block] = [.user(id: "\(shown)1", text: "/review"), .user(id: "\(shown)2", text: "and the tests")]
        Transcript.receive(userMessage: "m1", text: "Review the staged changes…", into: &blocks)
        #expect(blocks.map(\.id) == ["m1", "\(shown)2"])
        #expect(blocks[0].text == "Review the staged changes…")
    }

    @Test("the same text sent twice is echoed into each copy in turn")
    func repeatedTextKeepsBoth() {
        var blocks: [Block] = [.user(id: "\(shown)1", text: "continue"), .user(id: "\(shown)2", text: "continue")]
        Transcript.receive(userMessage: "m1", text: "continue", into: &blocks)
        Transcript.receive(userMessage: "m2", text: "continue", into: &blocks)
        #expect(blocks.map(\.id) == ["m1", "m2"])
    }

    @Test("a message the app did not send is added, and only once")
    func anUnsentMessageIsAddedOnce() {
        var blocks: [Block] = [.text(id: "a", text: "done")]
        Transcript.receive(userMessage: "m3", text: "from another client", into: &blocks)
        Transcript.receive(userMessage: "m3", text: "from another client", into: &blocks)
        #expect(blocks.map(\.id) == ["a", "m3"])
    }
}

import Foundation
import Testing
@testable import OMPCore

@Suite("The difference between two texts")
struct DiffTests {
    @Test("one changed line")
    func oneLine() {
        let lines = Diff.lines(from: "a\nb\nc", to: "a\nB\nc")
        #expect(lines.count == 4)
        #expect(lines[0] == .context("a"))
        #expect(lines[1] == .removed("b"))
        #expect(lines[1].marker == "-")
        #expect(lines[2] == .added("B"))
        #expect(lines[2].marker == "+")
        #expect(lines[3] == .context("c"))
    }

    @Test("a change in the middle")
    func middle() {
        let lines = Diff.lines(from: "a\nb\nc", to: "a\nx\ny\nc")
        #expect(lines.contains(.removed("b")))
        #expect(lines.contains(.added("x")))
        #expect(lines.contains(.added("y")))
        #expect(lines.contains(.context("c")))
    }

    @Test("no change at all")
    func unchanged() {
        let lines = Diff.lines(from: "a\nb", to: "a\nb")
        #expect(lines == [.context("a"), .context("b")])
    }
}

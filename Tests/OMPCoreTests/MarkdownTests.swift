import Foundation
import Testing
@testable import OMPCore

@Suite("The markdown reader")
struct MarkdownTests {
    @Test("a heading, a paragraph and a rule")
    func blocks() {
        let blocks = Markdown.blocks(of: "# Title\n\nSome words.\n\n---")
        #expect(blocks.count == 3)
        if case .heading(_, let level, let text) = blocks[0] {
            #expect(level == 1)
            #expect(text == "Title")
        } else {
            Issue.record("the first block should be a heading")
        }
        if case .paragraph(_, let text) = blocks[1] {
            #expect(text == "Some words.")
        } else {
            Issue.record("the second block should be a paragraph")
        }
    }

    @Test("a fenced block keeps its language and its text")
    func code() {
        let blocks = Markdown.blocks(of: "```swift\nlet x = 1\n```")
        #expect(blocks.count == 1)
        if case .code(_, let language, let text) = blocks[0] {
            #expect(language == "swift")
            #expect(text == "let x = 1")
        } else {
            Issue.record("the block should be code")
        }
    }

    @Test("a list is read as entries")
    func list() {
        let blocks = Markdown.blocks(of: "- one\n- two")
        #expect(blocks.count == 1)
        if case .list(_, let ordered, let items) = blocks[0] {
            #expect(!ordered)
            #expect(items.count == 2)
            #expect(items[0].text == "one")
        } else {
            Issue.record("the block should be a list")
        }
    }

    @Test("a task list marks what is done")
    func taskList() {
        let blocks = Markdown.blocks(of: "- [x] done\n- [ ] not done")
        if case .list(_, _, let items) = blocks[0] {
            #expect(items[0].checked == true)
            #expect(items[1].checked == false)
        } else {
            Issue.record("the block should be a list")
        }
    }

    @Test("a table keeps its header and its rows")
    func table() {
        let blocks = Markdown.blocks(of: "| a | b |\n| --- | --- |\n| 1 | 2 |")
        #expect(blocks.count == 1)
        if case .table(_, let header, let rows) = blocks[0] {
            #expect(header == ["a", "b"])
            #expect(rows.count == 1)
            #expect(rows[0] == ["1", "2"])
        } else {
            Issue.record("the block should be a table")
        }
    }

    @Test("inline styling is read")
    func inline() {
        let text = Markdown.inline("**bold** and `code`")
        #expect(text.characters.count > 0)
        #expect(String(text.characters).contains("bold"))
    }
}

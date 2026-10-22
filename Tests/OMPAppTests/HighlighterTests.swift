import SwiftUI
import Testing
@testable import OMPApp

@Suite("The highlighter")
struct HighlighterTests {
    private let palette = Theme.palettes[0].code

    /// The colour of the run that holds the given text.
    private func colour(of needle: String, in result: AttributedString) -> Color? {
        for run in result.runs {
            let text = String(result[run.range].characters)
            if text.contains(needle) { return run.attributes.foregroundColor }
        }
        return nil
    }

    @Test("the code is left exactly as it was")
    func theCodeIsUnchanged() {
        let code = """
        func compute(_ values: [Int]) -> Int {
            // sum them
            var total = 0
            for value in values {
                total += value * 2
            }
            return total
        }
        """
        let result = Highlighter.attributed(code, language: "swift", palette: palette)
        #expect(String(result.characters) == code)
    }

    @Test("keywords, strings, numbers and comments each take their colour")
    func eachPieceTakesItsColour() {
        let result = Highlighter.attributed(
            "let name = \"world\" // a note\nlet count = 42",
            language: "swift",
            palette: palette
        )
        #expect(colour(of: "let", in: result) == palette.keyword)
        #expect(colour(of: "\"world\"", in: result) == palette.string)
        #expect(colour(of: "42", in: result) == palette.number)
        #expect(colour(of: "// a note", in: result) == palette.comment)
    }

    @Test("a call is coloured as a function and a name as a type")
    func callsAndTypes() {
        let result = Highlighter.attributed("func run() { let count = total() }", language: "swift", palette: palette)
        #expect(colour(of: "func", in: result) == palette.keyword)
        #expect(colour(of: "run", in: result) == palette.function)
        #expect(colour(of: "total", in: result) == palette.function)
    }

    @Test("each block comment is a comment of its own")
    func blockComments() {
        let result = Highlighter.attributed(
            "/* one */\nlet x = 1\n/* two */\nlet y = 2",
            language: "swift",
            palette: palette
        )
        #expect(colour(of: "/* one */", in: result) == palette.comment)
        #expect(colour(of: "/* two */", in: result) == palette.comment)
        #expect(colour(of: "let", in: result) == palette.keyword)
    }

    @Test("a long file is coloured in one pass")
    func aLongFileIsFast() {
        let code = String(repeating: "func compute(_ values: [Int]) -> Int { return values.count } // note\n", count: 500)
        let start = ContinuousClock.now
        let result = Highlighter.attributed(code, language: "swift", palette: palette)
        let elapsed = start.duration(to: .now)
        #expect(String(result.characters) == code)
        // A scanner that copies as it goes would take seconds here.
        #expect(elapsed < .milliseconds(400), "colouring 500 lines took \(elapsed)")
    }
}

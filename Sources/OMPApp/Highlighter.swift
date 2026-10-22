import Foundation
import SwiftUI

/// Colouring a block of code.
///
/// A scanner rather than a grammar: comments, strings, numbers and words,
/// with the words coloured when the language says they are keywords. It is
/// small, has no dependencies, and does not recurse.
public enum Highlighter {
    public struct CodePalette: Sendable, Hashable {
        public var plain: Color
        public var keyword: Color
        public var string: Color
        public var number: Color
        public var comment: Color
        public var type: Color
        public var function: Color

        public init(plain: Color, keyword: Color, string: Color, number: Color, comment: Color, type: Color, function: Color) {
            self.plain = plain
            self.keyword = keyword
            self.string = string
            self.number = number
            self.comment = comment
            self.type = type
            self.function = function
        }
    }

    /// Colours a piece of code.
    ///
    /// The code is scanned once, from left to right, and the coloured pieces
    /// are collected as ranges. Nothing is copied while scanning, so the
    /// cost is the length of the code and not its square.
    public static func attributed(_ code: String, language: String?, palette: CodePalette) -> AttributedString {
        let characters = Array(code)
        guard !characters.isEmpty else { return AttributedString() }
        let keywords = keywordSet(for: language)
        let types = typeSet(for: language)
        let lineComment = language.map(commentPrefix(for:)) ?? "//"
        let blockComments = language.map { $0 == "swift" || $0 == "rust" || $0 == "c" || $0 == "cpp" || $0 == "go" || $0 == "java" || $0 == "js" || $0 == "ts" } ?? false

        // The coloured pieces, in order.
        var pieces: [(start: Int, end: Int, colour: Color?)] = []
        var index = 0

        while index < characters.count {
            // A block comment.
            if blockComments, characters[index] == "/", index + 1 < characters.count, characters[index + 1] == "*" {
                let close = characters[index...].firstIndex(of: "*") == nil
                    ? characters.count
                    : index + 2 + characters[(index + 2)...].firstIndex(of: "*")!
                let end = min(close + 1, characters.count)
                pieces.append((index, end, palette.comment))
                index = end
                continue
            }

            // A line comment.
            if matches(characters, at: index, lineComment) {
                var end = index
                while end < characters.count, characters[end] != "\n" { end += 1 }
                pieces.append((index, end, palette.comment))
                index = end
                continue
            }

            let character = characters[index]

            // A string.
            if character == "\"" || character == "'" || character == "`" {
                let end = stringEnd(characters, from: index, quote: character)
                pieces.append((index, end, palette.string))
                index = end
                continue
            }

            // A number.
            if character.isNumber {
                var end = index
                while end < characters.count {
                    let next = characters[end]
                    if next.isNumber || next == "." || next == "_" {
                        end += 1
                    } else if next.isHexDigit, end - index < 2 {
                        end += 1
                    } else {
                        break
                    }
                }
                let stop = max(end, index + 1)
                pieces.append((index, stop, palette.number))
                index = stop
                continue
            }

            // A word.
            if character.isLetter || character == "_" {
                var end = index
                while end < characters.count {
                    let next = characters[end]
                    if next.isLetter || next.isNumber || next == "_" { end += 1 } else { break }
                }
                let word = String(characters[index..<end])
                let following = end < characters.count ? characters[end] : nil
                let colour: Color
                if keywords.contains(word) {
                    colour = palette.keyword
                } else if types.contains(word) || (word.first?.isUppercase == true && word.count > 1) {
                    colour = palette.type
                } else if following == "(" {
                    colour = palette.function
                } else {
                    colour = palette.plain
                }
                pieces.append((index, end, colour))
                index = end
                continue
            }

            index += 1
        }
        return assemble(characters, pieces)
    }

    /// Whether the text at that place starts with the given marker.
    private static func matches(_ characters: [Character], at index: Int, _ marker: String) -> Bool {
        let marker = Array(marker)
        guard index + marker.count <= characters.count else { return false }
        for offset in 0..<marker.count where characters[index + offset] != marker[offset] {
            return false
        }
        return true
    }

    /// The end of a string literal, its quotes included.
    private static func stringEnd(_ characters: [Character], from start: Int, quote: Character) -> Int {
        var index = start + 1
        var escaped = false
        while index < characters.count {
            let character = characters[index]
            if escaped {
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == quote || character == "\n" {
                return index + 1
            }
            index += 1
        }
        return characters.count
    }

    /// Joins the pieces back into one attributed string.
    ///
    /// The string is made once and the pieces are coloured in place. The
    /// index walks forward a character at a time, so the cost is the length
    /// of the code.
    private static func assemble(_ characters: [Character], _ pieces: [(start: Int, end: Int, colour: Color?)]) -> AttributedString {
        var result = AttributedString(String(characters))
        var index = result.startIndex
        var cursor = 0
        for piece in pieces {
            while cursor < piece.start {
                index = result.index(afterCharacter: index)
                cursor += 1
            }
            var end = index
            for _ in piece.start..<piece.end {
                end = result.index(afterCharacter: end)
            }
            if let colour = piece.colour {
                result[index..<end].foregroundColor = colour
            }
            index = end
            cursor = piece.end
        }
        return result
    }

    // MARK: - Pieces

    private static func commentPrefix(for language: String) -> String {
        switch language {
        case "python", "ruby", "shell", "bash", "sh", "yaml", "toml": "#"
        case "sql", "lua", "haskell": "--"
        default: "//"
        }
    }

    /// The keywords of each language, kept so the sets are built once.
    private static let keywordSets: [String: Set<String>] = [
        "swift": ["actor", "as", "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "nil", "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while"],
        "rust": ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"],
        "python": ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"],
        "go": ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var"],
        "json": ["true", "false", "null"],
        "sql": ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table", "join", "left", "right", "inner", "outer", "on", "group", "by", "order", "having", "limit", "as", "and", "or", "not", "null"],
        "shell": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "return", "export", "local", "echo", "cd", "set", "unset"],
        "bash": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "return", "export", "local", "echo", "cd", "set", "unset"],
        "sh": ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "return", "export", "local", "echo", "cd", "set", "unset"],
        "typescript": ["abstract", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly", "return", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield"],
        "ts": ["abstract", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly", "return", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield"],
        "tsx": ["abstract", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly", "return", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield"],
        "javascript": ["abstract", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly", "return", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield"],
        "js": ["abstract", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly", "return", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield"],
        "jsx": ["abstract", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly", "return", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield"],
    ]

    /// The keywords of a language it does not know.
    private static let defaultKeywords: Set<String> = ["if", "else", "for", "while", "return", "break", "continue", "switch", "case", "default", "func", "function", "class", "struct", "enum", "import", "export", "const", "let", "var", "true", "false", "null", "nil", "none", "def", "lambda", "async", "await", "public", "private", "static", "new", "try", "catch", "throw"]

    /// The types of each language, kept so the sets are built once.
    private static let typeSets: [String: Set<String>] = [
        "swift": ["String", "Int", "Bool", "Double", "Float", "Character", "Array", "Dictionary", "Set", "Optional", "Result", "Void", "Any", "Self", "Date", "URL", "Data", "UUID"],
        "rust": ["String", "str", "Vec", "Option", "Result", "Box", "HashMap", "HashSet", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "usize", "isize", "f32", "f64", "bool", "char"],
    ]

    private static func keywordSet(for language: String?) -> Set<String> {
        guard let language else { return defaultKeywords }
        return keywordSets[language] ?? defaultKeywords
    }

    private static func typeSet(for language: String?) -> Set<String> {
        guard let language else { return [] }
        return typeSets[language] ?? []
    }
}

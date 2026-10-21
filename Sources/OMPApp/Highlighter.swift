import Foundation
import SwiftUI

/// Colouring a block of code.
///
/// A scanner rather than a grammar: comments, strings, numbers and words,
/// with the words coloured when the language says they are keywords. It is
/// small, has no dependencies, and does not recurse.
public enum Highlighter {
    public struct CodePalette: Sendable {
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

    /// The colours the interface uses for code.
    public static let darkPalette = CodePalette(
        plain: Color(hex: 0xD6D6DA),
        keyword: Color(hex: 0xED4FA6),
        string: Color(hex: 0x9BD48A),
        number: Color(hex: 0xE8B473),
        comment: Color(hex: 0x5A5A62),
        type: Color(hex: 0x74B8E8),
        function: Color(hex: 0xE5C07B)
    )

    /// Colours a piece of code.
    public static func attributed(_ code: String, language: String?, palette: CodePalette) -> AttributedString {
        var result = AttributedString(code)
        let keywords = keywordSet(for: language)
        let types = typeSet(for: language)
        let lineComment = language.map(commentPrefix(for:)) ?? "//"

        var index = result.startIndex
        let characters = Array(code)
        var offset = 0
        var inBlockComment = false
        let blockComments = language.map { $0 == "swift" || $0 == "rust" || $0 == "c" || $0 == "cpp" || $0 == "go" || $0 == "java" || $0 == "js" || $0 == "ts" } ?? false

        while offset < characters.count {
            if inBlockComment {
                let rest = String(characters[offset...])
                guard let end = rest.range(of: "*/") else { break }
                let length = rest.distance(from: rest.startIndex, to: end.lowerBound) + 2
                apply(&result, text: code, from: offset, length: length, colour: palette.comment)
                offset += length
                inBlockComment = false
                continue
            }

            let rest = String(characters[offset...])

            // A block comment.
            if blockComments, rest.hasPrefix("/*") {
                guard let end = rest.range(of: "*/") else {
                    apply(&result, text: code, from: offset, length: rest.count, colour: palette.comment)
                    break
                }
                let length = rest.distance(from: rest.startIndex, to: end.upperBound)
                apply(&result, text: code, from: offset, length: length, colour: palette.comment)
                offset += length
                inBlockComment = true
                continue
            }

            // A line comment.
            if rest.hasPrefix(lineComment) {
                let length = rest.prefix { $0 != "\n" }.count
                apply(&result, text: code, from: offset, length: length, colour: palette.comment)
                offset += length
                continue
            }

            // A string.
            if let quote = rest.first, quote == "\"" || quote == "'" || quote == "`" {
                let length = stringLength(rest, quote: quote)
                apply(&result, text: code, from: offset, length: length, colour: palette.string)
                offset += length
                continue
            }

            // A number.
            if let character = rest.first, character.isNumber {
                var length = 0
                for character in rest {
                    if character.isNumber || character == "." || character == "_" || character.isHexDigit && rest.distance(from: rest.startIndex, to: rest.index(rest.startIndex, offsetBy: length)) < 2 {
                        length += 1
                    } else { break }
                }
                apply(&result, text: code, from: offset, length: max(length, 1), colour: palette.number)
                offset += max(length, 1)
                continue
            }

            // A word.
            if let character = rest.first, character.isLetter || character == "_" {
                var length = 0
                for character in rest {
                    if character.isLetter || character.isNumber || character == "_" { length += 1 } else { break }
                }
                let word = String(rest.prefix(length))
                let following = rest.dropFirst(length).first
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
                apply(&result, text: code, from: offset, length: length, colour: colour)
                offset += length
                continue
            }

            offset += 1
        }
        _ = index
        return result
    }

    // MARK: - Pieces

    private static func apply(_ result: inout AttributedString, text: String, from offset: Int, length: Int, colour: Color) {
        guard length > 0, offset + length <= text.count else { return }
        let lower = text.index(text.startIndex, offsetBy: offset)
        let upper = text.index(lower, offsetBy: length)
        guard let start = AttributedString.Index(lower, within: result),
              let end = AttributedString.Index(upper, within: result) else { return }
        result[start..<end].foregroundColor = colour
    }

    /// The length of a string literal, including its quotes.
    private static func stringLength(_ text: String, quote: Character) -> Int {
        var length = 1
        var escaped = false
        for character in text.dropFirst() {
            length += 1
            if escaped {
                escaped = false
                continue
            }
            if character == "\\" {
                escaped = true
                continue
            }
            if character == quote { break }
            if character == "\n" { break }
        }
        return length
    }

    private static func commentPrefix(for language: String) -> String {
        switch language {
        case "python", "ruby", "shell", "bash", "sh", "yaml", "toml": "#"
        case "sql", "lua", "haskell": "--"
        default: "//"
        }
    }

    private static func keywordSet(for language: String?) -> Set<String> {
        switch language {
        case "swift":
            return ["actor", "as", "associatedtype", "break", "case", "catch", "class", "continue", "default", "defer", "deinit", "do", "else", "enum", "extension", "fallthrough", "false", "fileprivate", "final", "for", "func", "guard", "if", "import", "in", "init", "inout", "internal", "is", "let", "nil", "open", "operator", "private", "protocol", "public", "repeat", "rethrows", "return", "self", "some", "static", "struct", "subscript", "super", "switch", "throw", "throws", "true", "try", "typealias", "var", "where", "while"]
        case "rust":
            return ["as", "async", "await", "break", "const", "continue", "crate", "dyn", "else", "enum", "extern", "false", "fn", "for", "if", "impl", "in", "let", "loop", "match", "mod", "move", "mut", "pub", "ref", "return", "self", "Self", "static", "struct", "super", "trait", "true", "type", "unsafe", "use", "where", "while"]
        case "python":
            return ["and", "as", "assert", "async", "await", "break", "class", "continue", "def", "del", "elif", "else", "except", "False", "finally", "for", "from", "global", "if", "import", "in", "is", "lambda", "None", "nonlocal", "not", "or", "pass", "raise", "return", "True", "try", "while", "with", "yield"]
        case "go":
            return ["break", "case", "chan", "const", "continue", "default", "defer", "else", "fallthrough", "for", "func", "go", "goto", "if", "import", "interface", "map", "package", "range", "return", "select", "struct", "switch", "type", "var"]
        case "json":
            return ["true", "false", "null"]
        case "sql":
            return ["select", "from", "where", "insert", "into", "values", "update", "set", "delete", "create", "table", "join", "left", "right", "inner", "outer", "on", "group", "by", "order", "having", "limit", "as", "and", "or", "not", "null"]
        case "shell", "bash", "sh":
            return ["if", "then", "else", "elif", "fi", "for", "while", "do", "done", "case", "esac", "function", "return", "export", "local", "echo", "cd", "set", "unset"]
        case "typescript", "ts", "tsx", "javascript", "js", "jsx":
            return ["abstract", "any", "as", "async", "await", "break", "case", "catch", "class", "const", "continue", "declare", "default", "delete", "do", "else", "enum", "export", "extends", "false", "finally", "for", "from", "function", "if", "implements", "import", "in", "instanceof", "interface", "let", "new", "null", "of", "private", "protected", "public", "readonly", "return", "static", "super", "switch", "this", "throw", "true", "try", "type", "typeof", "undefined", "var", "void", "while", "yield"]
        default:
            return ["if", "else", "for", "while", "return", "break", "continue", "switch", "case", "default", "func", "function", "class", "struct", "enum", "import", "export", "const", "let", "var", "true", "false", "null", "nil", "none", "def", "lambda", "async", "await", "public", "private", "static", "new", "try", "catch", "throw"]
        }
    }

    private static func typeSet(for language: String?) -> Set<String> {
        switch language {
        case "swift":
            return ["String", "Int", "Bool", "Double", "Float", "Character", "Array", "Dictionary", "Set", "Optional", "Result", "Void", "Any", "Self", "Date", "URL", "Data", "UUID"]
        case "rust":
            return ["String", "str", "Vec", "Option", "Result", "Box", "HashMap", "HashSet", "i8", "i16", "i32", "i64", "u8", "u16", "u32", "u64", "usize", "isize", "f32", "f64", "bool", "char"]
        default:
            return []
        }
    }
}

/// A colour, written as a hex number.
public extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

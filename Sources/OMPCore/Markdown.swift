import Foundation

/// A block of a markdown document.
public enum MarkdownBlock: Identifiable, Sendable, Equatable {
    case heading(id: String, level: Int, text: String)
    case paragraph(id: String, text: String)
    case code(id: String, language: String?, text: String)
    case list(id: String, ordered: Bool, items: [MarkdownItem])
    case quote(id: String, text: String)
    case rule(id: String)
    case table(id: String, header: [String], rows: [[String]])

    public var id: String {
        switch self {
        case .heading(let id, _, _), .paragraph(let id, _), .code(let id, _, _),
             .list(let id, _, _), .quote(let id, _), .rule(let id), .table(let id, _, _): id
        }
    }
}

/// One entry of a list.
public struct MarkdownItem: Sendable, Equatable {
    public var text: String
    /// Set for a task-list entry.
    public var checked: Bool?
    public var children: [MarkdownItem]

    public init(text: String, checked: Bool? = nil, children: [MarkdownItem] = []) {
        self.text = text
        self.checked = checked
        self.children = children
    }
}

/// A markdown reader.
///
/// The block structure is read here; the inline styling is left to
/// `AttributedString(markdown:)`, which knows the inline grammar and does not
/// recurse.
public enum Markdown {
    public static func blocks(of source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        let lines = source.components(separatedBy: .newlines)
        var index = 0
        var counter = 0

        func identifier() -> String { counter += 1; return "md\(counter)" }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // A fenced code block.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                index += 1
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix(fence) { break }
                    body.append(lines[index])
                    index += 1
                }
                index += 1
                blocks.append(.code(id: identifier(), language: language.isEmpty ? nil : language, text: body.joined(separator: "\n")))
                continue
            }

            // A heading.
            if trimmed.hasPrefix("#") {
                let hashes = trimmed.prefix { $0 == "#" }.count
                if hashes <= 6 {
                    let text = String(trimmed.dropFirst(hashes)).trimmingCharacters(in: .whitespaces)
                    blocks.append(.heading(id: identifier(), level: hashes, text: text))
                    index += 1
                    continue
                }
            }

            // A horizontal rule.
            if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "-" || $0 == "*" || $0 == "_" }),
               trimmed.contains("-") || trimmed.contains("*") || trimmed.contains("_"),
               Set(trimmed).count == 1 {
                blocks.append(.rule(id: identifier()))
                index += 1
                continue
            }

            // A table: a header row, a rule, then body rows.
            if trimmed.contains("|"), index + 1 < lines.count,
               isTableRule(lines[index + 1]) {
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                index += 2
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.contains("|") else { break }
                    rows.append(tableCells(candidate))
                    index += 1
                }
                blocks.append(.table(id: identifier(), header: header, rows: rows))
                continue
            }

            // A list.
            if let bullet = listMarker(trimmed) {
                let ordered = bullet.ordered
                var items: [MarkdownItem] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard let marker = listMarker(candidate), marker.ordered == ordered else { break }
                    var text = String(candidate.dropFirst(marker.raw.count))
                    var checked: Bool?
                    if text.hasPrefix("[ ] ") { checked = false; text = String(text.dropFirst(4)) }
                    else if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { checked = true; text = String(text.dropFirst(4)) }
                    index += 1
                    // An indented line continues the entry.
                    var children: [MarkdownItem] = []
                    while index < lines.count {
                        let next = lines[index]
                        if next.trimmingCharacters(in: .whitespaces).isEmpty { break }
                        if listMarker(next.trimmingCharacters(in: .whitespaces)) != nil { break }
                        if !next.hasPrefix("  ") && !next.hasPrefix("\t") { break }
                        text += "\n" + next.trimmingCharacters(in: .whitespaces)
                        index += 1
                    }
                    items.append(MarkdownItem(text: text, checked: checked, children: children))
                }
                blocks.append(.list(id: identifier(), ordered: ordered, items: items))
                continue
            }

            // A quote.
            if trimmed.hasPrefix(">") {
                var body: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    body.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(id: identifier(), text: body.joined(separator: "\n")))
                continue
            }

            // A paragraph: everything up to the next blank line.
            if trimmed.isEmpty {
                index += 1
                continue
            }
            var body: [String] = []
            while index < lines.count {
                let candidate = lines[index]
                let candidateTrimmed = candidate.trimmingCharacters(in: .whitespaces)
                if candidateTrimmed.isEmpty { break }
                if candidateTrimmed.hasPrefix("#") || candidateTrimmed.hasPrefix("```") || candidateTrimmed.hasPrefix(">") { break }
                if listMarker(candidateTrimmed) != nil { break }
                body.append(candidateTrimmed)
                index += 1
            }
            blocks.append(.paragraph(id: identifier(), text: body.joined(separator: "\n")))
        }
        return blocks
    }

    /// The inline styling of a piece of text.
    public static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }

    // MARK: - Pieces

    private struct Marker {
        let raw: String
        let ordered: Bool
    }

    private static func listMarker(_ line: String) -> Marker? {
        for prefix in ["- ", "* ", "+ "] where line.hasPrefix(prefix) {
            return Marker(raw: prefix, ordered: false)
        }
        // An ordered marker: digits, a dot, a space.
        var digits = ""
        for character in line {
            if character.isNumber { digits.append(character) } else { break }
        }
        if !digits.isEmpty, line.dropFirst(digits.count).hasPrefix(". ") {
            return Marker(raw: "\(digits). ", ordered: true)
        }
        return nil
    }

    private static func isTableRule(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { $0 == "-" || $0 == "|" || $0 == ":" || $0 == " " }
    }

    private static func tableCells(_ line: String) -> [String] {
        var cells = line.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if cells.first?.isEmpty == true { cells.removeFirst() }
        if cells.last?.isEmpty == true { cells.removeLast() }
        return cells
    }
}

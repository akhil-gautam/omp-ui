import Foundation

/// One line of a change.
public enum DiffLine: Sendable, Equatable {
    case context(String)
    case removed(String)
    case added(String)

    public var text: String {
        switch self {
        case .context(let text), .removed(let text), .added(let text): text
        }
    }

    public var marker: String {
        switch self {
        case .context: " "
        case .removed: "-"
        case .added: "+"
        }
    }
}

/// The difference between two texts.
///
/// A single change, as an editor makes it: the common head and tail are
/// kept, and what falls between them is the change.
public enum Diff {
    public static func lines(from old: String, to new: String, context: Int = 3) -> [DiffLine] {
        let before = old.components(separatedBy: "\n")
        let after = new.components(separatedBy: "\n")

        var head = 0
        while head < before.count, head < after.count, before[head] == after[head] {
            head += 1
        }
        var tail = 0
        while tail < before.count - head, tail < after.count - head,
              before[before.count - 1 - tail] == after[after.count - 1 - tail] {
            tail += 1
        }

        // Only a little of the unchanged text is worth showing.
        let keep = max(context, 0)
        var lines: [DiffLine] = []
        let headStart = max(head - keep, 0)
        for index in headStart..<head { lines.append(.context(before[index])) }
        for index in head..<(before.count - tail) { lines.append(.removed(before[index])) }
        for index in head..<(after.count - tail) { lines.append(.added(after[index])) }
        let tailStart = before.count - tail
        let tailEnd = min(tailStart + keep, before.count)
        for index in tailStart..<tailEnd { lines.append(.context(before[index])) }
        return lines
    }
}

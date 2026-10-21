import Foundation

/// One entry in the transcript.
public enum Block: Identifiable, Sendable, Equatable {
    case user(id: String, text: String)
    case text(id: String, text: String)
    case thinking(id: String, text: String)
    case tool(id: String, name: String, args: JSONValue?, output: String?, isError: Bool, running: Bool)
    /// A turn the model could not finish, with the reason it gave.
    case failure(id: String, text: String)

    public var id: String {
        switch self {
        case .user(let id, _), .text(let id, _), .thinking(let id, _), .tool(let id, _, _, _, _, _), .failure(let id, _): id
        }
    }

    /// The text the block shows, when it shows any.
    public var text: String {
        switch self {
        case .user(_, let text), .text(_, let text), .thinking(_, let text), .failure(_, let text): text
        case .tool: ""
        }
    }
}

/// The transcript of one session, and the rules for folding tool calls into
/// single rows.
public struct Transcript: Sendable {
    public private(set) var blocks: [Block] = []

    public init() {}

    public mutating func replace(with blocks: [Block]) {
        self.blocks = blocks
    }

    public mutating func clear() {
        blocks.removeAll()
    }

    /// Appends a block, replacing one with the same id.
    public mutating func append(_ block: Block) {
        if let index = blocks.firstIndex(where: { $0.id == block.id }) {
            blocks[index] = block
        } else {
            blocks.append(block)
        }
    }

    public mutating func update(id: String, _ change: (inout Block) -> Void) {
        guard let index = blocks.firstIndex(where: { $0.id == id }) else { return }
        change(&blocks[index])
    }

    /// Appends text to a block, for streamed deltas.
    public mutating func appendText(id: String, text: String) {
        update(id: id) { block in
            switch block {
            case .user(let blockID, let body): block = .user(id: blockID, text: body + text)
            case .text(let blockID, let body): block = .text(id: blockID, text: body + text)
            case .thinking(let blockID, let body): block = .thinking(id: blockID, text: body + text)
            case .tool, .failure: break
            }
        }
    }
}

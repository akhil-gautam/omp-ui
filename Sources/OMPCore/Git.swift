import Foundation

/// Reading what a project directory is, for the interface.
public enum Git {
    /// The branch a project is on, when it is a git repository.
    ///
    /// Reads `.git/HEAD` directly: a full git client is a lot of machinery for
    /// one line of text.
    public static func branch(of path: String) -> String? {
        let head = URL(fileURLWithPath: path).appendingPathComponent(".git/HEAD")
        guard let text = try? String(contentsOf: head, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("ref: ") {
            return trimmed.dropFirst(5).split(separator: "/").last.map(String.init)
        }
        // A detached head names the commit.
        return trimmed.count >= 7 ? String(trimmed.prefix(7)) : nil
    }
}

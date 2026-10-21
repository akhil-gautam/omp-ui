import Foundation

/// How omp asks before it acts, read from its own configuration.
///
/// The app cannot change this at runtime, so it is shown as it is.
public enum ApprovalMode {
    /// The configured mode, if there is one.
    public static func read() -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omp/agent/config.yml")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("approvalMode:") else { continue }
            let raw = String(trimmed.dropFirst("approvalMode:".count))
            let value = raw.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            if !value.isEmpty { return value }
        }
        return nil
    }

    /// The mode, in the words the interface uses.
    public static func label(_ mode: String?) -> String? {
        guard let mode else { return nil }
        switch mode {
        case "always-ask": return "Manual"
        case "always-ask-cached": return "Manual, remembered"
        case "write": return "Writes only"
        case "yolo": return "Automatic"
        default: return mode
        }
    }
}

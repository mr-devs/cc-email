import CCEmailCore
import Foundation

/// One row in a conversation's transcript. Saved to disk, so only what's needed to redraw it.
struct TranscriptItem: Identifiable, Codable, Equatable {
    enum Kind: String, Codable { case user, assistant, tool, notice, error }
    enum ToolStatus: String, Codable { case running, done, failed }

    var id = UUID()
    var kind: Kind
    /// Markdown for user, assistant, notice and error rows; the one-line summary for a tool row.
    var text: String
    var toolName: String?
    var toolUseId: String?
    var toolStatus: ToolStatus?
    /// A short error excerpt for a failed tool.
    var detail: String?
    /// Tool calls made inside a subagent (e.g. email-reader) started by this tool.
    var childCount = 0
    var childActivity: String?
}

enum ToolDisplay {
    /// "mcp__claude_ai_Gmail__search_threads" → "Gmail · search threads"
    static func name(_ raw: String) -> String {
        if raw.hasPrefix("mcp__") {
            let parts = raw.dropFirst(5).components(separatedBy: "__")
            if parts.count >= 2 {
                let server = parts[0].replacingOccurrences(of: "claude_ai_", with: "")
                    .replacingOccurrences(of: "_", with: " ")
                return "\(server) · \(parts[1...].joined(separator: " ").replacingOccurrences(of: "_", with: " "))"
            }
        }
        return raw
    }

    /// A short, safe description of a tool call. Only well-known keys are shown, so message
    /// bodies don't leak into the transcript, and label IDs are replaced by names.
    static func summary(name: String, input: JSONValue, labels: LabelNames) -> String {
        // Label changes: name the labels.
        var labelParts: [String] = []
        for (key, verb) in [("labelIds", "labels"), ("addLabelIds", "add"), ("removeLabelIds", "remove")] {
            let ids = (input[key]?.arrayValue ?? []).compactMap(\.stringValue)
            if !ids.isEmpty { labelParts.append("\(verb) " + ids.map(labels.humanize).joined(separator: ", ")) }
        }
        if !labelParts.isEmpty { return labelParts.joined(separator: "; ") }

        let keys = ["description", "command", "query", "file_path", "path", "pattern", "skill", "subject", "prompt"]
        for key in keys {
            if let value = input[key]?.stringValue, !value.isEmpty {
                return labels.humanize(String(value.prefix(160))).replacingOccurrences(of: "\n", with: " ")
            }
        }
        return ""
    }
}

import Foundation

/// Gmail label ID → name, read from `CLAUDE.local.md`. CLAUDE.md says label IDs are never shown
/// to the user, so tool inputs displayed in the app pass through `humanize(_:)` first.
public struct LabelNames: Sendable, Equatable {
    public private(set) var names: [String: String] = [:]

    public init(names: [String: String] = [:]) {
        self.names = names
    }

    /// Reads both forms `CLAUDE.local.md` uses:
    /// a list entry, `` - `Work-Admin` (`Label_123`): … ``, and a table row, `` | Work | `Label_123` | … ``.
    public init(claudeLocalMarkdown text: String) {
        for line in text.components(separatedBy: .newlines) {
            if let m = line.firstMatch(of: /`([^`]+)`\s*\(`(Label_[0-9]+)`\)/) {
                names[String(m.2)] = String(m.1)
            } else if line.hasPrefix("|") {
                let cells = MarkdownBlocks.tableCells(line)
                if cells.count >= 2, let id = cells[1].firstMatch(of: /^`?(Label_[0-9]+)`?$/) {
                    names[String(id.1)] = cells[0].replacingOccurrences(of: "`", with: "")
                }
            }
        }
    }

    /// Replaces every `Label_<digits>` in `text` with the label's name (or "a label" if unknown).
    public func humanize(_ text: String) -> String {
        text.replacing(/Label_[0-9]+/) { match in
            names[String(match.output)] ?? "a label"
        }
    }
}

import Foundation

/// One change the user made in the app. Each edit records the value it expected to find,
/// so it can be applied to a newer copy of the file (after Claude rewrote it) or refused if
/// the target changed underneath it.
public enum SummaryEdit: Sendable, Hashable {
    case setChecked(threadId: String, kind: ActionLine.Kind, ordinal: Int, from: Bool, to: Bool)
    case setNotes(threadId: String, from: String, to: String)

    public var threadId: String {
        switch self {
        case .setChecked(let id, _, _, _, _), .setNotes(let id, _, _): return id
        }
    }
}

public struct SummaryConflict: Sendable, Equatable {
    public var edit: SummaryEdit
    /// The item's current tag, if it's still in the file.
    public var tag: String?
    public var reason: String
}

public enum SummaryPatcher {
    public static let notesPrefix = "- **Notes:** "

    /// Applies `edits` in order to `text`, changing only the targeted characters or lines.
    /// Edits whose target is gone or no longer has the expected value are returned as conflicts.
    public static func apply(_ edits: [SummaryEdit], to text: String) -> (text: String, conflicts: [SummaryConflict]) {
        var lines = text.components(separatedBy: "\n")
        var conflicts: [SummaryConflict] = []

        for edit in edits {
            // Re-parse each time: the previous edit can't move lines, but parsing is cheap and keeps this simple.
            let doc = SummaryParser.parse(lines.joined(separator: "\n"))
            guard let item = doc.item(threadId: edit.threadId) else {
                conflicts.append(SummaryConflict(edit: edit, tag: nil, reason: "The email is no longer in the summary."))
                continue
            }
            switch edit {
            case .setChecked(_, let kind, let ordinal, let from, let to):
                guard let action = item.actions.first(where: { $0.kind == kind && $0.ordinal == ordinal }) else {
                    conflicts.append(SummaryConflict(
                        edit: edit, tag: item.tag, reason: "Its \(kind.rawValue.lowercased()) was removed."))
                    continue
                }
                if action.checked == to { continue }  // already as wanted
                guard action.checked == from else {
                    conflicts.append(SummaryConflict(
                        edit: edit, tag: item.tag, reason: "Its \(kind.rawValue.lowercased()) changed."))
                    continue
                }
                lines[action.lineIndex] = settingCheckbox(lines[action.lineIndex], checked: to)

            case .setNotes(_, let from, let to):
                guard let notes = item.notes else {
                    conflicts.append(SummaryConflict(edit: edit, tag: item.tag, reason: "Its Notes line is missing."))
                    continue
                }
                let wanted = normalizedNotes(to)
                if notes.text == wanted { continue }
                guard notes.text == normalizedNotes(from) else {
                    conflicts.append(SummaryConflict(edit: edit, tag: item.tag, reason: "Its Notes changed."))
                    continue
                }
                lines[notes.lineIndex] = notesLine(wanted, replacing: lines[notes.lineIndex])
            }
        }
        return (lines.joined(separator: "\n"), conflicts)
    }

    /// `- [ ] **Suggestion:** …` with only the box character changed.
    static func settingCheckbox(_ line: String, checked: Bool) -> String {
        guard let open = line.range(of: "- [") else { return line }
        var chars = Array(line)
        let boxIndex = line.distance(from: line.startIndex, to: open.upperBound)
        guard boxIndex < chars.count else { return line }
        chars[boxIndex] = checked ? "x" : " "
        return String(chars)
    }

    /// Notes are one line in the file; typed newlines become spaces.
    public static func normalizedNotes(_ text: String) -> String {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// A Notes line with new text, keeping the original indentation and line ending.
    /// Empty notes keep the template's trailing space: `- **Notes:** `.
    static func notesLine(_ text: String, replacing original: String) -> String {
        let indent = String(original.prefix { $0 == " " || $0 == "\t" })
        let ending = original.hasSuffix("\r") ? "\r" : ""
        return indent + notesPrefix + text + ending
    }
}

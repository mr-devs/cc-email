import Foundation

/// `inbox-summary.md` as written by the /summary skill (see `.claude/skills/summary/SKILL.md`).
/// Every element remembers its line index so edits can be written back without touching anything else.
public struct SummaryDocument: Sendable, Equatable {
    /// The file split on "\n", exactly as read (a trailing "\r" stays on its line).
    /// `lines.joined(separator: "\n")` reproduces the file byte for byte.
    public var lines: [String]
    public var title: String?
    public var updatedLine: String?
    public var needsYou: [NeedsYouLine] = []
    public var counts: [CountsRow] = []
    /// Lines after the counts table, e.g. "13 other labels: all read."
    public var countsNotes: [String] = []
    public var sections: [SummarySection] = []
    public var done: [DoneLine] = []
    /// Problems found while parsing. Never fatal.
    public var warnings: [String] = []

    public var text: String { lines.joined(separator: "\n") }

    /// Every item outside Done, in file order.
    public var items: [SummaryItem] { sections.flatMap { $0.groups.flatMap(\.items) } }

    public func item(threadId: String) -> SummaryItem? {
        items.first { $0.threadId == threadId }
    }

    public func item(tag: String) -> SummaryItem? {
        items.first { $0.tag == tag }
    }

    /// Items the user has given directions on: a ticked box or text in Notes.
    public var itemsWithDirections: [SummaryItem] { items.filter(\.hasDirections) }

    /// True when the file has content but no recognisable items, sections or Done lines,
    /// e.g. a format the parser doesn't know.
    public var isUnrecognized: Bool {
        let hasContent = lines.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasContent && title == nil && sections.isEmpty && done.isEmpty
    }
}

public struct NeedsYouLine: Sendable, Equatable, Identifiable {
    public var id: Int { lineIndex }
    public var lineIndex: Int
    public var tag: String?
    public var sender: String?
    /// What's needed, or the whole line if it didn't match the expected shape.
    public var text: String
}

public struct CountsRow: Sendable, Equatable, Identifiable {
    public var id: String { label }
    public var label: String
    public var unread: String
    public var read: String
}

public struct SummarySection: Sendable, Equatable, Identifiable {
    public var id: Int { lineIndex }
    public var lineIndex: Int
    /// "Inbox", "Work", "Promotions/Forums", …
    public var name: String
    /// The text in parentheses, e.g. "4 threads, 0 unread".
    public var detail: String?
    public var groups: [SummaryGroup]

    public var itemCount: Int { groups.reduce(0) { $0 + $1.items.count } }
}

public struct SummaryGroup: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable { case unread = "Unread", read = "Read", ungrouped = "" }
    public var id: String { kind.rawValue }
    public var kind: Kind
    public var items: [SummaryItem]
}

public struct SummaryItem: Sendable, Equatable, Identifiable {
    public var id: String { threadId }
    public var threadId: String
    public var tag: String
    /// Display text, with Markdown escapes removed.
    public var subject: String
    public var url: URL?
    public var headingLineIndex: Int
    /// Sender as written, including any ★/☆ marker and "+N".
    public var from: String?
    public var summary: String?
    public var labels: [String] = []
    public var actions: [ActionLine] = []
    public var notes: NotesLine?
    /// Claude's "- ✗ … ; ✓ … (M/D)" lines after a partly failed pass.
    public var statusLines: [StatusLine] = []

    public var suggestion: ActionLine? { actions.first { $0.kind == .suggestion } }
    public var reminders: [ActionLine] { actions.filter { $0.kind == .reminder } }

    public var hasDirections: Bool {
        actions.contains(where: \.checked) || !(notes?.text.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
    }

    /// ★ for Tier 1 senders, ☆ for Tier 2.
    public var priorityMarker: String? {
        guard let from else { return nil }
        if from.hasPrefix("★") { return "★" }
        if from.hasPrefix("☆") { return "☆" }
        return nil
    }
}

public struct ActionLine: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable, Codable { case suggestion = "Suggestion", reminder = "Reminder" }
    public var id: String { "\(kind.rawValue)-\(ordinal)" }
    public var kind: Kind
    /// Position among this item's actions of the same kind (an item can have two reminders).
    public var ordinal: Int
    public var checked: Bool
    public var text: String
    public var lineIndex: Int
}

public struct NotesLine: Sendable, Equatable {
    public var text: String
    public var lineIndex: Int
}

public struct StatusLine: Sendable, Equatable, Identifiable {
    public var id: Int { lineIndex }
    public var lineIndex: Int
    public var text: String
    /// True for a "✗" line (something failed), false for a "✓" line.
    public var isFailure: Bool
}

public struct DoneLine: Sendable, Equatable, Identifiable {
    public var id: Int { lineIndex }
    public var lineIndex: Int
    public var tag: String?
    public var sender: String?
    public var subject: String?
    public var url: URL?
    public var threadId: String?
    /// What was done, or the whole line if it didn't match.
    public var outcome: String
}

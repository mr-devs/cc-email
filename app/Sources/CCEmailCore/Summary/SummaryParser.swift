import Foundation

/// Parses `inbox-summary.md`. It never fails: lines it doesn't recognise are left alone
/// (they stay in `lines`) and anything surprising is reported in `warnings`.
public enum SummaryParser {
    public static func parse(_ text: String) -> SummaryDocument {
        let lines = text.components(separatedBy: "\n")
        var doc = SummaryDocument(lines: lines)

        enum Region { case preamble, needsYou, counts, section, done, other }
        var region = Region.preamble
        var currentSection: SummarySection?
        var currentGroup: SummaryGroup?
        var currentItem: SummaryItem?
        var actionOrdinals: [ActionLine.Kind: Int] = [:]

        func closeItem() {
            if let item = currentItem {
                if currentGroup == nil { currentGroup = SummaryGroup(kind: .ungrouped, items: []) }
                currentGroup!.items.append(item)
            }
            currentItem = nil
            actionOrdinals = [:]
        }
        func closeGroup() {
            closeItem()
            if let group = currentGroup, currentSection != nil {
                currentSection!.groups.append(group)
            }
            currentGroup = nil
        }
        func closeSection() {
            closeGroup()
            if let section = currentSection { doc.sections.append(section) }
            currentSection = nil
        }

        for (index, raw) in lines.enumerated() {
            let line = raw.hasSuffix("\r") ? String(raw.dropLast()) : raw
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // `# Inbox summary`
            if doc.title == nil, let m = trimmed.firstMatch(of: /^# (.+)$/) {
                doc.title = String(m.1)
                continue
            }

            // `## Section (detail)`
            if let m = trimmed.firstMatch(of: /^## (.+)$/) {
                closeSection()
                let (name, detail) = splitSectionHeading(String(m.1))
                switch name.lowercased() {
                case "needs you": region = .needsYou
                case "counts": region = .counts
                case "done": region = .done
                default:
                    region = .section
                    currentSection = SummarySection(lineIndex: index, name: name, detail: detail, groups: [])
                }
                continue
            }

            switch region {
            case .preamble:
                if doc.updatedLine == nil, trimmed.hasPrefix("Updated") { doc.updatedLine = trimmed }

            case .needsYou:
                guard trimmed.hasPrefix("- ") else { continue }
                doc.needsYou.append(parseNeedsYou(trimmed, lineIndex: index))

            case .counts:
                if trimmed.hasPrefix("|") {
                    if MarkdownBlocks.isTableSeparator(trimmed) { continue }
                    let cells = MarkdownBlocks.tableCells(trimmed)
                    guard cells.count >= 3, cells[0] != "Label" else { continue }
                    doc.counts.append(CountsRow(label: cells[0], unread: cells[1], read: cells[2]))
                } else if !trimmed.isEmpty {
                    doc.countsNotes.append(trimmed)
                }

            case .done:
                guard trimmed.hasPrefix("- ") else { continue }
                doc.done.append(parseDone(trimmed, lineIndex: index))

            case .section:
                if let m = trimmed.firstMatch(of: /^### (.+)$/) {
                    closeGroup()
                    let kind = SummaryGroup.Kind(rawValue: String(m.1).trimmingCharacters(in: .whitespaces))
                    if kind == nil { doc.warnings.append("Line \(index + 1): unknown group \"\(m.1)\"") }
                    currentGroup = SummaryGroup(kind: kind ?? .ungrouped, items: [])
                    continue
                }
                if trimmed.hasPrefix("#### ") {
                    closeItem()
                    if let item = parseItemHeading(trimmed, lineIndex: index) {
                        currentItem = item
                    } else {
                        doc.warnings.append("Line \(index + 1): item heading without a Gmail thread link")
                    }
                    continue
                }
                guard currentItem != nil else { continue }
                parseItemLine(trimmed, lineIndex: index, into: &currentItem!, ordinals: &actionOrdinals)

            case .other:
                break
            }
        }
        closeSection()

        // Thread IDs are the keys for edits; a duplicate would make an edit ambiguous.
        var seen = Set<String>()
        for item in doc.items where !seen.insert(item.threadId).inserted {
            doc.warnings.append("Thread in \(item.tag) appears more than once; edits apply to the first")
        }
        return doc
    }

    // MARK: Pieces

    /// "Work (4 threads, 0 unread)" → ("Work", "4 threads, 0 unread")
    static func splitSectionHeading(_ heading: String) -> (String, String?) {
        if let m = heading.firstMatch(of: /^(.*?)\s*\(([^()]*)\)\s*$/) {
            return (String(m.1), String(m.2))
        }
        return (heading.trimmingCharacters(in: .whitespaces), nil)
    }

    static func parseNeedsYou(_ line: String, lineIndex: Int) -> NeedsYouLine {
        if let m = line.firstMatch(of: /^- \*\*(\S+?)\*\* · (.*)$/) {
            let rest = String(m.2)
            if let colon = rest.range(of: ": ") {
                return NeedsYouLine(
                    lineIndex: lineIndex, tag: String(m.1),
                    sender: String(rest[..<colon.lowerBound]), text: String(rest[colon.upperBound...])
                )
            }
            return NeedsYouLine(lineIndex: lineIndex, tag: String(m.1), sender: nil, text: rest)
        }
        return NeedsYouLine(lineIndex: lineIndex, tag: nil, sender: nil, text: String(line.dropFirst(2)))
    }

    static func parseDone(_ line: String, lineIndex: Int) -> DoneLine {
        if let m = line.firstMatch(of: /^- ✓ \*\*(\S+?)\*\* · (.*?) · \[((?:\\.|[^\]\\])*)\]\((\S+?)\) — (.*)$/) {
            let url = URL(string: String(m.4))
            return DoneLine(
                lineIndex: lineIndex, tag: String(m.1), sender: String(m.2),
                subject: unescape(String(m.3)), url: url, threadId: url.flatMap(threadId(from:)),
                outcome: String(m.5)
            )
        }
        var outcome = String(line.dropFirst(2))
        if outcome.hasPrefix("✓ ") { outcome = String(outcome.dropFirst(2)) }
        return DoneLine(lineIndex: lineIndex, tag: nil, sender: nil, subject: nil, url: nil, threadId: nil, outcome: outcome)
    }

    static func parseItemHeading(_ line: String, lineIndex: Int) -> SummaryItem? {
        guard let m = line.firstMatch(of: /^#### (\S+) · \[((?:\\.|[^\]\\])*)\]\((\S+?)\)\s*$/),
              let url = URL(string: String(m.3)),
              let threadId = threadId(from: url)
        else { return nil }
        return SummaryItem(
            threadId: threadId, tag: String(m.1), subject: unescape(String(m.2)),
            url: url, headingLineIndex: lineIndex
        )
    }

    static func parseItemLine(
        _ line: String, lineIndex: Int, into item: inout SummaryItem, ordinals: inout [ActionLine.Kind: Int]
    ) {
        if let m = line.firstMatch(of: /^\*\*(From|Summary|Labels):\*\*\s?(.*)$/) {
            var value = String(m.2)
            if value.hasSuffix("\\") { value.removeLast() }
            value = value.trimmingCharacters(in: .whitespaces)
            switch m.1 {
            case "From": item.from = value
            case "Summary": item.summary = value
            default: item.labels = value.matches(of: /`([^`]+)`/).map { String($0.1) }
            }
            return
        }
        if let m = line.firstMatch(of: /^- \[([ xX])\] \*\*(Suggestion|Reminder):\*\*\s?(.*)$/) {
            let kind = ActionLine.Kind(rawValue: String(m.2))!
            let ordinal = ordinals[kind, default: 0]
            ordinals[kind] = ordinal + 1
            item.actions.append(ActionLine(
                kind: kind, ordinal: ordinal, checked: m.1 != " ", text: String(m.3), lineIndex: lineIndex
            ))
            return
        }
        if let m = line.firstMatch(of: /^- \*\*Notes:\*\*(.*)$/) {
            item.notes = NotesLine(text: String(m.1).trimmingCharacters(in: .whitespaces), lineIndex: lineIndex)
            return
        }
        if let m = line.firstMatch(of: /^- ([✗✓])\s?(.*)$/) {
            item.statusLines.append(StatusLine(lineIndex: lineIndex, text: String(m.2), isFailure: m.1 == "✗"))
        }
    }

    /// The thread ID is the last path segment of the Gmail link's fragment, e.g. `#all/18f3a2b4c5d6e701`.
    public static func threadId(from url: URL) -> String? {
        if let fragment = url.fragment, let last = fragment.split(separator: "/").last, !last.isEmpty {
            return String(last)
        }
        let last = url.lastPathComponent
        return last.isEmpty || last == "/" ? nil : last
    }

    /// Removes Markdown backslash escapes (`\[` → `[`).
    static func unescape(_ s: String) -> String {
        var out = ""
        var escaped = false
        for ch in s {
            if escaped {
                out.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else {
                out.append(ch)
            }
        }
        if escaped { out.append("\\") }
        return out
    }
}

import Foundation

/// Block-level Markdown for the chat pane. SwiftUI renders inline Markdown (bold, links, code)
/// but not blocks, and approval tables are the part of a reply that matters most.
public enum MarkdownBlock: Sendable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case listItem(marker: String, indent: Int, text: String)
    case table(header: [String], rows: [[String]])
    case code(language: String, text: String)
    case quote(String)
    case rule
}

public enum MarkdownBlocks {
    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        let lines = markdown.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph.removeAll()
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty {
                flushParagraph()
                i += 1
                continue
            }

            // Fenced code
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushParagraph()
                let fence = String(trimmed.prefix(3))
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    body.append(lines[i])
                    i += 1
                }
                i += 1  // closing fence
                blocks.append(.code(language: language, text: body.joined(separator: "\n")))
                continue
            }

            // Table: a pipe row followed by a separator row
            if trimmed.hasPrefix("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushParagraph()
                let header = tableCells(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let row = lines[i].trimmingCharacters(in: .whitespaces)
                    guard row.hasPrefix("|") else { break }
                    var cells = tableCells(row)
                    if cells.count < header.count { cells += Array(repeating: "", count: header.count - cells.count) }
                    rows.append(Array(cells.prefix(max(header.count, 1))))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            // Heading
            if let match = trimmed.firstMatch(of: /^(#{1,6})\s+(.*)$/) {
                flushParagraph()
                blocks.append(.heading(level: match.1.count, text: String(match.2)))
                i += 1
                continue
            }

            // Horizontal rule
            if trimmed.firstMatch(of: /^([-*_])(\s*\1){2,}$/) != nil {
                flushParagraph()
                blocks.append(.rule)
                i += 1
                continue
            }

            // List item
            if let match = line.firstMatch(of: /^(\s*)([-*+]|\d+[.)])\s+(.*)$/) {
                flushParagraph()
                blocks.append(.listItem(marker: String(match.2), indent: match.1.count / 2, text: String(match.3)))
                i += 1
                continue
            }

            // Blockquote
            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    guard q.hasPrefix(">") else { break }
                    quoted.append(String(q.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }

            paragraph.append(line)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        return t.hasPrefix("|") && t.contains("-") && t.allSatisfy { "|:- ".contains($0) }
    }

    /// Splits `| a | b \| c |` into cells, honouring escaped pipes.
    static func tableCells(_ row: String) -> [String] {
        var t = row.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|"), !t.hasSuffix("\\|") { t.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        for ch in t {
            if escaped {
                current.append(ch == "|" ? "|" : "\\\(ch)")
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == "|" {
                cells.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
            } else {
                current.append(ch)
            }
        }
        if escaped { current.append("\\") }
        cells.append(current.trimmingCharacters(in: .whitespaces))
        return cells
    }
}

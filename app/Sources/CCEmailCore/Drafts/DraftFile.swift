import Foundation

/// A `drafts/*.md` file written by /draft-email: YAML-style front matter, then a plain-text body.
/// Only the front-matter lines for keys the user changed are rewritten; everything else is kept.
public struct DraftFile: Sendable, Equatable {
    public var to: [String]
    public var cc: [String]
    public var bcc: [String]
    public var from: String
    public var subject: String
    public var body: String
    /// Managed by Claude. Read-only in the app.
    public var replyToMessageId: String?
    public var threadId: String?
    public var draftId: String?
    public var gmailURL: String?

    /// The original text, so `serialized()` can change only what was edited.
    public private(set) var original: String
    public private(set) var hasFrontMatter: Bool

    public static let editableKeys = ["to", "cc", "bcc", "subject"]

    public init(text: String) {
        original = text
        let parsed = Self.split(text)
        hasFrontMatter = parsed.frontMatter != nil
        let values = Self.parseFrontMatter(parsed.frontMatter ?? [])
        to = Self.list(values["to"])
        cc = Self.list(values["cc"])
        bcc = Self.list(values["bcc"])
        from = Self.scalar(values["from"]) ?? ""
        subject = Self.scalar(values["subject"]) ?? ""
        replyToMessageId = Self.scalar(values["reply_to_message_id"])
        threadId = Self.scalar(values["thread_id"])
        draftId = Self.scalar(values["draft_id"])
        gmailURL = Self.scalar(values["gmail_url"])
        body = parsed.body
    }

    /// The file with the edited fields written back. Unchanged fields keep their exact original lines.
    public func serialized() -> String {
        let parsed = Self.split(original)
        guard var fm = parsed.frontMatter else {
            // No front matter: nothing to preserve but the body.
            return body
        }
        let before = DraftFile(text: original)
        if before.to == to, before.cc == cc, before.bcc == bcc, before.subject == subject, before.body == body {
            return original
        }
        func update(_ key: String, _ value: String) {
            if let i = fm.firstIndex(where: { Self.key(of: $0) == key }) {
                fm[i] = "\(key): \(value)"
            } else {
                fm.append("\(key): \(value)")
            }
        }
        if to != before.to { update("to", Self.formatList(to)) }
        if cc != before.cc { update("cc", Self.formatList(cc)) }
        if bcc != before.bcc { update("bcc", Self.formatList(bcc)) }
        if subject != before.subject { update("subject", Self.quote(subject)) }

        var text = "---\n" + fm.joined(separator: "\n") + "\n---\n"
        text += parsed.rawBodyPrefix + body
        return text
    }

    // MARK: Front matter

    struct Split {
        var frontMatter: [String]?
        /// Blank line(s) between the closing fence and the body, kept as they were.
        var rawBodyPrefix: String
        var body: String
    }

    static func split(_ text: String) -> Split {
        let normalized = text
        guard normalized.hasPrefix("---\n") || normalized.hasPrefix("---\r\n") else {
            return Split(frontMatter: nil, rawBodyPrefix: "", body: text)
        }
        let lines = normalized.components(separatedBy: "\n")
        guard let close = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" }) else {
            return Split(frontMatter: nil, rawBodyPrefix: "", body: text)
        }
        let fm = Array(lines[1..<close]).map { $0.hasSuffix("\r") ? String($0.dropLast()) : $0 }
        var rest = Array(lines[(close + 1)...])
        var prefix = ""
        while let first = rest.first, first.trimmingCharacters(in: .whitespaces).isEmpty, rest.count > 1 {
            prefix += first + "\n"
            rest.removeFirst()
        }
        return Split(frontMatter: fm, rawBodyPrefix: prefix, body: rest.joined(separator: "\n"))
    }

    static func key(of line: String) -> String? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let key = line[..<colon].trimmingCharacters(in: .whitespaces)
        return key.isEmpty || key.contains(" ") ? nil : key
    }

    static func parseFrontMatter(_ lines: [String]) -> [String: String] {
        var values: [String: String] = [:]
        for line in lines {
            guard let key = key(of: line), let colon = line.firstIndex(of: ":") else { continue }
            values[key] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        return values
    }

    static func scalar(_ raw: String?) -> String? {
        guard let raw, !raw.isEmpty, raw != "null", raw != "~" else { return nil }
        return unquote(raw)
    }

    static func unquote(_ raw: String) -> String {
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
            var out = ""
            var escaped = false
            for ch in raw.dropFirst().dropLast() {
                if escaped {
                    switch ch {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    default: out.append(ch)
                    }
                    escaped = false
                } else if ch == "\\" {
                    escaped = true
                } else {
                    out.append(ch)
                }
            }
            return out
        }
        if raw.count >= 2, raw.hasPrefix("'"), raw.hasSuffix("'") {
            return String(raw.dropFirst().dropLast()).replacingOccurrences(of: "''", with: "'")
        }
        return raw
    }

    /// `[a@x.com, "B <b@y.com>"]` or a bare `a@x.com`.
    static func list(_ raw: String?) -> [String] {
        guard let raw, !raw.isEmpty else { return [] }
        guard raw.hasPrefix("["), raw.hasSuffix("]") else { return [unquote(raw)] }
        var items: [String] = []
        var current = ""
        var quote: Character?
        for ch in raw.dropFirst().dropLast() {
            if let q = quote {
                current.append(ch)
                if ch == q { quote = nil }
            } else if ch == "\"" || ch == "'" {
                quote = ch
                current.append(ch)
            } else if ch == "," {
                items.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        items.append(current)
        return items.map { unquote($0.trimmingCharacters(in: .whitespaces)) }.filter { !$0.isEmpty }
    }

    static func formatList(_ items: [String]) -> String {
        "[" + items.map { needsQuoting($0) ? quote($0) : $0 }.joined(separator: ", ") + "]"
    }

    static func needsQuoting(_ s: String) -> Bool {
        s.contains { ",[]\"'#:{}".contains($0) } || s.hasPrefix(" ") || s.hasSuffix(" ")
    }

    static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    /// Three-way merge for when the file changed on disk while the user had unsaved edits.
    /// The result starts from the disk copy (so Claude's managed keys win). Each field the user
    /// changed is laid on top. A field both sides changed differently keeps the user's version
    /// and is listed in `conflicts`.
    public static func merge(base: DraftFile, mine: DraftFile, theirs: DraftFile) -> (merged: DraftFile, conflicts: [String]) {
        var merged = theirs
        var conflicts: [String] = []
        func field<T: Equatable>(_ name: String, _ path: WritableKeyPath<DraftFile, T>) {
            guard mine[keyPath: path] != base[keyPath: path] else { return }
            if theirs[keyPath: path] != base[keyPath: path], theirs[keyPath: path] != mine[keyPath: path] {
                conflicts.append(name)
            }
            merged[keyPath: path] = mine[keyPath: path]
        }
        field("To", \.to)
        field("Cc", \.cc)
        field("Bcc", \.bcc)
        field("Subject", \.subject)
        field("Body", \.body)
        return (merged, conflicts)
    }

    /// Splits a comma-separated recipients field typed by the user.
    public static func recipients(from field: String) -> [String] {
        field.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
}

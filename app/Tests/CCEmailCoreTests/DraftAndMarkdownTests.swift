import Foundation
import Testing
@testable import CCEmailCore

private let sampleDraft = """
    ---
    to: [jane.doe@example.edu]
    cc: []
    bcc: []
    from: you@example.com
    subject: "Re: Grant timeline: \\"phase 2\\""
    reply_to_message_id: 18f3a2b4c5d6e7f8
    thread_id: 18f3a2b4c5d6e7a1
    draft_id: r-1234567890123456789
    gmail_url: https://mail.google.com/mail/?authuser=you@example.com#drafts?compose=abc
    ---

    Hi Jane,

    Thanks for the update.

    Best,
    Sam

    """

@Suite struct DraftFileTests {
    @Test func parsesFrontMatter() {
        let d = DraftFile(text: sampleDraft)
        #expect(d.to == ["jane.doe@example.edu"])
        #expect(d.cc.isEmpty)
        #expect(d.from == "you@example.com")
        #expect(d.subject == #"Re: Grant timeline: "phase 2""#)
        #expect(d.threadId == "18f3a2b4c5d6e7a1")
        #expect(d.draftId == "r-1234567890123456789")
        #expect(d.gmailURL?.hasPrefix("https://mail.google.com/") == true)
        #expect(d.body.hasPrefix("Hi Jane,"))
        #expect(d.hasFrontMatter)
    }

    @Test func unchangedSerializesIdentically() {
        #expect(DraftFile(text: sampleDraft).serialized() == sampleDraft)
    }

    @Test func bodyEditLeavesFrontMatterIdentical() {
        var d = DraftFile(text: sampleDraft)
        d.body = "Hi Jane,\n\nShort answer: yes.\n"
        let out = d.serialized()
        let fmEnd = sampleDraft.range(of: "\n---\n")!.upperBound
        #expect(out.hasPrefix(String(sampleDraft[..<fmEnd])))
        #expect(out.hasSuffix("\nHi Jane,\n\nShort answer: yes.\n"))
        #expect(DraftFile(text: out).body == d.body)
    }

    @Test func subjectAndRecipientEditsChangeOnlyTheirLines() {
        var d = DraftFile(text: sampleDraft)
        d.subject = #"Budget: "final" \ v2"#
        d.cc = ["Pat Lee <pat@example.org>", "Lee, Pat <b@example.org>"]
        let out = d.serialized()
        let before = sampleDraft.components(separatedBy: "\n"), after = out.components(separatedBy: "\n")
        let changed = zip(before, after).filter { $0 != $1 }.map(\.1)
        #expect(changed.count == 2)
        // Only a value with a comma or YAML punctuation gets quoted.
        #expect(changed.contains("cc: [Pat Lee <pat@example.org>, \"Lee, Pat <b@example.org>\"]"))
        let reread = DraftFile(text: out)
        #expect(reread.subject == d.subject)
        #expect(reread.cc == d.cc)
        #expect(reread.draftId == d.draftId)
    }

    @Test func mergeTakesManagedKeysFromDiskAndFlagsConflicts() {
        let base = DraftFile(text: sampleDraft)
        var mine = base
        mine.body = "My new body\n"
        mine.subject = "Mine"
        // Claude synced: new draft_id, and (unusually) also changed the subject.
        let theirs = DraftFile(text: sampleDraft
            .replacingOccurrences(of: "r-1234567890123456789", with: "r-999")
            .replacingOccurrences(of: #"subject: "Re: Grant timeline: \"phase 2\"""#, with: "subject: Theirs"))
        let (merged, conflicts) = DraftFile.merge(base: base, mine: mine, theirs: theirs)
        #expect(merged.draftId == "r-999")
        #expect(merged.body == "My new body\n")
        #expect(merged.subject == "Mine")
        #expect(conflicts == ["Subject"])
        #expect(DraftFile(text: merged.serialized()).draftId == "r-999")
    }

    @Test func recipientsField() {
        #expect(DraftFile.recipients(from: " a@x.com, ,b@y.com ") == ["a@x.com", "b@y.com"])
    }
}

@Suite struct MarkdownBlocksTests {
    @Test func parsesApprovalTableAndLists() {
        let md = """
            Here's what I'll do:

            | Tag | Email | Change |
            |---|---|--:|
            | W1 | Editor · Review | remove `Work` |
            | I2 | Bank \\| Card | file to Personal-Finances |

            - first
              - nested
            1. numbered

            ```sh
            remindctl add
            ```
            > quoted
            ---
            ## Heading
            Reply **yes** to apply.
            """
        let blocks = MarkdownBlocks.parse(md)
        #expect(blocks == [
            .paragraph("Here's what I'll do:"),
            .table(header: ["Tag", "Email", "Change"], rows: [
                ["W1", "Editor · Review", "remove `Work`"],
                ["I2", "Bank | Card", "file to Personal-Finances"],
            ]),
            .listItem(marker: "-", indent: 0, text: "first"),
            .listItem(marker: "-", indent: 1, text: "nested"),
            .listItem(marker: "1.", indent: 0, text: "numbered"),
            .code(language: "sh", text: "remindctl add"),
            .quote("quoted"),
            .rule,
            .heading(level: 2, text: "Heading"),
            .paragraph("Reply **yes** to apply."),
        ])
    }
}

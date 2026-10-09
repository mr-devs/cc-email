import Foundation
import Testing
@testable import CCEmailCore

func fixture(_ name: String) throws -> String {
    let url = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

private let link = "https://mail.google.com/mail/?authuser=you@example.com#all/"

@Suite struct SummaryParserTests {
    @Test func parsesTemplate() throws {
        let doc = SummaryParser.parse(try fixture("summary-template.md"))
        #expect(doc.title == "Inbox summary")
        #expect(doc.updatedLine?.hasPrefix("Updated Wed 10/7, 4:50 pm.") == true)
        #expect(doc.warnings.isEmpty)

        #expect(doc.needsYou.count == 2)
        #expect(doc.needsYou[0].tag == "W2")
        #expect(doc.needsYou[0].sender == "Editor")
        #expect(doc.needsYou[0].text == "review due 10/15")
        #expect(doc.needsYou[1].sender == "★ Sender")

        #expect(doc.counts.count == 4)
        #expect(doc.counts[3] == CountsRow(label: "Work-Google-Scholar", unread: "250", read: "650"))
        #expect(doc.countsNotes == ["N other labels: all read."])

        #expect(doc.sections.map(\.name) == ["Inbox", "Work", "Promotions/Forums"])
        #expect(doc.sections[0].detail == "N threads, M unread")
        #expect(doc.sections[0].groups.map(\.kind) == [.unread, .read])
        #expect(doc.sections[1].groups.map(\.kind) == [.read])
        #expect(doc.items.map(\.tag) == ["I1", "I2", "W1", "W2", "P1"])

        let i1 = try #require(doc.item(tag: "I1"))
        #expect(i1.threadId == "18f3a2b4c5d6e701")
        #expect(i1.subject == "Subject")
        #expect(i1.from == "★ Sender · 10/7")
        #expect(i1.priorityMarker == "★")
        #expect(i1.summary == "One-line gist; details not in preview.")
        #expect(i1.labels == ["Inbox"])
        #expect(i1.suggestion?.checked == false)
        #expect(i1.notes?.text == "")
        #expect(!i1.hasDirections)

        let i2 = try #require(doc.item(tag: "I2"))
        #expect(i2.notes?.text == "file to Work-Admin instead")
        #expect(i2.hasDirections)

        let w1 = try #require(doc.item(tag: "W1"))
        #expect(w1.labels == ["Work", "Work-Projects", "Starred"])
        #expect(w1.suggestion?.checked == true)
        #expect(w1.summary == "One-line gist. *(partial thread)*")

        let w2 = try #require(doc.item(tag: "W2"))
        #expect(w2.reminders.count == 1)
        #expect(w2.reminders[0].text == #""Submit ICWSM review" on 10/13 in Reviews (due 10/15)"#)

        #expect(doc.itemsWithDirections.map(\.tag) == ["I2", "W1"])

        #expect(doc.done.count == 1)
        #expect(doc.done[0].tag == "I3")
        #expect(doc.done[0].sender == "Sender")
        #expect(doc.done[0].threadId == "18f3a2b4c5d6e706")
        #expect(doc.done[0].outcome == "filed to Work-Admin, marked read (10/7)")
    }

    /// Files written before the link fix put the address in the path; their items must still parse.
    @Test func threadIdFromCurrentAndOldLinks() throws {
        for url in [
            "https://mail.google.com/mail/?authuser=you@example.com#all/1a0b1fde4442feec",
            "https://mail.google.com/mail/u/you@example.com/#all/1a0b1fde4442feec",
            "https://mail.google.com/mail/u/0/#inbox/1a0b1fde4442feec",
        ] {
            #expect(SummaryParser.threadId(from: try #require(URL(string: url))) == "1a0b1fde4442feec")
        }
    }

    @Test func roundTripsExactly() throws {
        for text in [try fixture("summary-template.md"), crlfSample, noTrailingNewline, ""] {
            #expect(SummaryParser.parse(text).text == text)
        }
    }

    @Test func handlesEscapesUppercaseTicksTwoRemindersAndStatusLines() throws {
        let text = """
            # Inbox summary

            ## Work (1 threads, 0 unread)

            ### Read

            #### W1 · [Re: \\[ICWSM\\] camera ready](\(link)abc123)

            **From:** You · 10/8\\
            **Summary:** Done.\\
            **Labels:** `Work`

            - [X] **Suggestion:** Leave for now — deadline.
            - [ ] **Reminder:** "Submit" on 10/13 in Reviews
            - [x] **Reminder:** "Submit CFP" on 10/20 in Deadlines (due 10/25)
            - **Notes:**
            - ✗ reminder failed; ✓ removed Work (10/8)

            ## Inbox (0 threads, 0 unread)
            """
        let doc = SummaryParser.parse(text)
        let w1 = try #require(doc.item(threadId: "abc123"))
        #expect(w1.subject == "Re: [ICWSM] camera ready")
        #expect(w1.suggestion?.checked == true)
        #expect(w1.reminders.map(\.ordinal) == [0, 1])
        #expect(w1.reminders.map(\.checked) == [false, true])
        #expect(w1.notes?.text == "")
        #expect(w1.statusLines == [StatusLine(lineIndex: 16, text: "reminder failed; ✓ removed Work (10/8)", isFailure: true)])
        // An empty section still shows up.
        #expect(doc.sections.map(\.name) == ["Work", "Inbox"])
        #expect(doc.sections[1].itemCount == 0)
    }

    @Test func unknownFormatWarnsInsteadOfFailing() {
        let legacy = """
            Some notes
            1. **Sender** · Subject <!-- thread:abc -->
            """
        let doc = SummaryParser.parse(legacy)
        #expect(doc.isUnrecognized)
        #expect(doc.items.isEmpty)

        let missingLink = """
            # Inbox summary
            ## Work (1 threads)
            #### W1 · Subject without link
            """
        let doc2 = SummaryParser.parse(missingLink)
        #expect(doc2.items.isEmpty)
        #expect(doc2.warnings.count == 1)
    }

    private var crlfSample: String {
        "# Inbox summary\r\n\r\n## Work (1)\r\n\r\n#### W1 · [S](\(link)t1)\r\n\r\n- [ ] **Suggestion:** x\r\n- **Notes:** \r\n"
    }

    private var noTrailingNewline: String {
        "# Inbox summary\n\n## Work (1)\n\n#### W1 · [S](\(link)t1)\n\n- [ ] **Suggestion:** x\n- **Notes:** hi"
    }
}

@Suite struct SummaryPatcherTests {
    @Test func tickChangesExactlyOneCharacter() throws {
        let original = try fixture("summary-template.md")
        let (patched, conflicts) = SummaryPatcher.apply(
            [.setChecked(threadId: "18f3a2b4c5d6e705", kind: .reminder, ordinal: 0, from: false, to: true)],
            to: original
        )
        #expect(conflicts.isEmpty)
        let a = Array(original), b = Array(patched)
        #expect(a.count == b.count)
        let diffs = zip(a, b).enumerated().filter { $0.element.0 != $0.element.1 }
        #expect(diffs.count == 1)
        #expect(diffs.first?.element.1 == "x")
        #expect(SummaryParser.parse(patched).item(tag: "W2")?.reminders.first?.checked == true)
    }

    @Test func untickWritesSpace() throws {
        let original = try fixture("summary-template.md")
        let (patched, _) = SummaryPatcher.apply(
            [.setChecked(threadId: "18f3a2b4c5d6e703", kind: .suggestion, ordinal: 0, from: true, to: false)],
            to: original
        )
        #expect(patched.contains("- [ ] **Suggestion:** Remove Work (already in Work-Projects)"))
    }

    @Test func notesEditChangesOneLine() throws {
        let original = try fixture("summary-template.md")
        let (patched, conflicts) = SummaryPatcher.apply(
            [.setNotes(threadId: "18f3a2b4c5d6e701", from: "", to: "reply\nsaying yes  ")],
            to: original
        )
        #expect(conflicts.isEmpty)
        let before = original.components(separatedBy: "\n"), after = patched.components(separatedBy: "\n")
        #expect(before.count == after.count)
        let changed = zip(before, after).filter { $0 != $1 }
        #expect(changed.count == 1)
        #expect(changed.first?.1 == "- **Notes:** reply saying yes")
    }

    @Test func clearingNotesKeepsTrailingSpace() throws {
        let original = try fixture("summary-template.md")
        let (patched, _) = SummaryPatcher.apply(
            [.setNotes(threadId: "18f3a2b4c5d6e702", from: "file to Work-Admin instead", to: "")], to: original
        )
        #expect(SummaryParser.parse(patched).item(tag: "I2")?.notes?.text == "")
        #expect(patched.components(separatedBy: "\n").contains("- **Notes:** "))
    }

    @Test func preservesCRLF() {
        let text = "# Inbox summary\r\n## Work (1)\r\n#### W1 · [S](\(link)t1)\r\n- [ ] **Suggestion:** x\r\n- **Notes:** \r\n"
        let (patched, _) = SummaryPatcher.apply(
            [.setChecked(threadId: "t1", kind: .suggestion, ordinal: 0, from: false, to: true),
             .setNotes(threadId: "t1", from: "", to: "ok")], to: text)
        #expect(patched == text.replacingOccurrences(of: "[ ]", with: "[x]")
            .replacingOccurrences(of: "- **Notes:** \r", with: "- **Notes:** ok\r"))
    }

    /// Claude rewrote the file: tags renumbered, I1 moved to Read, I2 moved to Done.
    @Test func rebasesOntoRewrittenFile() throws {
        let rewritten = """
            # Inbox summary

            Updated Thu 10/8, 9:00 am.

            ## Inbox (2 threads, 0 unread)

            ### Read

            #### I1 · [New thread](\(link)ffff)

            - [ ] **Suggestion:** Read it — new.
            - **Notes:**

            #### I2 · [Subject](\(link)18f3a2b4c5d6e701)

            **From:** ★ Sender · 10/7\\
            **Summary:** Updated gist.\\
            **Labels:** `Inbox`

            - [ ] **Suggestion:** Read it — Tier 1 sender.
            - **Notes:**

            ## Done

            - ✓ **I2** · Bank · [Your statement is ready](\(link)18f3a2b4c5d6e702) — filed (10/8)
            """
        let edits: [SummaryEdit] = [
            .setChecked(threadId: "18f3a2b4c5d6e701", kind: .suggestion, ordinal: 0, from: false, to: true),
            .setNotes(threadId: "18f3a2b4c5d6e701", from: "", to: "do it"),
            .setNotes(threadId: "18f3a2b4c5d6e702", from: "file to Work-Admin instead", to: "never mind"),
        ]
        let (patched, conflicts) = SummaryPatcher.apply(edits, to: rewritten)
        let item = try #require(SummaryParser.parse(patched).item(threadId: "18f3a2b4c5d6e701"))
        #expect(item.tag == "I2")
        #expect(item.suggestion?.checked == true)
        #expect(item.notes?.text == "do it")
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.tag == nil)  // moved to Done, so it's gone from the sections
    }

    @Test func reportsConflictWhenTargetChanged() throws {
        let original = try fixture("summary-template.md")
        // The user's base had I2's notes empty, but the file now says something else.
        let (patched, conflicts) = SummaryPatcher.apply(
            [.setNotes(threadId: "18f3a2b4c5d6e702", from: "", to: "mine")], to: original
        )
        #expect(patched == original)
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.tag == "I2")
    }

    @Test func alreadyAppliedEditIsNotAConflict() throws {
        let original = try fixture("summary-template.md")
        let (patched, conflicts) = SummaryPatcher.apply(
            [.setChecked(threadId: "18f3a2b4c5d6e703", kind: .suggestion, ordinal: 0, from: false, to: true)],
            to: original
        )
        #expect(conflicts.isEmpty)
        #expect(patched == original)
    }
}

@Suite struct LabelNamesTests {
    @Test func readsListAndTableFormsAndHumanizes() {
        let md = """
            | Inbox | Label ID | What lands here |
            |---|---|---|
            | Work | `Label_111` | Forwarded |

            - `Work-Admin` (`Label_222`): University administration.
            - `Personal-Delivery/Receipts/Bills` (`Label_333`): Receipts.
            """
        let labels = LabelNames(claudeLocalMarkdown: md)
        #expect(labels.names == ["Label_111": "Work", "Label_222": "Work-Admin", "Label_333": "Personal-Delivery/Receipts/Bills"])
        #expect(labels.humanize(#"{"addLabelIds":["Label_222","INBOX"],"removeLabelIds":["Label_999"]}"#)
            == #"{"addLabelIds":["Work-Admin","INBOX"],"removeLabelIds":["a label"]}"#)
    }
}

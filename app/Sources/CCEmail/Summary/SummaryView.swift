import CCEmailCore
import SwiftUI

/// `inbox-summary.md` as a checklist: tick suggestions and reminders, write notes,
/// then "Apply my notes" hands them to Claude.
struct SummaryView: View {
    @Environment(AppState.self) private var app
    @State private var showDone = false

    private var store: SummaryStore { app.summary }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            banners
            content
        }
        .navigationTitle("Summary")
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            if let updated = store.document?.updatedLine {
                Text(Self.shortUpdated(updated))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Button("Refresh", systemImage: "arrow.clockwise") { store.refresh() }
                .fixedSize()
                .help("Run /summary to rebuild the file from your inboxes")
                .disabled(app.launchContext == nil)
            let count = store.document?.itemsWithDirections.count ?? 0
            Button("Apply Notes (\(count))") { store.applyNotes() }
                .fixedSize()
                .buttonStyle(.borderedProminent)
                .help("Tell Claude you've updated the file. It shows what it will change and waits for your yes.")
                .disabled(count == 0 || store.isLocked || app.launchContext == nil)
                .keyboardShortcut("r", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var banners: some View {
        if store.isLocked {
            Banner(icon: "lock", text: "Claude is working, and may rewrite this file. Editing resumes when it finishes.")
        }
        if let error = store.saveError {
            Banner(icon: "exclamationmark.triangle", text: error, tint: .orange)
        }
        if !store.conflicts.isEmpty {
            Banner(
                icon: "exclamationmark.arrow.triangle.2.circlepath",
                text: "Some edits weren't saved because the file changed: "
                    + store.conflicts.map { "\($0.tag ?? "an email that's gone") (\($0.reason.lowercased().dropLast()))" }
                        .joined(separator: "; ") + ".",
                tint: .orange,
                action: ("Dismiss", store.dismissConflicts)
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        if !store.fileExists {
            ContentUnavailableView {
                Label("No summary yet", systemImage: "tray")
            } description: {
                Text("Run /summary to build inbox-summary.md from your inboxes.")
            } actions: {
                Button("Run /summary") { store.refresh() }.disabled(app.launchContext == nil)
            }
        } else if let doc = store.document, doc.isUnrecognized {
            VStack(alignment: .leading, spacing: 8) {
                Banner(icon: "questionmark.circle", text: "This file isn't in the format the app expects. Run /summary to rebuild it.")
                ScrollView {
                    Text(doc.text).font(.system(.callout, design: .monospaced)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding()
                }
            }
        } else if let doc = store.document {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !doc.needsYou.isEmpty {
                            NeedsYouBox(lines: doc.needsYou, doc: doc) { threadId in
                                withAnimation { proxy.scrollTo(threadId, anchor: .top) }
                            }
                        }
                        if !doc.counts.isEmpty {
                            CountsBox(rows: doc.counts, notes: doc.countsNotes)
                        }
                        ForEach(doc.sections) { section in
                            SectionView(section: section, locked: store.isLocked)
                        }
                        if !doc.done.isEmpty {
                            DisclosureGroup("Done (\(doc.done.count))", isExpanded: $showDone) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(doc.done) { DoneRow(line: $0) }
                                }
                                .padding(.top, 6)
                            }
                            .font(.headline)
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: 860, alignment: .leading)
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    /// "Updated Thu 10/8, 5:09 pm. For each email, …" → "Updated Thu 10/8, 5:09 pm"
    static func shortUpdated(_ line: String) -> String {
        guard let dot = line.range(of: ". ") else { return line }
        return String(line[..<dot.lowerBound])
    }
}

private struct SectionView: View {
    let section: SummarySection
    let locked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(section.name).font(.title2.bold())
                if let detail = section.detail {
                    Text(detail).foregroundStyle(.secondary)
                }
            }
            if section.itemCount == 0 {
                Text("Nothing left here.").foregroundStyle(.tertiary)
            }
            ForEach(section.groups) { group in
                if group.kind != .ungrouped {
                    Text(group.kind.rawValue.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
                ForEach(group.items) { item in
                    SummaryItemRow(item: item, locked: locked).id(item.threadId)
                }
            }
        }
    }
}

struct SummaryItemRow: View {
    @Environment(AppState.self) private var app
    let item: SummaryItem
    let locked: Bool
    @State private var notes = ""
    @FocusState private var notesFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.tag)
                    .font(.caption.monospaced().bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary, in: Capsule())
                if let url = item.url {
                    Link(destination: url) {
                        Text(item.subject).font(.headline).multilineTextAlignment(.leading)
                    }
                    .help("Open in Gmail")
                } else {
                    Text(item.subject).font(.headline)
                }
            }
            VStack(alignment: .leading, spacing: 3) {
                if let from = item.from {
                    Text(from).font(.callout)
                }
                if let summary = item.summary {
                    InlineText(summary).font(.callout).foregroundStyle(.secondary)
                }
                if !item.labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(item.labels, id: \.self) { label in
                            Text(label)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.blue.opacity(0.1), in: Capsule())
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(item.actions) { action in
                    Toggle(isOn: Binding(
                        get: { action.checked },
                        set: { app.summary.setChecked(item, action: action, to: $0) }
                    )) {
                        (Text("\(action.kind.rawValue): ").bold() + Text(InlineText.attributed(action.text)))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .toggleStyle(.checkbox)
                }
                ForEach(item.statusLines) { status in
                    Label(status.text, systemImage: status.isFailure ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(status.isFailure ? .red : .green)
                }
                if item.notes != nil {
                    TextField("Notes for Claude, e.g. “file to Work-Admin instead”", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .focused($notesFocused)
                        .onChange(of: notes) { _, value in
                            if notesFocused { app.summary.setNotes(item, to: value) }
                        }
                        .onSubmit { app.summary.save() }
                }
            }
            .disabled(locked)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(item.hasDirections ? Color.accentColor.opacity(0.6) : Color.clear, lineWidth: 1.5)
        )
        .onAppear { notes = item.notes?.text ?? "" }
        .onChange(of: item.notes?.text) { _, value in
            // Don't overwrite what the user is typing; pick up changes from disk otherwise.
            if !notesFocused { notes = value ?? "" }
        }
        .onChange(of: notesFocused) { _, focused in
            if !focused { app.summary.save() }
        }
    }
}

private struct NeedsYouBox: View {
    let lines: [NeedsYouLine]
    let doc: SummaryDocument
    let jump: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Needs you").font(.headline)
            ForEach(lines) { line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let tag = line.tag, let item = doc.item(tag: tag) {
                        Button(tag) { jump(item.threadId) }
                            .buttonStyle(.link)
                            .font(.callout.monospaced().bold())
                    } else if let tag = line.tag {
                        Text(tag).font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                    if let sender = line.sender {
                        Text(sender).font(.callout.bold())
                    }
                    InlineText(line.text).font(.callout)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CountsBox: View {
    let rows: [CountsRow]
    let notes: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 4) {
                GridRow {
                    Text("Label").gridColumnAlignment(.leading)
                    Text("Unread")
                    Text("Read")
                }
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                ForEach(rows) { row in
                    GridRow {
                        Text(row.label).gridColumnAlignment(.leading)
                        Text(row.unread).monospacedDigit()
                        Text(row.read).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
            ForEach(notes, id: \.self) { Text($0).font(.caption).foregroundStyle(.secondary) }
        }
    }
}

private struct DoneRow: View {
    let line: DoneLine

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "checkmark").foregroundStyle(.green)
            if let tag = line.tag { Text(tag).font(.callout.monospaced()) }
            if let subject = line.subject {
                if let url = line.url {
                    Link(subject, destination: url).font(.callout)
                } else {
                    Text(subject).font(.callout)
                }
            }
            Text(line.outcome).font(.callout).foregroundStyle(.secondary)
        }
        .fontWeight(.regular)
    }
}

struct Banner: View {
    let icon: String
    let text: String
    var tint: Color = .secondary
    var action: (String, () -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon).foregroundStyle(tint)
            // No vertical fixedSize: banners sit outside a scroll view, and a fixed-height text
            // would claim an enormous minimum height when the window measures it narrow.
            Text(text).font(.callout).lineLimit(3)
            Spacer(minLength: 0)
            if let action {
                Button(action.0, action: action.1).controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(tint.opacity(0.08))
    }
}

import CCEmailCore
import SwiftUI

/// Claude Code asking to run a tool that isn't pre-allowed (a reminder, a send, a trash, …).
/// The sheet shows exactly what will run. Nothing is approved without a click.
struct PermissionSheet: View {
    let conversation: Conversation
    let request: PermissionRequest
    let labels: LabelNames

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .font(.title)
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text("in “\(conversation.title)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let description = request.description, !description.isEmpty {
                Text(labels.humanize(Self.clean(description)))
            }
            if let reason = request.decisionReason, !reason.isEmpty {
                Text(labels.humanize(Self.clean(reason)))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ScrollView {
                Text(inputText)
                    .font(.system(.callout, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
            }
            .frame(minHeight: 60, maxHeight: 260)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

            HStack {
                Button("Deny", role: .cancel) { conversation.deny(request) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if !request.suggestions.isEmpty && !request.suppressAlwaysAllow {
                    Button("Allow for This Conversation") { conversation.allow(request, forConversation: true) }
                        .help("Allow similar calls until this conversation's Claude Code process ends. Nothing is written to your settings.")
                }
                Button("Allow Once") { conversation.allow(request) }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 520)
        .interactiveDismissDisabled()
    }

    private var title: String {
        if let title = request.title, !title.isEmpty { return labels.humanize(Self.clean(title)) }
        return "Allow \(ToolDisplay.name(request.displayName ?? request.toolName))?"
    }

    private var inputText: String {
        if let command = request.input["command"]?.stringValue {
            return labels.humanize(command)
        }
        return labels.humanize(request.input.serialized(sortedKeys: true, pretty: true))
    }

    /// The CLI may include ANSI colour codes in these strings.
    static func clean(_ text: String) -> String {
        text.replacing(#/\x{1B}\[[0-9;]*[A-Za-z]/#, with: "")
    }
}

/// AskUserQuestion: Claude asking the user to choose (used by /scholar-digest and /contacts).
struct QuestionSheet: View {
    let conversation: Conversation
    let request: PermissionRequest

    private struct Question: Identifiable {
        var id: String { text }
        var text: String
        var header: String
        var options: [(label: String, description: String)]
        var multiSelect: Bool
    }

    @State private var single: [String: String] = [:]
    @State private var multi: [String: Set<String>] = [:]
    @State private var other: [String: String] = [:]

    private var questions: [Question] {
        (request.input["questions"]?.arrayValue ?? []).compactMap { q in
            guard let text = q["question"]?.stringValue else { return nil }
            let options = (q["options"]?.arrayValue ?? []).compactMap { o -> (String, String)? in
                guard let label = o["label"]?.stringValue else { return nil }
                return (label, o["description"]?.stringValue ?? "")
            }
            return Question(text: text, header: q["header"]?.stringValue ?? "",
                            options: options, multiSelect: q["multiSelect"]?.boolValue ?? false)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Claude has a question").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(questions) { question in
                        questionView(question)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 460)
            HStack {
                Button("Skip", role: .cancel) { conversation.dismissQuestion(request) }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Submit") { conversation.answer(request, answers: answers) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!allAnswered)
            }
        }
        .padding(20)
        .frame(width: 560)
        .interactiveDismissDisabled()
    }

    @ViewBuilder
    private func questionView(_ q: Question) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !q.header.isEmpty {
                Text(q.header.uppercased()).font(.caption2.bold()).foregroundStyle(.secondary)
            }
            Text(q.text).font(.body.weight(.medium))
            ForEach(q.options, id: \.label) { option in
                Button {
                    if q.multiSelect {
                        var set = multi[q.text, default: []]
                        if set.contains(option.label) { set.remove(option.label) } else { set.insert(option.label) }
                        multi[q.text] = set
                    } else {
                        single[q.text] = option.label
                        other[q.text] = nil
                    }
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: isSelected(q, option.label)
                              ? (q.multiSelect ? "checkmark.square.fill" : "largecircle.fill.circle")
                              : (q.multiSelect ? "square" : "circle"))
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                            if !option.description.isEmpty {
                                Text(option.description).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            TextField("Other…", text: Binding(
                get: { other[q.text] ?? "" },
                set: { value in
                    other[q.text] = value
                    if !value.isEmpty, !q.multiSelect { single[q.text] = nil }
                }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    private func isSelected(_ q: Question, _ label: String) -> Bool {
        q.multiSelect ? multi[q.text, default: []].contains(label) : single[q.text] == label
    }

    private var answers: [String: String] {
        var result: [String: String] = [:]
        for q in questions {
            var parts: [String] = q.multiSelect
                ? q.options.map(\.label).filter { multi[q.text, default: []].contains($0) }
                : [single[q.text]].compactMap { $0 }
            let typed = (other[q.text] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !typed.isEmpty { parts.append(typed) }
            if parts.isEmpty, q.multiSelect { parts = ["None of these"] }
            result[q.text] = parts.joined(separator: ", ")
        }
        return result
    }

    private var allAnswered: Bool {
        answers.count == questions.count && answers.values.allSatisfy { !$0.isEmpty }
    }
}

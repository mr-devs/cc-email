import CCEmailCore
import SwiftUI

/// Model picker plus context, session and weekly usage, like a Claude Code status line.
struct UsageFooter: View {
    @Environment(AppState.self) private var app
    /// The conversation whose context to show, if any.
    let conversation: Conversation?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                ModelPicker()
                Spacer(minLength: 0)
                if app.usage.refreshing {
                    ProgressView().controlSize(.mini)
                }
                Button("Refresh Usage", systemImage: "arrow.clockwise") { app.refreshUsage() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .help("Ask Claude Code for current usage (no model call)")
                    .disabled(app.launchContext == nil)
            }
            TimelineView(.periodic(from: .now, by: 30)) { timeline in
                Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 3) {
                    UsageRow(
                        label: "Context",
                        percent: conversation?.contextUsage?.percentage,
                        detail: conversation?.contextUsage.map { "\(Self.tokens($0.totalTokens)) of \(Self.tokens($0.maxTokens))" },
                        help: "How full this conversation's context window is"
                    )
                    UsageRow(
                        label: "Session",
                        percent: app.usage.plan?.session?.percent,
                        detail: app.usage.plan?.session?.resetsAt.map { Self.countdown(to: $0, now: timeline.date) },
                        help: stalenessHelp(now: timeline.date, window: "5-hour")
                    )
                    UsageRow(
                        label: "Weekly",
                        percent: app.usage.plan?.weekly?.percent,
                        detail: app.usage.plan?.weekly?.resetsAt.map(Self.weekday),
                        help: stalenessHelp(now: timeline.date, window: "7-day"),
                        isWeekly: true
                    )
                }
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private func stalenessHelp(now: Date, window: String) -> String {
        guard let fetched = app.usage.plan?.fetchedAt else { return "Your plan's \(window) limit. Not loaded yet." }
        let minutes = Int(now.timeIntervalSince(fetched) / 60)
        return "Your plan's \(window) limit, as reported by Claude Code \(minutes < 1 ? "just now" : "\(minutes) min ago")."
    }

    static func tokens(_ n: Int) -> String {
        if n >= 1_000_000 { return n % 1_000_000 == 0 ? "\(n / 1_000_000)M" : String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return "\(n / 1_000)K" }
        return "\(n)"
    }

    /// "resets in 3h 51m"
    static func countdown(to date: Date, now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "resetting…" }
        let d = seconds / 86400, h = (seconds % 86400) / 3600, m = (seconds % 3600) / 60
        if d > 0 { return "resets in \(d)d \(h)h" }
        return h > 0 ? "resets in \(h)h \(m)m" : "resets in \(m)m"
    }

    /// "resets Mon 5:59 AM"
    static func weekday(_ date: Date) -> String {
        "resets " + date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
    }
}

private struct UsageRow: View {
    let label: String
    let percent: Double?
    let detail: String?
    let help: String
    var isWeekly = false

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            UsageBar(fraction: (percent ?? 0) / 100, color: color)
                .frame(width: 70, height: 6)
            Text(percent.map { "\(Int($0.rounded()))%" } ?? "—")
                .monospacedDigit()
                .fontWeight(isWeekly && (percent ?? 0) >= 90 ? .bold : .regular)
                .foregroundStyle(percent == nil ? Color.secondary : color)
                .gridColumnAlignment(.trailing)
            Text(detail ?? "")
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(help)
    }

    /// Same thresholds as the terminal status line: green, yellow from 50%, red from 80%.
    private var color: Color {
        guard let percent else { return .secondary }
        if percent >= 80 { return .red }
        if percent >= 50 { return .yellow }
        return .green
    }
}

private struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(color)
                    .frame(width: max(0, min(1, fraction)) * geometry.size.width)
            }
        }
    }
}

/// The model for new turns. Changing it also switches running sessions.
struct ModelPicker: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Picker("Model", selection: Binding(get: { app.settings.model }, set: { app.setModel($0) })) {
            ForEach(options) { option in
                Text(option.displayName).tag(option.value)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
        // A menu picker sizes itself once; rebuild it when the list or selection changes.
        .id(options.map(\.value).joined(separator: ",") + "|" + app.settings.model)
        .help("Model for new turns in every conversation")
    }

    /// The account's models, plus the current setting if it isn't in the list.
    private var options: [ModelOption] {
        var list = app.usage.models
        if !list.contains(where: { $0.value == app.settings.model }) {
            list.insert(ModelOption(value: app.settings.model,
                                    displayName: ModelCatalog.displayName(for: app.settings.model, in: list)), at: 0)
        }
        return list
    }
}

import SwiftUI

struct TranscriptRow: View {
    let item: TranscriptItem

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(item.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            }
        case .assistant:
            MarkdownView(markdown: item.text)
        case .tool:
            ToolChip(item: item)
        case .notice:
            Label { InlineText(item.text) } icon: { Image(systemName: "info.circle") }
                .font(.callout)
                .foregroundStyle(.secondary)
        case .error:
            Label { MarkdownView(markdown: item.text) } icon: {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            .font(.callout)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

/// A compact line for a tool call, e.g. "Gmail · search threads  in:inbox".
private struct ToolChip: View {
    let item: TranscriptItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                statusIcon
                Text(ToolDisplay.name(item.toolName ?? "tool"))
                    .font(.caption.weight(.medium))
                if !item.text.isEmpty {
                    Text(item.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            if item.childCount > 0 {
                Text("\(item.childCount) step\(item.childCount == 1 ? "" : "s")"
                     + (item.toolStatus == .running ? " · \(item.childActivity ?? "")" : ""))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 20)
            }
            if let detail = item.detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
                    .padding(.leading, 20)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusIcon: some View {
        switch item.toolStatus {
        case .running:
            ProgressView().controlSize(.mini).frame(width: 14)
        case .failed:
            Image(systemName: "xmark.circle").foregroundStyle(.orange).frame(width: 14)
        default:
            Image(systemName: "checkmark.circle").foregroundStyle(.tertiary).frame(width: 14)
        }
    }
}

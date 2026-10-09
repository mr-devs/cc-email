import CCEmailCore
import SwiftUI

/// Renders Claude's Markdown replies, including the approval tables skills show before changing mail.
struct MarkdownView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(markdown).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            InlineText(text)
                .font(level <= 2 ? .title3.bold() : .headline)
                .padding(.top, 4)
        case .paragraph(let text):
            InlineText(text)
        case .listItem(let marker, let indent, let text):
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(marker.first?.isNumber == true ? marker : "•")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                InlineText(text)
            }
            .padding(.leading, CGFloat(indent) * 16)
        case .table(let header, let rows):
            TableView(header: header, rows: rows)
        case .code(_, let text):
            Text(text)
                .font(.system(.callout, design: .monospaced))
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
        case .quote(let text):
            InlineText(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    Rectangle().fill(.tertiary).frame(width: 3)
                }
        case .rule:
            Divider()
        }
    }
}

/// Inline Markdown: bold, italics, `code` and links.
struct InlineText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(Self.attributed(text))
            .fixedSize(horizontal: false, vertical: true)
    }

    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

private struct TableView: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        // Cells wrap to fit the pane. A horizontal scroll view would size the table to its
        // widest row and cut it off at the pane's edge.
        Grid(alignment: .topLeading, horizontalSpacing: 12, verticalSpacing: 6) {
            GridRow {
                ForEach(header.indices, id: \.self) { i in
                    InlineText(header[i]).font(.callout.bold())
                }
            }
            Divider()
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(header.indices, id: \.self) { c in
                        InlineText(c < rows[r].count ? rows[r][c] : "").font(.callout)
                    }
                }
                if r < rows.count - 1 { Divider().opacity(0.5) }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }
}

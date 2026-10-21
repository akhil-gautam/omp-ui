import SwiftUI
import OMPCore

/// Markdown, rendered.
struct MarkdownView: View {
    let source: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Markdown.blocks(of: source)) { block in
                switch block {
                case .heading(_, let level, let text):
                    Text(Markdown.inline(text))
                        .font(Theme.heading(level <= 2 ? 19 : 15))
                        .foregroundStyle(Theme.ink)
                        .padding(.top, level <= 2 ? 8 : 2)
                case .paragraph(_, let text):
                    Text(Markdown.inline(text))
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(_, let language, let text):
                    CodeBlock(language: language, text: text)
                case .list(_, let ordered, let items):
                    ListBlock(ordered: ordered, items: items)
                case .quote(_, let text):
                    Text(Markdown.inline(text))
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.inkDim)
                        .textSelection(.enabled)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(Theme.accent.opacity(0.5)).frame(width: 2)
                        }
                case .rule:
                    Rectangle().fill(Theme.hairlineSoft).frame(height: 1)
                case .table(_, let header, let rows):
                    TableBlock(header: header, rows: rows)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// A fenced block of code.
struct CodeBlock: View {
    let language: String?
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language?.uppercased() ?? "CODE")
                    .font(Theme.label(9))
                    .foregroundStyle(Theme.inkFaint)
                    .tracking(0.12)
                Spacer(minLength: 0)
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    copied = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.4))
                        copied = false
                    }
                } label: {
                    Text(copied ? "COPIED" : "COPY")
                        .font(Theme.label(9))
                        .foregroundStyle(copied ? Theme.accent : Theme.inkFaint)
                        .tracking(0.12)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) {
                Rectangle().fill(Theme.hairlineSoft).frame(height: 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(Highlighter.attributed(text, language: language, palette: Highlighter.darkPalette))
                    .font(Theme.code(12))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Theme.hairlineSoft, lineWidth: 1)
        }
    }
}

/// A list, with the task-list entries marked.
struct ListBlock: View {
    let ordered: Bool
    let items: [MarkdownItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let checked = item.checked {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundStyle(checked ? Theme.accent : Theme.inkFaint)
                    } else {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(Theme.body(13))
                            .foregroundStyle(Theme.inkFaint)
                            .monospacedDigit()
                    }
                    Text(Markdown.inline(item.text))
                        .font(Theme.body(13.5))
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A table.
struct TableBlock: View {
    let header: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                row(header, isHeader: true)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    self.row(row, isHeader: false)
                }
            }
            .overlay {
                Rectangle().fill(Theme.hairlineSoft).frame(width: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.hairlineSoft, lineWidth: 1)
        }
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(Markdown.inline(cell))
                    .font(isHeader ? Theme.body(12.5) : Theme.body(12.5))
                    .foregroundStyle(isHeader ? Theme.ink : Theme.inkDim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(Theme.hairlineSoft).frame(width: 1)
                    }
            }
            Spacer(minLength: 0)
        }
        .background(isHeader ? Theme.panel : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Theme.hairlineSoft).frame(height: 1)
        }
    }
}

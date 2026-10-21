import SwiftUI
import OMPCore

/// Markdown, rendered.
struct MarkdownView: View {
    @Environment(\.palette) private var palette
    let source: String
    /// The colour of the text, when it should not be the usual ink.
    var ink: Color?

    /// The colour the text is drawn in.
    private var textColour: Color { ink ?? palette.ink }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Markdown.blocks(of: source)) { block in
                switch block {
                case .heading(_, let level, let text):
                    Text(Markdown.inline(text))
                        .font(Theme.heading(level <= 2 ? 19 : 15))
                        .foregroundStyle(textColour)
                        .padding(.top, level <= 2 ? 8 : 2)
                case .paragraph(_, let text):
                    Text(Markdown.inline(text))
                        .font(Theme.body(13.5))
                        .foregroundStyle(textColour)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(_, let language, let text):
                    CodeBlock(language: language, text: text)
                case .list(_, let ordered, let items):
                    ListBlock(ordered: ordered, items: items, ink: ink)
                case .quote(_, let text):
                    Text(Markdown.inline(text))
                        .font(Theme.body(13.5))
                        .foregroundStyle(ink ?? palette.inkDim)
                        .textSelection(.enabled)
                        .padding(.leading, 12)
                        .overlay(alignment: .leading) {
                            Rectangle().fill(palette.accent.opacity(0.5)).frame(width: 2)
                        }
                case .rule:
                    Rectangle().fill(palette.hairlineSoft).frame(height: 1)
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
    @Environment(\.palette) private var palette
    let language: String?
    let text: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text(language?.uppercased() ?? "CODE")
                    .font(Theme.label(9))
                    .foregroundStyle(palette.inkFaint)
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
                        .foregroundStyle(copied ? palette.accent : palette.inkFaint)
                        .tracking(0.12)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Copy the code")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .overlay(alignment: .bottom) {
                Rectangle().fill(palette.hairlineSoft).frame(height: 1)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                Text(Highlighter.attributed(text, language: language, palette: Highlighter.darkPalette))
                    .font(Theme.code(12))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(palette.codeBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.hairlineSoft, lineWidth: 1)
        }
    }
}

/// A list, with the task-list entries marked.
struct ListBlock: View {
    @Environment(\.palette) private var palette
    let ordered: Bool
    let items: [MarkdownItem]
    /// The colour of the text, when it should not be the usual ink.
    var ink: Color?

    private var textColour: Color { ink ?? palette.ink }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    if let checked = item.checked {
                        Image(systemName: checked ? "checkmark.square.fill" : "square")
                            .font(.system(size: 12))
                            .foregroundStyle(checked ? palette.accent : palette.inkFaint)
                    } else {
                        Text(ordered ? "\(index + 1)." : "•")
                            .font(Theme.body(13))
                            .foregroundStyle(palette.inkFaint)
                            .monospacedDigit()
                    }
                    Text(Markdown.inline(item.text))
                        .font(Theme.body(13.5))
                        .foregroundStyle(textColour)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// A table.
struct TableBlock: View {
    @Environment(\.palette) private var palette
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
                Rectangle().fill(palette.hairlineSoft).frame(width: 1)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairlineSoft, lineWidth: 1)
        }
    }

    private func row(_ cells: [String], isHeader: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { _, cell in
                Text(Markdown.inline(cell))
                    .font(isHeader ? Theme.body(12.5) : Theme.body(12.5))
                    .foregroundStyle(isHeader ? palette.ink : palette.inkDim)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .overlay(alignment: .trailing) {
                        Rectangle().fill(palette.hairlineSoft).frame(width: 1)
                    }
            }
            Spacer(minLength: 0)
        }
        .background(isHeader ? palette.panel : .clear)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairlineSoft).frame(height: 1)
        }
    }
}

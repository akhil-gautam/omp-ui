import SwiftUI
import OMPCore

/// The conversation.
struct TranscriptView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    if let session = store.active {
                        if session.blocks.isEmpty {
                            GreetingView(store: store)
                        } else {
                            ForEach(session.blocks) { block in
                                BlockView(block: block)
                                    .id(block.id)
                            }
                        }
                        if let request = session.pendingRequest {
                            DialogView(request: request, store: store)
                        }
                    } else {
                        GreetingView(store: store)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: Theme.contentWidth)
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: store.active?.blocks.count) { _, _ in
                // The rows have to be laid out before the scroll means
                // anything, so the jump waits a beat.
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
                }
            }
        }
    }
}

/// The greeting, shown while there is nothing to read.
struct GreetingView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What are we building?")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(palette.ink)
            if let session = store.active {
                Text("omp is ready in \(session.project.name).")
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.inkDim)
            } else {
                Text("Add a project to give omp a place to work.")
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.inkDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 60)
    }
}

/// One entry of the transcript.
struct BlockView: View {
    @Environment(\.palette) private var palette
    let block: Block

    var body: some View {
        switch block {
        case .user(_, let text):
            // What the reader said, in a bubble of its own.
            HStack {
                Spacer(minLength: 0)
                Text(Markdown.inline(text))
                    .font(.system(size: 14))
                    .foregroundStyle(palette.ink)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .frame(maxWidth: 560, alignment: .trailing)
            }
        case .text(_, let text):
            MarkdownView(source: text)
        case .thinking(_, let text):
            // Thinking is always shown: it is the reasoning, not a summary.
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "brain")
                        .font(.system(size: 13))
                    Text("Thinking")
                        .font(.system(size: 13.5))
                }
                .foregroundStyle(palette.inkDim)
                MarkdownView(source: text, ink: palette.inkDim)
            }
        case .tool(_, let name, let args, let output, let isError, let running):
            ToolCallView(name: name, args: args, output: output, isError: isError, running: running)
        }
    }
}

/// A tool call: a card with the call at the top and its result below.
struct ToolCallView: View {
    @Environment(\.palette) private var palette
    let name: String
    let args: JSONValue?
    let output: String?
    let isError: Bool
    let running: Bool

    @State private var expanded: Bool
    @State private var hovering = false

    init(name: String, args: JSONValue?, output: String?, isError: Bool, running: Bool) {
        self.name = name
        self.args = args
        self.output = output
        self.isError = isError
        self.running = running
        // The result is shown the way a terminal shows it: open.
        _expanded = State(initialValue: true)
    }

    /// The one argument worth showing in the line itself.
    private var summary: String? {
        guard let args, !args.isNull else { return nil }
        switch name {
        case "read", "write", "edit", "notebook_edit", "apply_patch":
            return args["path"].optionalString ?? args["file_path"].optionalString
        case "bash", "shell":
            return args["command"].optionalString
        case "grep", "glob", "rg":
            return args["pattern"].optionalString
        case "web_search", "search":
            return args["query"].optionalString
        case "fetch", "web_fetch":
            return args["url"].optionalString
        default:
            return args.object.values.compactMap(\.optionalString).first
        }
    }

    /// The kind of call, in the title's voice.
    private var title: String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "terminal")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.inkDim)
                Text(title)
                    .font(.system(size: 13.5))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 8)
                if running {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 6, height: 6)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.inkFaint)
                    .rotationEffect(.degrees(expanded ? 0 : -90))
                    .opacity(hovering || expanded ? 1 : 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            }
            .onHover { hovering = $0 }

            if let summary {
                HStack(spacing: 8) {
                    Circle()
                        .fill(palette.link)
                        .frame(width: 6, height: 6)
                    Text(summary)
                        .font(.system(size: 12.5, design: .monospaced))
                        .foregroundStyle(palette.link)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 11)
            }

            if expanded {
                if let edit = EditChange(args: args) {
                    EditDiff(change: edit)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                } else if summary == nil, let args, !args.isNull {
                    // With no argument worth a line, the whole of them are
                    // shown instead.
                    Labelled(title: "ARGUMENTS", text: args.pretty)
                        .padding(.horizontal, 14)
                        .padding(.bottom, 12)
                }
                if let output, !output.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        Text(output)
                            .font(.system(size: 11.5, design: .monospaced))
                            .foregroundStyle(isError ? palette.danger : palette.inkDim)
                            .textSelection(.enabled)
                            .padding(12)
                    }
                    .frame(maxHeight: 190)
                    .background(palette.codeBackground)
                }
            }
        }
        .background(palette.ground)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.hairline, lineWidth: 1)
        }
        .help(expanded ? "Hide the result" : "Show the result")
    }
}

/// A change an editor made: the text before and the text after.
struct EditChange: Equatable {
    let path: String
    let before: String
    let after: String

    init?(args: JSONValue?) {
        guard let args else { return nil }
        let before = args["oldString"].optionalString ?? args["old_str"].optionalString
        let after = args["newString"].optionalString ?? args["new_str"].optionalString
        guard let before, let after else { return nil }
        self.before = before
        self.after = after
        self.path = args["path"].optionalString ?? args["file_path"].optionalString ?? ""
    }
}

/// The change, shown as a diff.
struct EditDiff: View {
    @Environment(\.palette) private var palette
    let change: EditChange

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(Diff.lines(from: change.before, to: change.after).enumerated()), id: \.offset) { _, line in
                HStack(alignment: .top, spacing: 0) {
                    Text(line.marker)
                        .frame(width: 16, alignment: .center)
                    Text(line.text.isEmpty ? " " : line.text)
                        .padding(.trailing, 14)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 11.5, design: .monospaced))
                .foregroundStyle(colour(for: line))
                .background(background(for: line))
            }
        }
        .padding(.vertical, 5)
        .background(palette.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.hairlineSoft, lineWidth: 1)
        }
    }

    private func colour(for line: DiffLine) -> Color {
        switch line {
        case .context: palette.inkDim
        case .removed: palette.danger
        case .added: palette.success
        }
    }

    private func background(for line: DiffLine) -> Color {
        switch line {
        case .context: .clear
        case .removed: palette.danger.opacity(0.08)
        case .added: palette.success.opacity(0.08)
        }
    }
}

/// A labelled piece of a tool call.
private struct Labelled: View {
    @Environment(\.palette) private var palette
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.inkFaint)
                .tracking(0.12)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(palette.inkDim)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.hairlineSoft, lineWidth: 1)
            }
        }
    }
}

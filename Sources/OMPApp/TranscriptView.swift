import SwiftUI
import OMPCore

/// The conversation.
struct TranscriptView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
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
                .padding(.horizontal, 24)
                .padding(.top, 22)
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
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT ARE WE BUILDING")
                .font(Theme.label(10))
                .foregroundStyle(Theme.accent)
                .tracking(0.2)
            Text(store.userName.isEmpty ? "What are we building?" : "What are we building, \(store.userName)?")
                .font(Theme.heading(30))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let session = store.active {
                Text("omp is ready in \(session.project.name).")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkDim)
            } else {
                Text("Add a project to give omp a place to work.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 60)
    }
}

/// One entry of the transcript.
struct BlockView: View {
    let block: Block

    var body: some View {
        switch block {
        case .user(_, let text):
            Text(Markdown.inline(text))
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .text(_, let text):
            MarkdownView(source: text)
        case .thinking(_, let text):
            // Thinking is always shown: it is the reasoning, not a summary.
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                    Text("THINKING")
                        .font(Theme.label(9))
                        .tracking(0.14)
                }
                .foregroundStyle(Theme.inkFaint)
                MarkdownView(source: text)
                    .foregroundStyle(Theme.inkDim)
            }
        case .tool(_, let name, let args, let output, let isError, let running):
            ToolCallView(name: name, args: args, output: output, isError: isError, running: running)
        }
    }
}

/// A tool call: one line, the way a terminal shows it, opened on demand.
struct ToolCallView: View {
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
        // A change is shown the way a terminal shows it: open.
        _expanded = State(initialValue: EditChange(args: args) != nil)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(running ? Theme.accent : (isError ? Theme.danger : Theme.inkFaint))
                        .frame(width: 5, height: 5)
                    Text(name)
                        .font(Theme.code(11.5))
                        .foregroundStyle(Theme.inkDim)
                    if let summary {
                        Text(summary)
                            .font(Theme.code(11.5))
                            .foregroundStyle(Theme.inkFaint)
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .opacity(hovering || expanded ? 1 : 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { hovering = $0 }

            if expanded {
                if let edit = EditChange(args: args) {
                    EditDiff(change: edit)
                } else if let args, !args.isNull {
                    Labelled(title: "ARGUMENTS", text: args.pretty)
                }
                if let output, !output.isEmpty {
                    Labelled(title: "RESULT", text: output)
                }
            }
        }
        .padding(.vertical, 1)
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
                .font(Theme.code(11.5))
                .foregroundStyle(colour(for: line))
                .background(background(for: line))
            }
        }
        .padding(.vertical, 5)
        .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.hairlineSoft, lineWidth: 1)
        }
    }

    private func colour(for line: DiffLine) -> Color {
        switch line {
        case .context: Theme.inkDim
        case .removed: Theme.danger
        case .added: Theme.success
        }
    }

    private func background(for line: DiffLine) -> Color {
        switch line {
        case .context: .clear
        case .removed: Theme.danger.opacity(0.08)
        case .added: Theme.success.opacity(0.08)
        }
    }
}

/// A labelled piece of a tool call.
private struct Labelled: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.label(9))
                .foregroundStyle(Theme.inkFaint)
                .tracking(0.12)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(Theme.code(11.5))
                    .foregroundStyle(Theme.inkDim)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.hairlineSoft, lineWidth: 1)
            }
        }
    }
}

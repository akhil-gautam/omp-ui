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
                        } else if let since = session.turnStarted {
                            WorkingRow(activity: WorkingRow.activity(of: session), since: since)
                                .id("working")
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

/// The sign that a turn is under way, from the moment a message is sent until
/// the turn ends, saying what omp is doing and for how long.
struct WorkingRow: View {
    @Environment(\.palette) private var palette
    let activity: String
    let since: Date

    var body: some View {
        // Drawn frame by frame only while a turn runs: a ring of light
        // circling, and a sheen passing over the words.
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 10) {
                Circle()
                    .trim(from: 0, to: 0.72)
                    .stroke(
                        AngularGradient(colors: [palette.accent.opacity(0), palette.accent], center: .center),
                        style: StrokeStyle(lineWidth: 1.7, lineCap: .round)
                    )
                    .frame(width: 13, height: 13)
                    .rotationEffect(.degrees((time * 320).truncatingRemainder(dividingBy: 360)))
                    .shadow(color: palette.accent.opacity(0.6), radius: 4)
                Text("\(activity)  ·  \(WorkingRow.elapsed(from: since, to: context.date))")
                    .font(Theme.body(12.5))
                    .monospacedDigit()
                    .foregroundStyle(WorkingRow.sheen(palette, at: time))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .glass(radius: 999)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("omp is working on your message")
    }

    /// A band of light crossing the words, once every two seconds.
    private static func sheen(_ palette: Palette, at time: TimeInterval) -> LinearGradient {
        let phase = (time / 2).truncatingRemainder(dividingBy: 1) * 1.8 - 0.4
        return LinearGradient(
            stops: [
                .init(color: palette.inkDim, location: 0),
                .init(color: palette.ink, location: 0.5),
                .init(color: palette.inkDim, location: 1),
            ],
            startPoint: UnitPoint(x: phase - 0.35, y: 0.5),
            endPoint: UnitPoint(x: phase + 0.35, y: 0.5)
        )
    }

    /// What omp is doing, read from where the turn has got to.
    static func activity(of session: ProjectSession) -> String {
        guard session.isBusy else {
            return session.status == .starting ? "Starting omp" : "Sending"
        }
        switch session.blocks.last {
        case .tool(_, let name, _, _, _, true): return "Running \(ToolCallView.title(of: name))"
        case .thinking: return "Thinking"
        case .text: return "Writing"
        default: return "Working"
        }
    }

    static func elapsed(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return seconds < 60 ? "\(seconds)s" : "\(seconds / 60)m \(String(format: "%02d", seconds % 60))s"
    }
}

/// The empty page: a lamp over it, a headline in the light, and a few ways
/// to begin.
struct GreetingView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 18) {
            if let session = store.active {
                Chip(icon: "sparkle", text: GreetingView.where(session), tint: palette.accent)
            }
            Text(store.active == nil ? "Give omp a place to work" : "What are we building?")
                .font(.system(size: 46, weight: .semibold))
                .tracking(-1.2)
                .multilineTextAlignment(.center)
                .foregroundStyle(LinearGradient(
                    colors: [palette.ink, palette.ink.opacity(0.48)],
                    startPoint: .top, endPoint: .bottom
                ))
            Text(store.active == nil
                 ? "Add a project folder and omp starts on it, picking up where its last session left off."
                 : "Ask for a change, a fix or an explanation. omp reads the code, runs the commands and shows its work here.")
                .font(.system(size: 14.5))
                .foregroundStyle(palette.inkDim)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 470)
            if store.active == nil {
                Button {
                    Task { await store.addProjectPicker() }
                } label: {
                    Text("Add a project")
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(palette.ground)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(palette.ink, in: Capsule())
                        .shadow(color: palette.glow.opacity(palette.isLight ? 0.25 : 0.35), radius: 14)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Add a project (⌘N)")
                .padding(.top, 6)
            } else {
                HStack(spacing: 12) {
                    ForEach(Starter.all) { starter in
                        StarterTile(starter: starter) { store.pendingDraft = starter.prompt }
                    }
                }
                .padding(.top, 22)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 64)
    }

    /// Where omp is, as the pill above the headline says it.
    static func `where`(_ session: ProjectSession) -> String {
        let place = session.branch.map { "\(session.project.name) · \($0)" } ?? session.project.name
        switch session.status {
        case .starting: return "Starting omp in \(place)"
        case .error: return "omp could not start in \(place)"
        case .stopped: return "omp is stopped in \(place)"
        default: return "omp is ready in \(place)"
        }
    }
}

/// A way to begin, offered on the empty page.
struct Starter: Identifiable {
    let id: String
    let symbol: String
    let title: String
    let prompt: String

    static let all = [
        Starter(id: "tour", symbol: "map", title: "Tour the\ncodebase",
                prompt: "Give me a tour of this codebase: what it does, how it is laid out, and where the important parts live."),
        Starter(id: "bug", symbol: "ant", title: "Hunt down\na bug",
                prompt: "Help me track down a bug: "),
        Starter(id: "tests", symbol: "checkmark.seal", title: "Write the\nmissing tests",
                prompt: "Find the code in this project that has no tests, and write them."),
        Starter(id: "review", symbol: "arrow.triangle.branch", title: "Review my\nchanges",
                prompt: "Review my uncommitted changes and tell me what you would change."),
    ]
}

/// One way to begin: an icon on a lit plate and a line under it, on glass.
private struct StarterTile: View {
    @Environment(\.palette) private var palette
    let starter: Starter
    let onChoose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onChoose) {
            VStack(spacing: 14) {
                IconPlate(symbol: starter.symbol, size: 36)
                Text(starter.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(hovering ? palette.ink : palette.inkDim)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 148, height: 132)
            .glass(radius: 16)
            .shadow(color: palette.glow.opacity(hovering ? (palette.isLight ? 0.18 : 0.12) : 0), radius: 18)
            .scaleEffect(hovering ? 1.03 : 1)
            .animation(.easeOut(duration: 0.18), value: hovering)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help("Start with: \(starter.prompt)")
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
                    .padding(.horizontal, 15)
                    .padding(.vertical, 9)
                    .glass(radius: 18, raised: true)
                    .frame(maxWidth: 560, alignment: .trailing)
            }
        case .text(_, let text):
            MarkdownView(source: text)
        case .thinking(_, let text):
            // Thinking is always shown: it is the reasoning, not a summary.
            VStack(alignment: .leading, spacing: 10) {
                Chip(icon: "brain", text: "Thinking")
                MarkdownView(source: text, ink: palette.inkDim)
            }
        case .tool(_, let name, let args, let output, let isError, let running):
            ToolCallView(name: name, args: args, output: output, isError: isError, running: running)
        case .failure(_, let text):
            // A turn the model could not finish says why, where it happened.
            HStack(alignment: .firstTextBaseline, spacing: 9) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 12, weight: .medium))
                VStack(alignment: .leading, spacing: 4) {
                    Text("The turn failed")
                        .font(.system(size: 13.5, weight: .medium))
                    Text(text)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.inkDim)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.danger)
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(palette.danger.opacity(0.07), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.danger.opacity(0.25), lineWidth: 1)
            }
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
        case "bash", "shell", "terminal":
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
    private var title: String { Self.title(of: name) }

    static func title(of name: String) -> String {
        name.prefix(1).uppercased() + name.dropFirst()
    }

    /// The icon for a kind of call.
    static func symbol(of name: String) -> String {
        switch name {
        case "read": "doc.text"
        case "write", "edit", "notebook_edit", "apply_patch", "ast_edit": "pencil"
        case "grep", "glob", "rg", "find", "search": "magnifyingglass"
        case "web_search", "fetch", "web_fetch", "browser": "globe"
        case "task", "agent": "person.2"
        case "eval": "curlybraces"
        case "todo", "todo_write": "checklist"
        case "ask": "questionmark.bubble"
        default: "terminal"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                IconPlate(symbol: Self.symbol(of: name), size: 22)
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 8)
                if running {
                    Circle()
                        .fill(palette.accent)
                        .frame(width: 6, height: 6)
                        .shadow(color: palette.accent, radius: 4)
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
        .glass(radius: 12)
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

import AppKit
import SwiftUI
import OMPCore

/// The composer's + menu: what can be brought into a message. Each entry
/// opens a page of its own inside the menu, with a way back.
struct ComposerMenu: View {
    /// What choosing something does to the message being written.
    enum Insertion: Equatable {
        /// Words added where the message ends: a file named, a commit.
        case mention(String)
        /// A command, which omp only reads at the start of a message.
        case command(String)
        /// A whole message, written for the reader.
        case message(String)
    }

    enum Page: String, CaseIterable, Identifiable {
        case upload, files, directories, skills, conversations, git, rules, terminal, codemaps, commands
        var id: String { rawValue }

        var title: String {
            switch self {
            case .upload: "Upload file"
            case .files: "Files"
            case .directories: "Directories"
            case .skills: "Skills"
            case .conversations: "Conversations"
            case .git: "Git"
            case .rules: "Rules"
            case .terminal: "Terminal"
            case .codemaps: "Codemaps"
            case .commands: "Slash commands"
            }
        }

        var symbol: String {
            switch self {
            case .upload: "paperclip"
            case .files: "chevron.left.forwardslash.chevron.right"
            case .directories: "folder"
            case .skills: "bolt"
            case .conversations: "bubble.left"
            case .git: "arrow.triangle.branch"
            case .rules: "book.closed"
            case .terminal: "terminal"
            case .codemaps: "map"
            case .commands: "slash.circle"
            }
        }

        var hint: String {
            switch self {
            case .upload: "Attach images, or name any other file so omp reads it"
            case .files: "Name a file in the project so omp reads it"
            case .directories: "Name a folder so omp sees what is in it"
            case .skills: "Run one of the project's skills"
            case .conversations: "Go back to an earlier conversation in this project"
            case .git: "Point at your changes, a branch or a commit"
            case .rules: "Name a rules file omp works under"
            case .terminal: "Run a command; omp keeps its output to read"
            case .codemaps: "Ask omp to map how a part of the code fits together"
            case .commands: "Start the message with one of omp's commands"
            }
        }
    }

    @Environment(\.palette) private var palette
    @Bindable var store: AppStore
    let onInsert: (Insertion) -> Void
    let onImages: ([ImageAttachment]) -> Void
    let onClose: () -> Void

    @State private var page: Page?
    @State private var query = ""
    @State private var listing: ProjectListing?
    @State private var rules: [RuleFile]?
    @State private var git: [GitReference]?
    @State private var conversations: [SessionFile]?
    @State private var command = ""
    @FocusState private var searching: Bool

    private var project: String { store.active?.project.path ?? "" }

    var body: some View {
        Group {
            if let page {
                detail(page)
                    .frame(width: 360, height: 430)
            } else {
                root
                    .frame(width: 260)
            }
        }
        .background(palette.panel)
        .background(PopoverBackground(colour: palette.panel))
    }

    // MARK: - The list of entries

    private var root: some View {
        VStack(alignment: .leading, spacing: 1) {
            entry(.upload)
            Rectangle().fill(palette.hairline).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 5)
            ForEach(Page.allCases.filter { $0 != .upload }) { page in
                entry(page)
            }
        }
        .padding(6)
    }

    private func entry(_ target: Page) -> some View {
        MenuRow(symbol: target.symbol, title: target.title, detail: nil, help: target.hint) {
            if target == .upload {
                upload()
            } else {
                query = ""
                page = target
            }
        }
    }

    // MARK: - A page

    @ViewBuilder
    private func detail(_ page: Page) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    self.page = nil
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.inkDim)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Back to the menu")
                Image(systemName: page.symbol)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.inkDim)
                Text(page.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)
            .padding(.bottom, 8)

            if page == .terminal {
                terminal
            } else {
                search
                Rectangle().fill(palette.hairline).frame(height: 1)
                rows(for: page)
            }
        }
        .task(id: page) { await load(page) }
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(palette.inkFaint)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(palette.ink)
                .focused($searching)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
        .onAppear { searching = true }
    }

    @ViewBuilder
    private func rows(for page: Page) -> some View {
        let items = self.items(for: page)
        if let items {
            if items.isEmpty {
                Text(empty(page))
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.inkFaint)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(items) { item in
                            MenuRow(symbol: item.symbol, title: item.title, detail: item.detail, help: item.help) {
                                choose(item.action)
                            }
                        }
                    }
                    .padding(6)
                }
            }
        } else {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Reading the project…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.inkFaint)
            }
            .padding(14)
            Spacer(minLength: 0)
        }
    }

    private var terminal: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("$")
                    .font(Theme.code(13))
                    .foregroundStyle(palette.accent)
                TextField("Command to run", text: $command)
                    .textFieldStyle(.plain)
                    .font(Theme.code(13))
                    .foregroundStyle(palette.ink)
                    .focused($searching)
                    .onSubmit(run)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glass(radius: 9)
            .onAppear { searching = true }
            Text("Runs in \(store.active?.project.displayPath ?? "the project"). omp keeps the output in the conversation, so the agent can read it.")
                .font(.system(size: 12))
                .foregroundStyle(palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer(minLength: 0)
                Button(action: run) {
                    Text("Run")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(palette.ground)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(palette.ink, in: Capsule())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(command.trimmingCharacters(in: .whitespaces).isEmpty)
                .help("Run the command in the project")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.top, 2)
    }

    // MARK: - What each page lists

    private struct Item: Identifiable {
        let id: String
        let symbol: String
        let title: String
        let detail: String?
        let help: String
        let action: Action
    }

    private enum Action {
        case insert(Insertion)
        case conversation(SessionFile)
    }

    /// At most this many rows are drawn; searching narrows the rest.
    private static let shown = 300

    private func items(for page: Page) -> [Item]? {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        func matches(_ fields: String?...) -> Bool {
            needle.isEmpty || fields.contains { $0?.lowercased().contains(needle) ?? false }
        }
        switch page {
        case .upload, .terminal:
            return []
        case .files:
            guard let listing else { return nil }
            return listing.files.lazy.filter { matches($0) }.prefix(Self.shown).map { path in
                Item(id: path, symbol: "doc", title: (path as NSString).lastPathComponent,
                     detail: parent(of: path), help: "Name \(path) in the message",
                     action: .insert(.mention(Mention.token(path))))
            }
        case .directories:
            guard let listing else { return nil }
            return listing.directories.lazy.filter { matches($0) }.prefix(Self.shown).map { path in
                Item(id: path, symbol: "folder", title: (path as NSString).lastPathComponent + "/",
                     detail: parent(of: path), help: "Name the \(path) folder in the message",
                     action: .insert(.mention(Mention.token(path + "/"))))
            }
        case .codemaps:
            guard let listing else { return nil }
            let whole = Item(id: "", symbol: "map", title: "The whole project", detail: nil,
                             help: "Ask omp to map the whole project", action: .insert(.message(Codemap.prompt(for: nil))))
            let folders = listing.directories.lazy.filter { matches($0) }.prefix(Self.shown).map { path in
                Item(id: path, symbol: "folder", title: (path as NSString).lastPathComponent + "/",
                     detail: parent(of: path), help: "Ask omp to map \(path)",
                     action: .insert(.message(Codemap.prompt(for: path + "/"))))
            }
            return (matches("whole project") ? [whole] : []) + folders
        case .skills, .commands:
            let commands = (store.active?.commands ?? []).filter { page == .skills ? $0.isSkill : !$0.isSkill }
            return commands.filter { matches($0.name, $0.description) }.map { command in
                let title = page == .skills ? String(command.name.dropFirst("skill:".count)) : "/\(command.name)"
                return Item(id: command.name, symbol: page == .skills ? "bolt" : "slash.circle", title: title,
                            detail: command.description ?? command.hint, help: "Start the message with /\(command.name)",
                            action: .insert(.command(command.name)))
            }
        case .conversations:
            guard let conversations else { return nil }
            return conversations.filter { matches($0.title) }.map { file in
                Item(id: file.path, symbol: "bubble.left", title: file.title,
                     detail: file.modified.formatted(.relative(presentation: .named)),
                     help: "Switch to this conversation", action: .conversation(file))
            }
        case .git:
            guard let git else { return nil }
            return git.filter { matches($0.name, $0.detail) }.map { reference in
                let symbol = switch reference.kind {
                case .changes: "plusminus"
                case .staged: "tray.full"
                case .branch: "arrow.triangle.branch"
                case .commit: "smallcircle.filled.circle"
                }
                return Item(id: reference.id, symbol: symbol, title: reference.name, detail: reference.detail,
                            help: "Point at \(reference.phrase)", action: .insert(.mention(reference.phrase)))
            }
        case .rules:
            guard let rules else { return nil }
            return rules.filter { matches($0.path) }.map { rule in
                Item(id: rule.path, symbol: "book.closed", title: shortPath(rule.path), detail: rule.scope,
                     help: "Name \(rule.path) in the message", action: .insert(.mention(Mention.token(rule.path))))
            }
        }
    }

    private func empty(_ page: Page) -> String {
        guard query.isEmpty else { return "Nothing matches." }
        switch page {
        case .skills: return "This project has no skills."
        case .commands: return "omp has not listed its commands yet."
        case .conversations: return "No conversations yet."
        case .git: return "This project is not a git repository."
        case .rules: return "No rules files were found for this project."
        default: return "This project is empty."
        }
    }

    private func load(_ page: Page) async {
        let project = self.project
        switch page {
        case .files, .directories, .codemaps:
            if listing == nil {
                listing = await Task.detached { ProjectFiles.list(in: project) }.value
            }
        case .rules:
            if rules == nil {
                rules = await Task.detached { RuleFiles.find(for: project) }.value
            }
        case .git:
            if git == nil {
                git = await Task.detached { GitReferences.list(in: project) }.value
            }
        case .conversations:
            if conversations == nil {
                conversations = await Task.detached { SessionFiles.sessions(for: project) }.value
            }
        case .upload, .skills, .terminal, .commands:
            break
        }
    }

    // MARK: - Choosing

    private func choose(_ action: Action) {
        switch action {
        case .insert(let insertion):
            onInsert(insertion)
        case .conversation(let file):
            Task { await store.openConversation(file) }
        }
        onClose()
    }

    private func run() {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        command = ""
        onClose()
        Task { await store.runInTerminal(text) }
    }

    /// Images are attached to the message; anything else is named in it, so
    /// omp reads it from where it is.
    private func upload() {
        onClose()
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.directoryURL = URL(fileURLWithPath: project)
        panel.message = "Images are attached; other files are named so omp reads them."
        guard panel.runModal() == .OK else { return }
        var images: [ImageAttachment] = []
        for url in panel.urls {
            if let image = ImageAttachment(contentsOf: url) {
                images.append(image)
            } else {
                onInsert(.mention(Mention.token(url.path)))
            }
        }
        if !images.isEmpty { onImages(images) }
    }

    private func parent(of path: String) -> String? {
        let parent = (path as NSString).deletingLastPathComponent
        return parent.isEmpty ? nil : parent
    }

    private func shortPath(_ path: String) -> String {
        if path.hasPrefix(project + "/") { return String(path.dropFirst(project.count + 1)) }
        return (path as NSString).abbreviatingWithTildeInPath
    }
}

/// One row of the menu: an icon, a name, and what it points at.
private struct MenuRow: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let title: String
    let detail: String?
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.inkDim)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 13.5))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.inkFaint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, detail == nil ? 7 : 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(hovering ? palette.raised : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(help)
    }
}

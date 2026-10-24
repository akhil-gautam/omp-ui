import AppKit
import SwiftUI
import UniformTypeIdentifiers
import OMPCore

/// The composer's + menu: what can be brought into a message. Each entry
/// opens a page of its own inside the menu, with a way back. Every list is
/// worked from the keyboard too: ↑ and ↓ move, Return chooses, Escape goes
/// back.
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
            case .conversations: "Open another conversation in this project, or start a new one; each has its own agent"
            case .git: "Point at your changes, a branch or a commit"
            case .rules: "Name a rules file omp works under"
            case .terminal: "Run a command; omp keeps its output to read"
            case .codemaps: "Ask omp to map how a part of the code fits together"
            case .commands: "Start the message with one of omp's commands"
            }
        }

        /// What the search field says on the page.
        var searchPrompt: String {
            switch self {
            case .files: "Search files"
            case .directories: "Search folders"
            case .skills: "Search skills"
            case .conversations: "Search conversations"
            case .git: "Search branches and commits"
            case .rules: "Search rules"
            case .codemaps: "Search folders to map"
            case .commands: "Search commands"
            case .upload, .terminal: "Search"
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
    /// The row the keyboard is on; the pointer moves it too.
    @State private var highlight = 0
    @State private var listing: ProjectListing?
    @State private var rules: [RuleFile]?
    @State private var git: [GitReference]?
    @State private var conversationsLoaded = false
    @State private var command = ""
    @FocusState private var focus: Focus?

    private enum Focus { case root, search, terminal }

    private var project: String { store.active?.project.path ?? "" }

    var body: some View {
        Group {
            if let page {
                detail(page)
                    .frame(width: 380, height: 440)
            } else {
                root
                    .frame(width: 260)
            }
        }
        .background(palette.panel)
        .background(PopoverBackground(colour: palette.panel))
    }

    // MARK: - The list of entries

    private var rootRows: [Row] {
        Page.allCases.map { target in
            Row(id: target.rawValue, icon: .symbol(target.symbol), title: target.title, help: target.hint,
                action: target == .upload ? .upload : .open(target))
        }
    }

    private var root: some View {
        let rows = rootRows
        return VStack(alignment: .leading, spacing: 1) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                RowView(row: row, highlighted: index == highlight) { perform(row.action) }
                    .onHover { if $0 { highlight = index } }
                if row.id == Page.upload.rawValue {
                    Rectangle().fill(palette.hairline).frame(height: 1).padding(.horizontal, 10).padding(.vertical, 5)
                }
            }
        }
        .padding(6)
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .root)
        .onAppear { focus = .root }
        .onKeyPress(.downArrow) { move(1, in: rows.count); return .handled }
        .onKeyPress(.upArrow) { move(-1, in: rows.count); return .handled }
        .onKeyPress(.return) {
            if rows.indices.contains(highlight) { perform(rows[highlight].action) }
            return .handled
        }
    }

    // MARK: - A page

    @ViewBuilder
    private func detail(_ page: Page) -> some View {
        let built = rows(for: page)
        VStack(alignment: .leading, spacing: 0) {
            header(page, count: built?.rows.filter(\.counted).count, capped: built?.capped ?? false)
            if page == .terminal {
                terminal
            } else {
                search(page, rows: built?.rows ?? [])
                Rectangle().fill(palette.hairline).frame(height: 1)
                list(page, built: built)
            }
        }
        .task(id: page) { await load(page) }
    }

    private func header(_ page: Page, count: Int?, capped: Bool) -> some View {
        HStack(spacing: 8) {
            Button(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.inkDim)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Back to the menu (Escape)")
            Image(systemName: page.symbol)
                .font(.system(size: 12))
                .foregroundStyle(palette.inkDim)
            Text(page.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
            Spacer(minLength: 0)
            if let count, page != .terminal {
                Text(capped ? "\(count)+" : "\(count)")
                    .font(Theme.label(10))
                    .foregroundStyle(palette.inkFaint)
                    .help(capped ? "The first \(count) are listed; type to find the rest" : "\(count) listed")
            }
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }

    private func search(_ page: Page, rows: [Row]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(palette.inkFaint)
            TextField(page.searchPrompt, text: $query, prompt: Text(""))
                .placeholder(page.searchPrompt, shown: query.isEmpty)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(palette.ink)
                .focused($focus, equals: .search)
                .onSubmit {
                    if rows.indices.contains(highlight) { perform(rows[highlight].action) }
                }
                .onKeyPress(.downArrow) { move(1, in: rows.count); return .handled }
                .onKeyPress(.upArrow) { move(-1, in: rows.count); return .handled }
                .onKeyPress(.escape) { back(); return .handled }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 9)
        .onAppear { focus = .search }
        .onChange(of: query) { _, _ in highlight = 0 }
    }

    @ViewBuilder
    private func list(_ page: Page, built: (rows: [Row], capped: Bool)?) -> some View {
        if let rows = built?.rows {
            if rows.isEmpty {
                Text(empty(page))
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.inkFaint)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Spacer(minLength: 0)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                RowView(row: row, highlighted: index == highlight) { perform(row.action) }
                                    .id(index)
                                    .onHover { if $0 { highlight = index } }
                            }
                        }
                        .padding(6)
                    }
                    .onChange(of: highlight) { _, row in
                        proxy.scrollTo(row)
                    }
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
                TextField("Command to run", text: $command, prompt: Text(""))
                    .placeholder("Command to run", shown: command.isEmpty)
                    .textFieldStyle(.plain)
                    .font(Theme.code(13))
                    .foregroundStyle(palette.ink)
                    .focused($focus, equals: .terminal)
                    .onSubmit(run)
                    .onKeyPress(.escape) { back(); return .handled }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .glass(radius: 9)
            .onAppear { focus = .terminal }
            Text("Runs in \(store.active?.project.displayPath ?? "the project"). omp keeps the output in the conversation, so the agent can read it.")
                .font(.system(size: 12))
                .foregroundStyle(palette.inkFaint)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Return runs it")
                    .font(.system(size: 11))
                    .foregroundStyle(palette.inkFaint)
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

    /// At most this many rows are drawn; searching finds the rest.
    private static let shown = 300

    /// The page's rows, best first when searching, and whether there were
    /// more than are drawn; nil while the page is still being read.
    private func rows(for page: Page) -> (rows: [Row], capped: Bool)? {
        func cap(_ rows: [Row]) -> (rows: [Row], capped: Bool) {
            (Array(rows.prefix(Self.shown)), rows.count > Self.shown)
        }
        let searching = !query.trimmingCharacters(in: .whitespaces).isEmpty
        switch page {
        case .upload, .terminal:
            return ([], false)
        case .files:
            guard let listing else { return nil }
            let files = FuzzyMatch.rank(listing.files, query: query) { [($0 as NSString).lastPathComponent, $0] }
            return cap(files.map { path in
                Row(id: path, icon: .file(path), title: (path as NSString).lastPathComponent,
                    detail: parent(of: path), detailIsPath: true, help: "Name \(path) in the message",
                    action: .insert(.mention(Mention.token(path))))
            })
        case .directories:
            guard let listing else { return nil }
            let folders = FuzzyMatch.rank(listing.directories, query: query) { [($0 as NSString).lastPathComponent, $0] }
            return cap(folders.map { path in
                Row(id: path, icon: .folder, title: (path as NSString).lastPathComponent + "/",
                    detail: parent(of: path), detailIsPath: true, help: "Name the \(path) folder in the message",
                    action: .insert(.mention(Mention.token(path + "/"))))
            })
        case .codemaps:
            guard let listing else { return nil }
            let whole = Row(id: "", icon: .symbol("map"), title: "The whole project",
                            detail: "Entry points, flows and key files, as a diagram", counted: false,
                            help: "Ask omp to map the whole project", action: .insert(.message(Codemap.prompt(for: nil))))
            let folders = FuzzyMatch.rank(listing.directories, query: query) { [($0 as NSString).lastPathComponent, $0] }
            let rows = folders.map { path in
                Row(id: path, icon: .folder, title: (path as NSString).lastPathComponent + "/",
                    detail: parent(of: path), detailIsPath: true, help: "Ask omp to map \(path)",
                    action: .insert(.message(Codemap.prompt(for: path + "/"))))
            }
            return cap((searching ? [] : [whole]) + rows)
        case .skills, .commands:
            let commands = (store.active?.commands ?? []).filter { page == .skills ? $0.isSkill : !$0.isSkill }
            let ranked = FuzzyMatch.rank(commands, query: query) { [$0.name, $0.description ?? ""] }
            return cap(ranked.map { command in
                let skill = page == .skills
                return Row(id: command.name, icon: .symbol(skill ? "bolt" : "slash.circle"),
                           title: skill ? String(command.name.dropFirst("skill:".count)) : "/\(command.name)",
                           hint: skill ? nil : command.hint, detail: command.description,
                           help: "Start the message with /\(command.name)", action: .insert(.command(command.name)))
            })
        case .conversations:
            guard conversationsLoaded, let session = store.active else { return nil }
            let fresh = Row(id: "new", icon: .symbol("plus.bubble"), title: "New conversation",
                            detail: "Its own agent; this one keeps working", counted: false, help: "Start a new conversation",
                            action: .newConversation)
            let ranked = FuzzyMatch.rank(store.conversations(in: session.project.id), query: query) { [$0.title] }
            return cap((searching ? [] : [fresh]) + ranked.map { conversation in
                let open = conversation.session === session
                return Row(id: conversation.id, icon: .symbol("bubble.left"), title: conversation.title,
                           detail: conversation.date.formatted(.relative(presentation: .named)),
                           current: open,
                           help: open ? "The conversation that is open" : "Open this conversation",
                           action: .conversation(conversation))
            })
        case .git:
            guard let git else { return nil }
            let ranked = FuzzyMatch.rank(git, query: query) { [$0.kind == .commit ? $0.detail : $0.name, $0.name] }
            return cap(ranked.map { reference in
                switch reference.kind {
                case .changes, .staged:
                    return Row(id: reference.id, icon: .symbol(reference.kind == .changes ? "plusminus" : "tray.full"),
                               title: reference.name, detail: reference.detail,
                               help: "Point at \(reference.phrase)", action: .insert(.mention(reference.phrase)))
                case .branch:
                    return Row(id: reference.id, icon: .symbol("arrow.triangle.branch"), title: reference.name,
                               detail: reference.detail, current: reference.detail == "current branch",
                               help: "Point at \(reference.phrase)", action: .insert(.mention(reference.phrase)))
                case .commit:
                    return Row(id: reference.id, icon: .symbol("smallcircle.filled.circle"), title: reference.detail,
                               detail: [reference.name, reference.when].compactMap { $0 }.joined(separator: " · "),
                               help: "Point at \(reference.phrase)", action: .insert(.mention(reference.phrase)))
                }
            })
        case .rules:
            guard let rules else { return nil }
            let ranked = FuzzyMatch.rank(rules, query: query) { [($0.path as NSString).lastPathComponent, $0.path] }
            return cap(ranked.map { rule in
                let folder = shortPath((rule.path as NSString).deletingLastPathComponent)
                return Row(id: rule.path, icon: .file(rule.path), title: (rule.path as NSString).lastPathComponent,
                           detail: (folder.isEmpty ? "" : folder + " · ") + (rule.scope == "project" ? "this project" : "everywhere"),
                           detailIsPath: true, help: "Name \(rule.path) in the message",
                           action: .insert(.mention(Mention.token(rule.path))))
            })
        }
    }

    private func empty(_ page: Page) -> String {
        guard query.isEmpty else { return "Nothing matches \u{201C}\(query)\u{201D}." }
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
            if !conversationsLoaded, let id = store.active?.project.id {
                await store.loadConversations(id)
                conversationsLoaded = true
            }
        case .upload, .skills, .terminal, .commands:
            break
        }
    }

    // MARK: - Moving and choosing

    private func move(_ step: Int, in count: Int) {
        guard count > 0 else { return }
        highlight = min(max(highlight + step, 0), count - 1)
    }

    private func back() {
        guard page != nil else { return }
        page = nil
        query = ""
        highlight = 0
        focus = .root
    }

    private func perform(_ action: Action) {
        switch action {
        case .open(let target):
            query = ""
            highlight = 0
            page = target
            return
        case .upload:
            upload()
            return
        case .insert(let insertion):
            onInsert(insertion)
        case .conversation(let file):
            Task { await store.openConversation(file) }
        case .newConversation:
            Task { await store.newConversation() }
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
        if path == project { return "" }
        if path.hasPrefix(project + "/") { return String(path.dropFirst(project.count + 1)) }
        return (path as NSString).abbreviatingWithTildeInPath
    }
}

// MARK: - Rows

/// What choosing a row does.
private enum Action {
    case open(ComposerMenu.Page)
    case upload
    case insert(ComposerMenu.Insertion)
    case conversation(Conversation)
    case newConversation
}

/// One row of a menu page.
private struct Row: Identifiable {
    enum Icon {
        case symbol(String)
        /// The icon Finder shows for a file of this kind.
        case file(String)
        case folder
    }

    let id: String
    let icon: Icon
    let title: String
    /// Said after the title, quieter: what a command takes.
    var hint: String?
    var detail: String?
    /// A path is shortened in its middle, so both ends stay; anything else
    /// at its end.
    var detailIsPath = false
    /// The one in use: the open conversation, the current branch.
    var current = false
    /// Whether it counts as one of the page's items, as an action such as
    /// "New conversation" does not.
    var counted = true
    let help: String
    let action: Action
}

private struct RowView: View {
    @Environment(\.palette) private var palette
    let row: Row
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                    .frame(width: 18, height: 18)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(row.title)
                            .font(.system(size: 13.5))
                            .foregroundStyle(palette.ink)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let hint = row.hint {
                            Text(hint)
                                .font(Theme.code(11))
                                .foregroundStyle(palette.inkFaint)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    if let detail = row.detail, !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(palette.inkFaint)
                            .lineLimit(1)
                            .truncationMode(row.detailIsPath ? .middle : .tail)
                    }
                }
                Spacer(minLength: 0)
                if row.current {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, row.detail == nil ? 7 : 5)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(highlighted ? palette.raised : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(row.help)
    }

    @ViewBuilder
    private var icon: some View {
        switch row.icon {
        case .symbol(let name):
            Image(systemName: name)
                .font(.system(size: 12.5))
                .foregroundStyle(palette.inkDim)
        case .file(let path):
            Image(nsImage: FileIcons.icon(for: path))
                .resizable()
                .aspectRatio(contentMode: .fit)
        case .folder:
            Image(nsImage: FileIcons.folder)
                .resizable()
                .aspectRatio(contentMode: .fit)
        }
    }
}

/// The icons Finder shows for kinds of file, one per kind, kept once read.
@MainActor
private enum FileIcons {
    private static var byKind: [String: NSImage] = [:]

    static func icon(for path: String) -> NSImage {
        let kind = (path as NSString).pathExtension.lowercased()
        if let icon = byKind[kind] { return icon }
        let type = UTType(filenameExtension: kind) ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        byKind[kind] = icon
        return icon
    }

    static let folder = NSWorkspace.shared.icon(for: .folder)
}

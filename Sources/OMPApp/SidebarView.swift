import SwiftUI
import OMPCore

/// The rail: the projects at the top, the app's settings at the foot.
struct SidebarView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore
    @State private var query = ""

    private var shown: [Project] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return store.projects }
        return store.projects.filter { $0.name.lowercased().contains(needle) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                newProject
                search
                list
            }
            .padding(.top, 34)

            Spacer(minLength: 0)

            foot
        }
        .frame(width: Theme.sidebarWidth)
        .background(palette.panel)
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.hairline).frame(width: 1)
        }
    }

    // MARK: - The top

    private var newProject: some View {
        Button {
            Task { await store.addProjectPicker() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .medium))
                Text("New project")
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help("Add a project (⌘N)")
    }

    private var search: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(palette.inkFaint)
            TextField("Search projects", text: $query, prompt: Text(""))
                .placeholder("Search projects", shown: query.isEmpty)
                .textFieldStyle(.plain)
                .font(.system(size: 13.5))
                .foregroundStyle(palette.ink)
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.inkFaint)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Clear the search")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                if shown.isEmpty {
                    Text(query.isEmpty ? "No projects yet." : "Nothing matches.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.inkFaint)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                }
                ForEach(shown) { project in
                    ProjectGroup(store: store, project: project)
                }
            }
            .padding(.horizontal, 8)
        }
    }

    // MARK: - The foot

    private var foot: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle().fill(palette.hairline).frame(height: 1)
            SettingsButton(store: store)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
        }
    }
}

/// A project, and under it — when it is open in the rail — its
/// conversations.
private struct ProjectGroup: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore
    let project: Project
    /// Whether every conversation is listed, not only the newest.
    @State private var showingAll = false

    /// How many conversations are listed before "Show more".
    private static let listed = 5

    private var expanded: Bool { store.expanded.contains(project.id) }

    var body: some View {
        let open = store.sessions(of: project.id)
        VStack(alignment: .leading, spacing: 1) {
            ProjectRow(
                project: project,
                status: Self.status(of: open),
                working: open.contains { $0.isWorking },
                isActive: store.activeID == project.id,
                expanded: expanded,
                onOpen: {
                    if store.activeID == project.id {
                        toggle()
                    } else {
                        Task { await store.open(project.id) }
                    }
                },
                onToggle: toggle,
                onNew: { Task { await store.newConversation(in: project.id) } },
                onStop: open.contains { $0.process != nil } ? { Task { await store.close(project.id) } } : nil,
                onRemove: { Task { await store.removeProject(project.id) } }
            )
            if expanded {
                conversations
            }
        }
        .task(id: expanded) {
            if expanded { await store.loadConversations(project.id) }
        }
    }

    private var conversations: some View {
        let all = store.conversations(in: project.id)
        let shown = showingAll ? all : Array(all.prefix(Self.listed))
        return VStack(alignment: .leading, spacing: 1) {
            SubRow(symbol: "plus", title: "New conversation",
                   help: "Start a new conversation in \(project.name), with its own agent; the others keep working") {
                Task { await store.newConversation(in: project.id) }
            }
            ForEach(shown) { conversation in
                ConversationRow(
                    conversation: conversation,
                    isActive: conversation.session != nil && conversation.session === store.active,
                    onOpen: { Task { await store.openConversation(conversation) } },
                    onStop: conversation.session.flatMap { session in
                        session.process == nil ? nil : { Task { await store.stop(session) } }
                    }
                )
            }
            if all.count > Self.listed {
                SubRow(symbol: showingAll ? "chevron.up" : "ellipsis",
                       title: showingAll ? "Show fewer" : "Show \(all.count - Self.listed) more",
                       help: showingAll ? "List only the newest conversations" : "List every conversation in \(project.name)") {
                    showingAll.toggle()
                }
            }
        }
        .padding(.leading, 14)
        .padding(.bottom, 4)
    }

    private func toggle() {
        if expanded { store.expanded.remove(project.id) } else { store.expanded.insert(project.id) }
    }

    /// What a project's conversations are doing, as one: a failure or work
    /// under way first, then a start, then whether any agent is up at all.
    static func status(of sessions: [ProjectSession]) -> SessionStatus {
        let statuses = Set(sessions.map(\.status))
        for status in [SessionStatus.error, .busy, .starting, .idle, .asleep] where statuses.contains(status) {
            return status
        }
        return .stopped
    }
}

/// One project in the list.
private struct ProjectRow: View {
    @Environment(\.palette) private var palette
    let project: Project
    let status: SessionStatus
    /// Whether any of its conversations has a turn under way.
    let working: Bool
    let isActive: Bool
    let expanded: Bool
    let onOpen: () -> Void
    let onToggle: () -> Void
    let onNew: () -> Void
    /// Stops every one of the project's agents; absent while none is running.
    let onStop: (() -> Void)?
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(palette.inkFaint)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
                    .frame(width: 12, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(expanded ? "Hide \(project.name)'s conversations" : "Show \(project.name)'s conversations")
            Image(systemName: "folder")
                .font(.system(size: 11))
                .foregroundStyle(isActive ? palette.ink : palette.inkFaint)
            Text(project.name)
                .font(.system(size: 13.5, weight: isActive ? .medium : .regular))
                .foregroundStyle(isActive ? palette.ink : palette.inkDim)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if hovering {
                HStack(spacing: 10) {
                    Button(action: onNew) {
                        Image(systemName: "plus")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.inkDim)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Start a new conversation in \(project.name)")
                    if let onStop {
                        Button(action: onStop) {
                            Image(systemName: "stop.circle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.inkFaint)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("Stop every agent in this project, which gives their memory back")
                    }
                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(palette.inkFaint)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Remove this project from the list")
                }
            } else {
                StatusDot(status: status, working: working)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 6)
        .background {
            if hovering {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.raised.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open", action: onOpen)
            Button("New Conversation", action: onNew)
            if let onStop {
                Button("Stop All Agents", action: onStop)
            }
            Divider()
            Button("Remove from List", action: onRemove)
        }
        .help("Open \(project.name)")
    }
}

/// One conversation under its project.
private struct ConversationRow: View {
    @Environment(\.palette) private var palette
    let conversation: Conversation
    let isActive: Bool
    let onOpen: () -> Void
    /// Stops the conversation's agent; absent while none is running.
    let onStop: (() -> Void)?

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(conversation.title)
                .font(.system(size: 12.5))
                .foregroundStyle(isActive ? palette.ink : palette.inkDim)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if hovering, let onStop {
                Button(action: onStop) {
                    Image(systemName: "stop.circle")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.inkFaint)
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Stop this conversation's agent, which gives its memory back")
            } else if let session = conversation.session, session.process != nil || session.status == .error || session.status == .asleep {
                StatusDot(status: session.status, working: session.isWorking)
            } else {
                Text(Self.age(conversation.date))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.inkFaint)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background {
            if isActive {
                Color.clear.glass(radius: 8, raised: true)
            } else if hovering {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(palette.raised.opacity(0.6))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open", action: onOpen)
            if let onStop {
                Button("Stop Agent", action: onStop)
            }
        }
        .help(conversation.title)
    }

    /// How long ago, in a few letters: "now", "5m", "3h", "2d", "6w".
    static func age(_ date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h" }
        if seconds < 7 * 86400 { return "\(Int(seconds / 86400))d" }
        return "\(Int(seconds / (7 * 86400)))w"
    }
}

/// A quiet action in a project's list: a new conversation, more of them.
private struct SubRow: View {
    @Environment(\.palette) private var palette
    let symbol: String
    let title: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .frame(width: 12)
                Text(title)
                    .font(.system(size: 12.5))
                Spacer(minLength: 0)
            }
            .foregroundStyle(hovering ? palette.ink : palette.inkFaint)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// The dot that says what an agent is doing.
private struct StatusDot: View {
    @Environment(\.palette) private var palette
    let status: SessionStatus
    let working: Bool

    var body: some View {
        let colour = palette.colour(for: status, working: working)
        Circle()
            .fill(colour)
            .frame(width: 6, height: 6)
            .shadow(color: status == .stopped ? .clear : colour.opacity(0.8), radius: 3)
    }
}

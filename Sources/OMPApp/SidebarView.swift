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
            TextField("Search projects", text: $query)
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
                    let status = store.sessions[project.id]?.status ?? .stopped
                    ProjectRow(
                        project: project,
                        status: status,
                        isActive: store.activeID == project.id,
                        onOpen: { Task { await store.open(project.id) } },
                        onStop: status == .stopped ? nil : { Task { await store.close(project.id) } },
                        onRemove: { Task { await store.removeProject(project.id) } }
                    )
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

/// One project in the list.
private struct ProjectRow: View {
    @Environment(\.palette) private var palette
    let project: Project
    let status: SessionStatus
    let isActive: Bool
    let onOpen: () -> Void
    /// Stops the project's omp; absent while none is running.
    let onStop: (() -> Void)?
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.system(size: 13.5))
                    .foregroundStyle(isActive ? palette.ink : palette.inkDim)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(ProjectRow.ago(project.createdAt))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.inkFaint)
            }
            Spacer(minLength: 4)
            if hovering {
                HStack(spacing: 10) {
                    if let onStop {
                        Button(action: onStop) {
                            Image(systemName: "stop.circle")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(palette.inkFaint)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("Stop this project's agent, which gives its memory back")
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
                Circle()
                    .fill(colour)
                    .frame(width: 6, height: 6)
                    .shadow(color: status == .stopped ? .clear : colour.opacity(0.8), radius: 3)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
            Divider()
            Button("Remove from List", action: onRemove)
        }
        .help("Open \(project.name)")
    }

    private var colour: Color { palette.colour(for: status) }

    /// How long ago a project was added.
    static func ago(_ date: Date) -> String {
        let seconds = Date().timeIntervalSince(date)
        if seconds < 60 { return "just now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m ago" }
        if seconds < 86400 { return "\(Int(seconds / 3600))h ago" }
        return "\(Int(seconds / 86400))d ago"
    }
}

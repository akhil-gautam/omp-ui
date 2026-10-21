import SwiftUI
import OMPCore

/// The list of projects, and what each project can do.
struct SidebarView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                projectList
            }
            .padding(.top, 18)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 0) {
                Text("CUSTOMIZATIONS")
                    .font(Theme.label(9.5))
                    .foregroundStyle(palette.inkFaint)
                    .tracking(0.14)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 8)
                customizations
            }
            .padding(.bottom, 14)
        }
        .frame(width: Theme.sidebarWidth)
        .background(palette.ground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.hairlineSoft).frame(width: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("SESSIONS")
                .font(Theme.label(9.5))
                .foregroundStyle(palette.inkFaint)
                .tracking(0.14)
            Spacer(minLength: 8)
            Button {
                Task { await store.addProjectPicker() }
            } label: {
                HStack(spacing: 5) {
                    Text("NEW")
                        .font(Theme.label(9.5))
                    Text("⌘N")
                        .font(Theme.label(9))
                        .foregroundStyle(palette.inkFaint)
                }
                .foregroundStyle(palette.inkDim)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .overlay {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(palette.hairline, lineWidth: 1)
                }
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Add a project (⌘N)")
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var projectList: some View {
        VStack(alignment: .leading, spacing: 1) {
            if store.projects.isEmpty {
                Text("No projects yet.")
                    .font(Theme.body(12))
                    .foregroundStyle(palette.inkFaint)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 4)
            }
            ForEach(store.projects) { project in
                ProjectRow(
                    project: project,
                    status: store.sessions[project.id]?.status ?? .stopped,
                    isActive: store.activeID == project.id,
                    onOpen: { Task { await store.open(project.id) } },
                    onRemove: { Task { await store.removeProject(project.id) } }
                )
            }
        }
    }

    private var customizations: some View {
        VStack(alignment: .leading, spacing: 1) {
            CustomizationRow(title: "Overview", help: "What this project is", count: nil, isActive: store.view == .overview) {
                store.view = .overview
            }
            CustomizationRow(title: "Tools", help: "The tools omp can use here", count: store.active?.inventory?.tools.count, isActive: store.view == .tools) {
                store.view = .tools
            }
            CustomizationRow(title: "Skills", help: "The skills available here", count: store.active?.inventory?.skills.count, isActive: store.view == .skills) {
                store.view = .skills
            }
            CustomizationRow(title: "Extensions", help: "The extensions loaded here", count: store.active?.inventory?.extensions.count, isActive: store.view == .extensions) {
                store.view = .extensions
            }
            CustomizationRow(title: "Prompts", help: "The prompt templates here", count: store.active?.inventory?.prompts.count, isActive: store.view == .prompts) {
                store.view = .prompts
            }
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
    let onRemove: () -> Void

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 9) {
            Circle()
                .fill(colour)
                .frame(width: 6, height: 6)
            Text(project.name)
                .font(Theme.body(12.5))
                .foregroundStyle(isActive ? palette.ink : palette.inkDim)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            if hovering {
                Button(action: onRemove) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.inkFaint)
                }
                .buttonStyle(.plain)
                .help("Remove this project")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isActive ? palette.raised : (hovering ? palette.panel : .clear))
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
        .onHover { hovering = $0 }
        .help("Open \(project.name)")
    }

    private var colour: Color {
        switch status {
        case .busy: palette.accent
        case .idle: palette.success
        case .starting: palette.accent.opacity(0.6)
        case .error: palette.danger
        case .stopped: palette.inkFaint
        }
    }
}

/// One of the project's pages.
private struct CustomizationRow: View {
    @Environment(\.palette) private var palette
    let title: String
    /// What the page holds, shown when the pointer rests on it.
    let help: String
    let count: Int?
    let isActive: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.body(12.5))
                    .foregroundStyle(isActive ? palette.ink : palette.inkDim)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(Theme.body(11))
                        .foregroundStyle(palette.inkFaint)
                }
                if isActive {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(isActive ? palette.raised : (hovering ? palette.panel : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(help)
    }
}

import SwiftUI
import OMPCore

/// The bar across the top of the window.
struct TopBarView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    private var statusLabel: String {
        guard let session = store.active else { return "NO PROJECT" }
        switch session.status {
        case .busy: return "WORKING"
        case .idle: return "READY"
        case .starting: return "STARTING"
        case .error: return "ERROR"
        case .stopped: return "STOPPED"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            arrow("chevron.left", enabled: store.canGoBack, help: "Go back") {
                Task { await store.goBack() }
            }
            arrow("chevron.right", enabled: store.canGoForward, help: "Go forward") {
                Task { await store.goForward() }
            }
            Text(store.active?.project.name ?? "omp-ui")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(palette.ink)
                .padding(.leading, 8)
                .lineLimit(1)
            Spacer(minLength: 12)
            HStack(spacing: 14) {
                Text(statusLabel)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(store.active?.isBusy == true ? palette.accent : palette.inkFaint)
                Select(
                    icon: "paintpalette",
                    items: Theme.palettes.map { theme in
                        Select.Item(id: theme.name, title: theme.name, detail: theme.isLight ? "light" : "dark")
                    },
                    selected: store.themeName,
                    placeholder: "Theme",
                    plain: true,
                    help: "The colours of the interface"
                ) { item in
                    store.themeName = item.id
                }
                .font(.system(size: 12.5))
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(palette.ground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    private func arrow(_ name: String, enabled: Bool, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(enabled ? palette.inkDim : palette.inkFaint.opacity(0.5))
                .frame(width: 22, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .disabled(!enabled)
        .help(help)
    }
}

/// The open projects, as tabs.
struct TabBarView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(store.projects) { project in
                        tab(project)
                    }
                }
                .padding(.horizontal, 8)
            }
            Button {
                Task { await store.addProjectPicker() }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.inkFaint)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Add a project (⌘N)")
            Spacer(minLength: 0)
        }
        .frame(height: 34)
        .background(palette.ground)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairline).frame(height: 1)
        }
    }

    private func tab(_ project: Project) -> some View {
        let active = store.activeID == project.id
        return HStack(spacing: 7) {
            // The tab and its close button are separate targets, so closing
            // a tab can never also open it.
            Button {
                Task { await store.open(project.id) }
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(colour(for: project))
                        .frame(width: 6, height: 6)
                    Text(project.name)
                        .font(.system(size: 12.5))
                        .foregroundStyle(active ? palette.ink : palette.inkDim)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Open \(project.name)")
            Button {
                Task { await store.close(project.id) }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.inkFaint)
                    .frame(width: 14, height: 14)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Stop this agent and close the tab")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    private func colour(for project: Project) -> Color {
        switch store.sessions[project.id]?.status ?? .stopped {
        case .busy: palette.accent
        case .idle: palette.success
        case .starting: palette.accent.opacity(0.6)
        case .error: palette.danger
        case .stopped: palette.inkFaint
        }
    }
}

/// The window's shell.
struct ContentView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(store: store)
            VStack(spacing: 0) {
                TopBarView(store: store)
                TabBarView(store: store)
                MainColumn(store: store)
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .environment(\.palette, store.palette)
        .background(store.palette.ground)
        .background {
            // The window's content runs to the top, with the traffic lights
            // drawn over it.
            WindowChrome()
        }
        .foregroundStyle(store.palette.ink)
        .overlay(alignment: .bottom) {
            if let banner = store.banner ?? store.active?.error {
                BannerView(message: banner) { store.banner = nil }
            }
        }
        .task {
            await store.restore()
        }
    }
}

/// The column that holds the transcript and the composer.
struct MainColumn: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(spacing: 0) {
            if store.view == .transcript {
                TranscriptView(store: store)
            } else {
                PanelView(store: store)
            }
            ComposerView(store: store)
        }
    }
}

/// A message along the bottom of the window.
struct BannerView: View {
    @Environment(\.palette) private var palette
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(palette.danger)
                .lineLimit(3)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.inkDim)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.panel)
        .overlay {
            Rectangle().fill(palette.danger.opacity(0.4)).frame(height: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.bottom, 14)
        .frame(maxWidth: 620)
    }
}

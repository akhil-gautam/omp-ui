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
        case .idle: return session.isWorking ? "WORKING" : "READY"
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
            Text(statusLabel)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(store.active?.isWorking == true ? palette.accent : palette.inkFaint)
                .padding(.trailing, 4)
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

/// The window's shell.
struct ContentView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(store: store)
            VStack(spacing: 0) {
                TopBarView(store: store)
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
            TranscriptView(store: store)
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

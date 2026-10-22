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
        ZStack {
            HStack(spacing: 4) {
                arrow("chevron.left", enabled: store.canGoBack, help: "Go back") {
                    Task { await store.goBack() }
                }
                arrow("chevron.right", enabled: store.canGoForward, help: "Go forward") {
                    Task { await store.goForward() }
                }
                Spacer(minLength: 0)
            }
            // The project and what its agent is doing, in a pill at the
            // centre, lit like the rest of the glass.
            HStack(spacing: 9) {
                if let session = store.active {
                    let colour = palette.colour(for: session.status, working: session.isWorking)
                    Circle()
                        .fill(colour)
                        .frame(width: 6, height: 6)
                        .shadow(color: colour.opacity(0.9), radius: 3)
                }
                Text(store.active?.project.name ?? "omp-ui")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1)
                Text(statusLabel)
                    .font(Theme.label(9.5))
                    .tracking(0.6)
                    .foregroundStyle(store.active?.isWorking == true ? palette.accent : palette.inkFaint)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .glass(radius: 999)
            .help(store.active.map { "\($0.project.displayPath) — \(statusLabel.lowercased())" } ?? "No project is open")
        }
        .padding(.horizontal, 12)
        .frame(height: 46)
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
            // The lamp over the page: bright over an empty one, faint
            // behind a conversation so it never competes with the words.
            .background(alignment: .top) {
                Spotlight(strength: store.active?.blocks.isEmpty ?? true ? 1 : 0.35)
                    .animation(.easeOut(duration: 0.6), value: store.active?.blocks.isEmpty ?? true)
            }
        }
        // The sky over everything in the window — page, cards and code alike —
        // never in the way of a click.
        .overlay {
            SkyView(settings: store.sky, working: store.active?.isWorking ?? false, preview: store.skyPreview)
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

/// The column that holds the transcript and the composer — or, on a Mac
/// without omp, the way to install it, and with nothing signed in, the way
/// to sign in.
struct MainColumn: View {
    @Bindable var store: AppStore

    private enum Page { case setup, signIn, conversation }

    private var page: Page {
        if store.ompMissing { return .setup }
        if store.showingAccounts || store.signIn != nil || store.active?.needsSignIn == true { return .signIn }
        return .conversation
    }

    var body: some View {
        Group {
            switch page {
            case .setup:
                SetupView(store: store)
            case .signIn:
                SignInView(store: store)
            case .conversation:
                VStack(spacing: 0) {
                    TranscriptView(store: store)
                    ComposerView(store: store)
                }
            }
        }
        // The name, enormous and fading as it falls, in the empty band
        // between an empty page and the composer.
        .background(alignment: .bottom) {
            if page == .conversation, store.active?.blocks.isEmpty ?? true {
                Wordmark()
                    .offset(y: -96)
                    .transition(.opacity)
            }
        }
        .clipped()
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

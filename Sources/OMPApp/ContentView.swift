import SwiftUI
import OMPCore

/// The mark omp wears.
struct BrandMark: View {
    @Environment(\.palette) private var palette
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: size * 0.18) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(spacing: 0) {
                    Rectangle().frame(width: size * 0.62, height: size * 0.16)
                    Rectangle().frame(width: size * 0.2, height: size * 0.72)
                }
            }
        }
        .foregroundStyle(palette.accent)
    }
}

/// The narrow strip on the far left.
struct IconRail: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    private let sections: [(String, String)] = [
        ("Projects", "01"),
        ("Sessions", "02"),
        ("Agents", "03"),
        ("Customizations", "04"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Button {
                store.sidebarOpen.toggle()
            } label: {
                Image(systemName: "sidebar.leading")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.inkFaint)
                    .frame(width: Theme.railWidth, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(store.sidebarOpen ? "Hide the sidebar" : "Show the sidebar")

            ForEach(sections, id: \.0) { section in
                Button {
                    switch section.0 {
                    case "Projects": store.view = .transcript
                    case "Sessions": store.view = .transcript
                    case "Agents": store.view = .transcript
                    default: store.view = .overview
                    }
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icon(for: section.0))
                            .font(.system(size: 13, weight: .regular))
                        Text(section.1)
                            .font(Theme.label(8))
                            .foregroundStyle(palette.inkFaint)
                    }
                    .frame(width: Theme.railWidth, height: 46)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .foregroundStyle(section.0 == "Projects" ? palette.accent : palette.inkFaint)
                .help(section.0)

                Rectangle()
                    .fill(palette.hairlineSoft)
                    .frame(width: 24, height: 1)
                    .padding(.bottom, 6)
            }

            Spacer(minLength: 0)
        }
        .frame(width: Theme.railWidth)
        .background(palette.ground)
        .overlay(alignment: .trailing) {
            Rectangle().fill(palette.hairlineSoft).frame(width: 1)
        }
    }

    private func icon(for section: String) -> String {
        switch section {
        case "Projects": "folder"
        case "Sessions": "text.alignleft"
        case "Agents": "person.2"
        default: "slider.horizontal.3"
        }
    }
}

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
        HStack(spacing: 10) {
            HStack(spacing: 7) {
                BrandMark(size: 13)
                Text("omp")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
            }

            Spacer(minLength: 12)

            HStack(spacing: 16) {
                Text(statusLabel)
                    .foregroundStyle(store.active?.isBusy == true ? palette.accent : palette.inkDim)
                Rectangle()
                    .fill(palette.hairline)
                    .frame(width: 1, height: 14)
                Select(
                    icon: "paintpalette",
                    items: Theme.palettes.map { palette in
                        Select.Item(id: palette.name, title: palette.name, detail: palette.isLight ? "light" : "dark")
                    },
                    selected: store.themeName,
                    placeholder: "Theme"
                ) { item in
                    store.themeName = item.id
                }
                .font(Theme.label(10))
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 46)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.hairlineSoft).frame(height: 1)
        }
    }
}

/// The window's shell.
struct ContentView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    var body: some View {
        HStack(spacing: 0) {
            IconRail(store: store)
            if store.sidebarOpen {
                SidebarView(store: store)
            }
            VStack(spacing: 0) {
                TopBarView(store: store)
                MainColumn(store: store)
            }
        }
        .environment(\.palette, store.palette)
        .background(store.palette.ground)
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
                .font(Theme.body(12))
                .foregroundStyle(palette.danger)
                .lineLimit(3)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(palette.inkDim)
            }
            .buttonStyle(.plain)
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

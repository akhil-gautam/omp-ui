import SwiftUI

/// The rail's last row: the app's settings, in a menu beside it.
struct SettingsButton: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore
    @State private var open = false
    @State private var hovering = false

    var body: some View {
        Button {
            open.toggle()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "gearshape")
                    .font(.system(size: 13))
                Text("Settings")
                    .font(.system(size: 14))
                Spacer(minLength: 0)
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(open || hovering ? palette.raised : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help("Settings")
        .popover(isPresented: $open, arrowEdge: .trailing) {
            // A popover is a window of its own, so it is handed the palette.
            SettingsMenu(store: store) { open = false }
                .environment(\.palette, store.palette)
        }
    }
}

/// The settings: the model accounts, the sky, and the theme, each shown as it
/// looks.
struct SettingsMenu: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore
    var onClose: () -> Void = {}

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Button {
                    store.showingAccounts = true
                    onClose()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "person.badge.key")
                            .font(.system(size: 13))
                            .foregroundStyle(palette.inkDim)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Accounts")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(palette.ink)
                            Text("Sign in to model providers, or out of them")
                                .font(.system(size: 11.5))
                                .foregroundStyle(palette.inkFaint)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.inkFaint)
                    }
                    .padding(10)
                    .glass(radius: 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(store.active == nil)
                .help(store.active == nil ? "Open a project first: omp signs in through it" : "See the model providers omp can sign in to")

                SkySettingsView(store: store)
                    .padding(.top, 4)

                HStack(alignment: .firstTextBaseline) {
                    Text("Theme")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.ink)
                    Spacer(minLength: 0)
                    Text(store.themeName)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.inkFaint)
                }
                .padding(.top, 4)
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(Theme.palettes, id: \.name) { theme in
                        ThemeCard(theme: theme, selected: theme.name == store.themeName) {
                            store.themeName = theme.name
                        }
                    }
                }
                .padding(2)
            }
            .padding(16)
        }
        .frame(width: 500, height: 640)
        // Sliders, switches and menus drawn light or dark with the theme,
        // not with the system.
        .environment(\.colorScheme, palette.isLight ? .light : .dark)
        .background(palette.panel)
        .background(PopoverBackground(colour: palette.panel))
    }
}

/// One theme, drawn as a small window in its own colours: the rail, a
/// message, an answer, a command and the accent.
private struct ThemeCard: View {
    @Environment(\.palette) private var palette
    let theme: Palette
    let selected: Bool
    let onChoose: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onChoose) {
            VStack(alignment: .leading, spacing: 6) {
                preview
                    .frame(height: 74)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(selected ? palette.accent : (hovering ? palette.inkFaint : palette.hairline),
                                    lineWidth: selected ? 2 : 1)
                    }
                HStack(spacing: 4) {
                    Text(theme.name)
                        .font(.system(size: 11.5, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? palette.ink : palette.inkDim)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help("Use \(theme.name), a \(theme.isLight ? "light" : "dark") theme")
    }

    private var preview: some View {
        HStack(spacing: 0) {
            // The rail.
            VStack(alignment: .leading, spacing: 4) {
                bar(theme.ink, width: 18)
                bar(theme.inkFaint, width: 14)
                bar(theme.inkFaint, width: 16)
                Spacer(minLength: 0)
            }
            .padding(6)
            .frame(width: 34)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(theme.panel)
            .overlay(alignment: .trailing) {
                Rectangle().fill(theme.hairline).frame(width: 1)
            }
            // The page.
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Spacer(minLength: 0)
                    Capsule().fill(theme.raised).frame(width: 30, height: 8)
                }
                bar(theme.inkDim, width: 52)
                bar(theme.inkDim, width: 38)
                HStack(spacing: 4) {
                    Circle().fill(theme.accent).frame(width: 5, height: 5)
                    bar(theme.link, width: 30)
                }
                Spacer(minLength: 0)
            }
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(theme.ground)
        }
    }

    private func bar(_ colour: Color, width: CGFloat) -> some View {
        Capsule().fill(colour).frame(width: width, height: 3.5)
    }
}

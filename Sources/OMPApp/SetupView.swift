import AppKit
import SwiftUI
import OMPCore

/// Shown when omp is not on this Mac: what it is, a button that installs it,
/// the other ways to, and a way to point at one installed somewhere else.
struct SetupView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Chip(icon: "shippingbox", text: "One thing first", tint: palette.accent)
                Text("omp isn\u{2019}t installed yet")
                    .font(.system(size: 44, weight: .semibold))
                    .tracking(-1.1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LinearGradient(
                        colors: [palette.ink, palette.ink.opacity(0.48)],
                        startPoint: .top, endPoint: .bottom
                    ))
                Text("omp-ui is a window onto omp, the coding agent that does the work on your Mac. Install it once and every project here can use it.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(palette.inkDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)

                install
                    .padding(.top, 8)

                if !store.installLog.isEmpty {
                    InstallLog(lines: store.installLog)
                }
                if let failure = store.installFailure {
                    Text(failure)
                        .font(.system(size: 12.5))
                        .foregroundStyle(palette.danger)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 520)
                }

                otherWays
                    .padding(.top, 10)

                Text("Next, you sign in to a model provider, right here.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.inkFaint)
                    .padding(.top, 4)
            }
            .frame(maxWidth: 620)
            .padding(.horizontal, 28)
            .padding(.top, 56)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - The installer

    private var install: some View {
        VStack(spacing: 12) {
            Button {
                Task { await store.installOMP() }
            } label: {
                HStack(spacing: 8) {
                    if store.installing {
                        ProgressView().controlSize(.small).tint(palette.ground)
                    }
                    Text(store.installing ? "Installing omp…" : "Install omp")
                        .font(.system(size: 14, weight: .medium))
                }
                .foregroundStyle(palette.ground)
                .padding(.horizontal, 22)
                .padding(.vertical, 10)
                .background(palette.ink, in: Capsule())
                .shadow(color: palette.glow.opacity(palette.isLight ? 0.25 : 0.35), radius: 16)
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(store.installing)
            .help("Runs omp's official installer: \(OMPInstaller.command)")

            CommandLine(command: OMPInstaller.command, help: "The command the button runs, from omp's README")
        }
    }

    // MARK: - The other ways

    private var otherWays: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Other ways")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.ink)
            way("With Homebrew", OMPInstaller.homebrew)
            way("With Bun", OMPInstaller.bun)
            Rectangle().fill(palette.hairline).frame(height: 1).padding(.vertical, 2)
            HStack(spacing: 10) {
                SecondaryButton(title: "Check again", symbol: "arrow.clockwise",
                                help: "Look for omp again, after installing it yourself") {
                    Task { await store.checkForOMP() }
                }
                SecondaryButton(title: "Choose omp…", symbol: "folder",
                                help: "Point the app at an omp installed somewhere it does not look") {
                    choose()
                }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(maxWidth: 520)
        .glass(radius: 14)
    }

    private func way(_ title: String, _ command: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12))
                .foregroundStyle(palette.inkFaint)
            CommandLine(command: command, help: "Run this in Terminal, then choose Check again")
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = true
        panel.showsHiddenFiles = true
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        panel.prompt = "Use"
        panel.message = "Choose the omp program."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await store.chooseOMP(at: url.path) }
    }
}

/// A command set in a pill, with a button that copies it.
private struct CommandLine: View {
    @Environment(\.palette) private var palette
    let command: String
    let help: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 10) {
            Text("$")
                .foregroundStyle(palette.accent)
            Text(command)
                .foregroundStyle(palette.ink)
                .textSelection(.enabled)
                .lineLimit(1)
            Spacer(minLength: 8)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundStyle(copied ? palette.success : palette.inkDim)
                    .frame(width: 18, height: 18)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help(copied ? "Copied" : "Copy the command")
        }
        .font(Theme.code(12.5))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .glass(radius: 9, raised: true)
        .frame(maxWidth: 520)
        .help(help)
    }
}

/// A quiet button on glass.
private struct SecondaryButton: View {
    @Environment(\.palette) private var palette
    let title: String
    let symbol: String
    let help: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .medium))
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
            }
            .foregroundStyle(hovering ? palette.ink : palette.inkDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .glass(radius: 999, raised: hovering)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// What the installer prints, as it prints it.
private struct InstallLog: View {
    @Environment(\.palette) private var palette
    let lines: [String]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        Text(line.isEmpty ? " " : line)
                            .font(Theme.code(11.5))
                            .foregroundStyle(index == 0 ? palette.inkFaint : palette.inkDim)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(index)
                    }
                }
                .padding(12)
            }
            .frame(height: 170)
            .background(palette.codeBackground)
            .glass(radius: 10)
            .frame(maxWidth: 520)
            .onChange(of: lines.count) { _, count in
                proxy.scrollTo(count - 1, anchor: .bottom)
            }
        }
    }
}

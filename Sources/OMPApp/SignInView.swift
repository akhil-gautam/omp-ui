import AppKit
import SwiftUI
import OMPCore

/// Signing in to a model provider through omp: shown on its own when omp can
/// use no model yet, and from Settings to add or remove an account.
struct SignInView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore
    @State private var query = ""

    private var firstRun: Bool { store.active?.needsSignIn ?? false }

    private var shown: [LoginProvider] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return store.providers }
        return store.providers.filter { $0.name.lowercased().contains(needle) || $0.id.contains(needle) }
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Chip(icon: "person.badge.key", text: firstRun ? "One more thing" : "Accounts", tint: palette.accent)
                Text(firstRun ? "Sign in to a model provider" : "Your model accounts")
                    .font(.system(size: 42, weight: .semibold))
                    .tracking(-1.1)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(LinearGradient(
                        colors: [palette.ink, palette.ink.opacity(0.48)],
                        startPoint: .top, endPoint: .bottom
                    ))
                Text(firstRun
                     ? "omp works through the model accounts you already have. Pick one and finish signing in in your browser."
                     : "omp signs in to these for every project. Add another, or sign out of one.")
                    .font(.system(size: 14.5))
                    .foregroundStyle(palette.inkDim)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 480)

                if let flow = store.signIn {
                    SignInFlowCard(flow: flow, store: store)
                }
                if let request = store.active?.pendingRequest {
                    // A provider that wants the code from its page asks here.
                    DialogView(request: request, store: store)
                }

                providerList
                    .padding(.top, 6)

                Text("Some providers sign in with an API key instead: omp opens the page where you get one, and you paste it here.")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.inkFaint)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)

                if !firstRun {
                    Button {
                        store.showingAccounts = false
                    } label: {
                        Text("Done")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(palette.ground)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(palette.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Back to the conversation")
                }
            }
            .frame(maxWidth: 700)
            .padding(.horizontal, 28)
            .padding(.top, 52)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .task { await store.loadProviders() }
    }

    @ViewBuilder
    private var providerList: some View {
        if store.providers.isEmpty {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Asking omp which providers it can sign in to…")
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.inkFaint)
            }
        } else {
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.inkFaint)
                    TextField("Search \(store.providers.count) providers", text: $query, prompt: Text(""))
                        .placeholder("Search \(store.providers.count) providers", shown: query.isEmpty)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .foregroundStyle(palette.ink)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .glass(radius: 999)
                .frame(maxWidth: 360)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(shown) { provider in
                        ProviderTile(provider: provider, busy: store.signIn != nil && store.signIn?.failure == nil,
                                     signingIn: store.signIn?.provider.id == provider.id && store.signIn?.failure == nil) {
                            Task { await store.signIn(to: provider) }
                        } onSignOut: {
                            Task { await store.signOut(of: provider) }
                        }
                    }
                }
            }
        }
    }
}

/// The sign-in under way: where to finish it, what omp has said, and why it
/// stopped if it did.
private struct SignInFlowCard: View {
    @Environment(\.palette) private var palette
    let flow: SignIn
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                if flow.failure == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(palette.danger)
                }
                Text(flow.failure == nil ? "Signing in to \(flow.provider.name)" : "\(flow.provider.name) did not sign in")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.ink)
                Spacer(minLength: 0)
            }
            if let failure = flow.failure {
                Text(failure)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(flow.instructions ?? (flow.url == nil ? "omp is getting the sign-in page ready…" : "Finish in your browser; this page updates when you are done."))
                    .font(.system(size: 13))
                    .foregroundStyle(palette.inkDim)
                    .fixedSize(horizontal: false, vertical: true)
                if let progress = flow.progress {
                    Text(progress)
                        .font(.system(size: 12))
                        .foregroundStyle(palette.inkFaint)
                }
                if let address = flow.url {
                    Text(address)
                        .font(Theme.code(11.5))
                        .foregroundStyle(palette.inkFaint)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
            HStack(spacing: 10) {
                if flow.failure == nil, flow.url != nil {
                    FlowButton(title: "Open the page again", help: "Open the sign-in page in your browser") {
                        store.reopenSignInPage()
                    }
                    FlowButton(title: "Copy link", help: "Copy the sign-in page's address") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(flow.url ?? "", forType: .string)
                    }
                }
                Spacer(minLength: 0)
                FlowButton(title: flow.failure == nil ? "Stop waiting" : "Close",
                           help: flow.failure == nil ? "Stop waiting for this sign-in" : "Close this message") {
                    store.dismissSignIn()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: 560)
        .glass(radius: 14, lifted: true)
    }
}

private struct FlowButton: View {
    @Environment(\.palette) private var palette
    let title: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(palette.inkDim)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .glass(radius: 999, raised: true)
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}

/// One provider: its name, and whether omp is signed in to it.
private struct ProviderTile: View {
    @Environment(\.palette) private var palette
    let provider: LoginProvider
    /// Another sign-in is under way.
    let busy: Bool
    let signingIn: Bool
    let onSignIn: () -> Void
    let onSignOut: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(provider.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(palette.ink)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .topLeading)
            HStack(spacing: 6) {
                if provider.authenticated {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.success)
                    Text("Signed in")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.inkDim)
                    Spacer(minLength: 0)
                    if hovering {
                        Button("Sign out", action: onSignOut)
                            .buttonStyle(.plain)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.danger)
                            .help("Remove omp's saved sign-in for \(provider.name)")
                    }
                } else if signingIn {
                    ProgressView().controlSize(.mini)
                    Text("Signing in…")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.inkDim)
                } else {
                    Button(action: onSignIn) {
                        Text("Sign in")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(palette.ground)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 4)
                            .background(palette.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .disabled(busy)
                    .help("Sign in to \(provider.name) through omp")
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(12)
        .glass(radius: 12, raised: hovering)
        .onHover { hovering = $0 }
    }
}

import SwiftUI
import OMPCore

/// The pages behind the sidebar's customizations.
struct PanelView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(store.view.title.uppercased())
                    .font(Theme.label(10))
                    .foregroundStyle(Theme.accent)
                    .tracking(0.2)

                switch store.view {
                case .overview:
                    overview
                case .tools:
                    list(store.active?.inventory?.tools ?? [], empty: "omp exposes no tools in this project.")
                case .skills:
                    list(store.active?.inventory?.skills ?? [], empty: "This project has no skills.")
                case .extensions:
                    list(store.active?.inventory?.extensions ?? [], empty: "This project has no extensions.")
                case .prompts:
                    list(store.active?.inventory?.prompts ?? [], empty: "This project has no prompts.")
                case .transcript:
                    EmptyView()
                }
            }
            .frame(maxWidth: Theme.contentWidth, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var overview: some View {
        let session = store.active
        return VStack(alignment: .leading, spacing: 10) {
            fact("PROJECT", session?.project.name ?? "—")
            fact("FOLDER", session?.project.displayPath ?? "—")
            fact("BRANCH", session?.branch ?? "Not a git repository")
            fact("MODEL", session?.model?.name ?? "—")
            fact("MODE", session?.mode.label ?? "—")
            fact("PERMISSIONS", store.approvalLabel ?? "omp's default")
            fact("MESSAGES", session.map { "\($0.blocks.count)" } ?? "—")
            if let usage = session?.contextUsage {
                fact("CONTEXT", "\(usage.tokens.formatted()) of \(usage.contextWindow.formatted()) tokens (\(Int(usage.percent.rounded()))%)")
            }
        }
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(Theme.label(9.5))
                .foregroundStyle(Theme.inkFaint)
                .tracking(0.12)
                .frame(width: 120, alignment: .leading)
            Text(value)
                .font(Theme.body(13))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Theme.hairlineSoft, lineWidth: 1)
        }
    }

    @ViewBuilder
    private func list(_ items: [String], empty: String) -> some View {
        if items.isEmpty {
            Text(empty)
                .font(Theme.body(13))
                .foregroundStyle(Theme.inkFaint)
        } else {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(Theme.code(12.5))
                        .foregroundStyle(Theme.inkDim)
                        .padding(.horizontal, 2)
                        .padding(.vertical, 3)
                        .textSelection(.enabled)
                }
            }
        }
    }
}

/// A dialog the agent is waiting on.
struct DialogView: View {
    let request: UIRequest
    @Bindable var store: AppStore
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text((request.title ?? "omp needs an answer").uppercased())
                .font(Theme.label(10))
                .foregroundStyle(Theme.accent)
                .tracking(0.18)

            if let message = request.message, !message.isEmpty {
                Text(message)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.ink)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if request.method == "select" || request.method == "ask" {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(request.options) { option in
                        Button {
                            Task { await store.answer(request, value: option.label) }
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.label)
                                    .font(Theme.body(13))
                                    .foregroundStyle(Theme.ink)
                                if let description = option.description {
                                    Text(description)
                                        .font(Theme.body(11.5))
                                        .foregroundStyle(Theme.inkFaint)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(Theme.hairline, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            } else if request.method == "confirm" {
                HStack(spacing: 8) {
                    Button("Yes") { Task { await store.answer(request, value: "yes") } }
                        .buttonStyle(ConfirmButton(tone: Theme.accent))
                    Button("No") { Task { await store.answer(request, value: "no") } }
                        .buttonStyle(ConfirmButton(tone: Theme.inkDim))
                }
            } else if request.method == "input" || request.method == "editor" {
                TextField(request.placeholder ?? "Your answer", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1...8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Theme.hairline, lineWidth: 1)
                    }
                Button("Send") { Task { await store.answer(request, value: text) } }
                    .buttonStyle(ConfirmButton(tone: Theme.accent))
            } else if request.method == "open_url", let url = request.launchURL {
                Text(url)
                    .font(Theme.code(12))
                    .foregroundStyle(Theme.inkDim)
                    .textSelection(.enabled)
                Button("Dismiss") { Task { await store.answer(request, value: "", cancelled: true) } }
                    .buttonStyle(ConfirmButton(tone: Theme.inkDim))
            }

            Button("Cancel") { Task { await store.answer(request, value: "", cancelled: true) } }
                .buttonStyle(ConfirmButton(tone: Theme.inkFaint))
        }
        .padding(18)
        .frame(maxWidth: 520, alignment: .leading)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
    }
}

/// A plain button in the dialog's colours.
struct ConfirmButton: ButtonStyle {
    var tone: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.body(12.5))
            .foregroundStyle(tone)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.raised.opacity(configuration.isPressed ? 1 : 0.7), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Theme.hairline, lineWidth: 1)
            }
    }
}

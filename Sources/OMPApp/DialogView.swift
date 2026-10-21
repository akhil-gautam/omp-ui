import SwiftUI
import OMPCore

/// A dialog the agent is waiting on.
struct DialogView: View {
    @Environment(\.palette) private var palette
    let request: UIRequest
    @Bindable var store: AppStore
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text((request.title ?? "omp needs an answer").uppercased())
                .font(Theme.label(10))
                .foregroundStyle(palette.accent)
                .tracking(0.18)

            if let message = request.message, !message.isEmpty {
                Text(message)
                    .font(Theme.body(13))
                    .foregroundStyle(palette.ink)
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
                                    .foregroundStyle(palette.ink)
                                if let description = option.description {
                                    Text(description)
                                        .font(Theme.body(11.5))
                                        .foregroundStyle(palette.inkFaint)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 9)
                            .background(palette.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(palette.hairline, lineWidth: 1)
                            }
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help(option.description ?? option.label)
                    }
                }
            } else if request.method == "confirm" {
                HStack(spacing: 8) {
                    ConfirmButton(title: "Yes", tone: palette.accent, help: "Let omp go ahead") {
                        Task { await store.answer(request, value: "yes") }
                    }
                    ConfirmButton(title: "No", tone: palette.inkDim, help: "Decline, and tell omp no") {
                        Task { await store.answer(request, value: "no") }
                    }
                }
            } else if request.method == "input" || request.method == "editor" {
                TextField(request.placeholder ?? "Your answer", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(Theme.body(13))
                    .foregroundStyle(palette.ink)
                    .lineLimit(1...8)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(palette.raised, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(palette.hairline, lineWidth: 1)
                    }
                    .help("Your answer goes back to omp")
                ConfirmButton(title: "Send", tone: palette.accent, help: "Send your answer to omp") {
                    Task { await store.answer(request, value: text) }
                }
            } else if request.method == "open_url", let url = request.launchURL {
                Text(url)
                    .font(Theme.code(12))
                    .foregroundStyle(palette.inkDim)
                    .textSelection(.enabled)
                ConfirmButton(title: "Dismiss", tone: palette.inkDim, help: "Close the request without opening it") {
                    Task { await store.answer(request, value: "", cancelled: true) }
                }
            }

            ConfirmButton(title: "Cancel", tone: palette.inkFaint, help: "Cancel this request") {
                Task { await store.answer(request, value: "", cancelled: true) }
            }
        }
        .padding(18)
        .frame(maxWidth: 520, alignment: .leading)
        .glass(radius: 14, lifted: true)
    }
}

/// A plain button in the dialog's colours.
struct ConfirmButton: View {
    let title: String
    let tone: Color
    /// What the button does, shown when the pointer rests on it.
    let help: String
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.body(12.5))
                .foregroundStyle(tone)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(palette.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help)
    }
}

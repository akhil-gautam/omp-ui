import SwiftUI
import OMPCore

/// The composer: the place a message is written.
struct ComposerView: View {
    @Bindable var store: AppStore
    @State private var draft = ""
    @FocusState private var focused: Bool

    private var session: ProjectSession? { store.active }
    private var busy: Bool { session?.isBusy ?? false }

    var body: some View {
        VStack(spacing: 0) {
            if let session, !session.queue.isEmpty {
                queueStrip(session)
            }
            card
            footer
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    // MARK: - The queue

    private func queueStrip(_ session: ProjectSession) -> some View {
        HStack(spacing: 8) {
            Text("QUEUED")
                .font(Theme.label(9))
                .foregroundStyle(Theme.inkFaint)
                .tracking(0.14)
            Text("\(session.queue.count)")
                .font(Theme.label(9))
                .foregroundStyle(Theme.inkDim)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Theme.raised, in: Capsule())
            ForEach(session.queue.steering + session.queue.followUp, id: \.self) { message in
                Text(message)
                    .font(Theme.body(11))
                    .foregroundStyle(Theme.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(Theme.panel, in: Capsule())
                    .overlay {
                        Capsule().stroke(Theme.hairlineSoft, lineWidth: 1)
                    }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: Theme.contentWidth)
        .padding(.bottom, 8)
    }

    // MARK: - The card

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            modelChip

            TextField("Pitch your idea", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.body(15))
                .foregroundStyle(Theme.ink)
                .lineLimit(1...8)
                .focused($focused)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .onSubmit(send)

            HStack(spacing: 6) {
                Button {
                    draft = "/"
                    focused = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Theme.inkDim)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Run a command")

                modeChip
                thinkingChip

                if let usage = session?.contextUsage {
                    Text("\(Int((100 - usage.percent).rounded()))% left")
                        .font(Theme.body(11))
                        .foregroundStyle(Theme.inkFaint)
                        .monospacedDigit()
                        .padding(.leading, 4)
                        .help("Context left in this session")
                }

                Spacer(minLength: 0)

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ground)
                        .frame(width: 28, height: 28)
                        .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.raised : Theme.accent, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(busy ? "Queue this message" : "Send")

                if busy {
                    Button {
                        Task { await store.abort() }
                    } label: {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.ink)
                            .frame(width: 28, height: 28)
                            .background(Theme.raised, in: Circle())
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .help("Stop the turn")
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: Theme.contentWidth)
        .background(Theme.panel, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(focused ? Theme.accentLine : Theme.hairline, lineWidth: 1)
        }
    }

    private var modelChip: some View {
        Select(
            icon: "bolt",
            items: (session?.modelList ?? []).map { model in
                Select.Item(id: model.id, title: model.name, detail: model.provider)
            },
            selected: session?.model?.id,
            placeholder: "No model"
        ) { model in
            if let found = session?.modelList.first(where: { $0.id == model.id }) {
                Task { await store.setModel(found) }
            }
        }
    }

    private var modeChip: some View {
        Select(
            icon: "bubble.left",
            items: SessionMode.allCases.map { mode in
                Select.Item(id: mode.rawValue, title: mode.label, detail: mode.hint)
            },
            selected: session?.mode.rawValue,
            placeholder: "Interactive"
        ) { mode in
            Task { await store.setMode(SessionMode(rawValue: mode.id) ?? .interactive) }
        }
    }

    private var thinkingChip: some View {
        Select(
            icon: "brain",
            items: ["off", "minimal", "low", "medium", "high", "xhigh", "max"].map { level in
                Select.Item(id: level, title: level.capitalized)
            },
            selected: session?.thinkingLevel,
            placeholder: "Off"
        ) { level in
            Task { await store.setThinking(level.id) }
        }
    }

    // MARK: - The footer

    private var footer: some View {
        HStack(spacing: 14) {
            if let approval = store.approvalLabel {
                Text(approval)
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.inkFaint)
            }
            Spacer(minLength: 0)

            if let branch = session?.branch {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.system(size: 10.5))
                    Text(branch)
                        .font(Theme.body(11.5))
                }
                .foregroundStyle(Theme.inkFaint)
            }
        }
        .frame(maxWidth: Theme.contentWidth)
        .padding(.top, 9)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await store.send(text) }
    }
}

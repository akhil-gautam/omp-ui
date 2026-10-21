import SwiftUI
import OMPCore

/// The composer: the place a message is written.
struct ComposerView: View {
    @Environment(\.palette) private var palette
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
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("Pitch your idea", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1...6)
                        .focused($focused)
                        .frame(minHeight: 22, alignment: .topLeading)
                        .help("Write to the agent. Return sends it.")
                        .onSubmit(send)
                    controls
                }
                .padding(.horizontal, 14)
                .padding(.top, 13)
                .padding(.bottom, 11)
                .background(palette.ground)

                footer
                    .background(palette.panel)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(palette.hairline, lineWidth: 1)
            }
            .shadow(color: .black.opacity(palette.isLight ? 0.08 : 0.45), radius: 20, y: 8)
        }
        .frame(maxWidth: Theme.contentWidth)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
    }

    // MARK: - The queue

    private func queueStrip(_ session: ProjectSession) -> some View {
        HStack(spacing: 8) {
            Text("QUEUED")
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.inkFaint)
                .tracking(0.14)
            Text("\(session.queue.count)")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(palette.inkDim)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(palette.raised, in: Capsule())
            ForEach(session.queue.steering + session.queue.followUp, id: \.self) { message in
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(palette.inkDim)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(palette.panel, in: Capsule())
            }
            Spacer(minLength: 0)
        }
        .padding(.bottom, 8)
    }

    // MARK: - The controls

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                draft = "/"
                focused = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.inkDim)
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Run a command")

            modeChip
            thinkingChip

            Spacer(minLength: 8)

            modelChip

            if busy {
                Button {
                    Task { await store.abort() }
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.ink)
                        .frame(width: 30, height: 30)
                        .background(palette.raised, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .help("Stop the turn")
            }

            Button(action: send) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(palette.ground)
                    .frame(width: 30, height: 30)
                    .background(
                        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? palette.raised : palette.ink,
                        in: Circle()
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help(busy ? "Queue this message" : "Send")
        }
    }

    private var modelChip: some View {
        Select(
            icon: "bolt",
            items: (session?.modelList ?? []).map { model in
                Select.Item(id: model.id, title: model.name, detail: model.upstream)
            },
            selected: session?.model?.id,
            placeholder: "No model",
            plain: true,
            help: "The model that answers"
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
            placeholder: "Interactive",
            plain: true,
            help: session?.mode.hint ?? "How messages reach a running turn"
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
            placeholder: "Off",
            plain: true,
            help: "How much the model thinks before it answers"
        ) { level in
            Task { await store.setThinking(level.id) }
        }
    }

    // MARK: - The foot of the card

    private var footer: some View {
        HStack(spacing: 16) {
            if let branch = session?.branch {
                Label(branch, systemImage: "arrow.triangle.branch")
                    .help("The branch omp is working on")
            }
            if let path = session?.project.displayPath {
                Label(path, systemImage: "folder")
                    .lineLimit(1)
                    .truncationMode(.head)
                    .help("The folder omp is working in")
            }
            Spacer(minLength: 0)
            if let approval = store.approvalLabel {
                Text(approval)
                    .font(.system(size: 11.5))
                    .foregroundStyle(palette.inkFaint)
                    .help("How omp asks before it acts")
            }
        }
        .font(.system(size: 12))
        .foregroundStyle(palette.inkFaint)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        Task { await store.send(text) }
    }
}

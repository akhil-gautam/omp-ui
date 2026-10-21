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
        .padding(.bottom, 16)
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
            HStack(spacing: 6) {
                projectChip
                modelChip
            }
            .padding(.horizontal, 3)

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
                    .help("Stop the turn")
                }

                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.ground)
                        .frame(width: 28, height: 28)
                        .background(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Theme.raised : Theme.accent, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help(busy ? "Queue this message" : "Send")
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

    private var projectChip: some View {
        Menu {
            ForEach(store.projects) { project in
                Button {
                    Task { await store.open(project.id) }
                } label: {
                    Text(project.name)
                }
            }
            Divider()
            Button("Add a project…") {
                Task { await store.addProjectPicker() }
            }
        } label: {
            chipLabel(icon: "folder", text: session?.project.name ?? "No project")
        }
    }

    private var modelChip: some View {
        Menu {
            ForEach(session?.modelList ?? []) { model in
                Button {
                    Task { await store.setModel(model) }
                } label: {
                    Text(model.name)
                }
            }
        } label: {
            chipLabel(icon: "bolt", text: session?.model?.name ?? "No model")
        }
    }

    private var modeChip: some View {
        Menu {
            ForEach(SessionMode.allCases, id: \.self) { mode in
                Button {
                    Task { await store.setMode(mode) }
                } label: {
                    Text("\(mode.label) — \(mode.hint)")
                }
            }
        } label: {
            chipLabel(icon: "bubble.left", text: session?.mode.label ?? "Interactive")
        }
    }

    private var thinkingChip: some View {
        Menu {
            ForEach(["off", "minimal", "low", "medium", "high", "xhigh", "max"], id: \.self) { level in
                Button {
                    Task { await store.setThinking(level) }
                } label: {
                    Text(level.capitalized)
                }
            }
        } label: {
            chipLabel(icon: "brain", text: (session?.thinkingLevel ?? "off").capitalized)
        }
    }

    private func chipLabel(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10.5))
            Text(text)
                .font(Theme.body(12))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(Theme.inkFaint)
        }
        .foregroundStyle(Theme.inkDim)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(Theme.hairline, lineWidth: 1)
        }
    }

    // MARK: - The footer

    private var footer: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left")
                    .font(.system(size: 11))
                Text(session?.mode.label ?? "Interactive")
                    .font(Theme.body(11.5))
            }
            .foregroundStyle(Theme.inkDim)

            if let approval = store.approvalLabel {
                Text(approval)
                    .font(Theme.body(11.5))
                    .foregroundStyle(Theme.inkFaint)
            }

            Spacer(minLength: 0)

            if let session {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                        .font(.system(size: 10.5))
                    Text(session.project.name)
                        .font(Theme.body(11.5))
                        .lineLimit(1)
                }
                .foregroundStyle(Theme.inkFaint)

                if let branch = session.branch {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 10.5))
                        Text(branch)
                            .font(Theme.body(11.5))
                    }
                    .foregroundStyle(Theme.inkFaint)
                }
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

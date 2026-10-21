import SwiftUI
import OMPCore

/// The composer: the place a message is written.
struct ComposerView: View {
    @Environment(\.palette) private var palette
    @Bindable var store: AppStore
    @State private var draft = ""
    /// Images going with the next message.
    @State private var images: [ImageAttachment] = []
    @State private var menuOpen = false
    @FocusState private var focused: Bool

    private var session: ProjectSession? { store.active }
    /// From the moment a message is sent until the turn ends.
    private var working: Bool { session?.isWorking ?? false }

    var body: some View {
        VStack(spacing: 0) {
            if let session, !session.queue.isEmpty {
                queueStrip(session)
            }
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    if !images.isEmpty {
                        attachmentStrip
                    }
                    TextField("Pitch your idea", text: $draft, axis: .vertical)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.ink)
                        .lineLimit(1...6)
                        .focused($focused)
                        .frame(minHeight: 22, alignment: .topLeading)
                        .help(working
                              ? "Return adds this to the turn in progress; omp reads it at its next step."
                              : "Write to the agent. Return sends it.")
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
            .glass(radius: 14, lifted: true)
            // Light pooling under the composer, the way it gathers under a
            // button lit from above.
            .background {
                Ellipse()
                    .fill(palette.glow.opacity(palette.isLight ? 0.10 : 0.07))
                    .blur(radius: 36)
                    .padding(.horizontal, 70)
                    .offset(y: 26)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: Theme.contentWidth)
        .padding(.horizontal, 28)
        .padding(.bottom, 18)
        .onChange(of: store.pendingDraft) { _, text in
            guard let text else { return }
            draft = text
            store.pendingDraft = nil
            focused = true
        }
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
                menuOpen.toggle()
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(palette.inkDim)
                    .frame(width: 24, height: 24)
                    .background(Circle().fill(menuOpen ? palette.raised : .clear))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .help("Add files, folders, skills, git, rules, a command…")
            .popover(isPresented: $menuOpen, arrowEdge: .top) {
                ComposerMenu(
                    store: store,
                    onInsert: insert,
                    onImages: { images += $0; focused = true },
                    onClose: { menuOpen = false }
                )
                .environment(\.palette, palette)
            }

            modeChip
            thinkingChip

            Spacer(minLength: 8)

            modelChip

            // One button: stop while a turn is under way, send otherwise.
            // A message written meanwhile still goes with Return.
            if working {
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
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.ground)
                        .frame(width: 30, height: 30)
                        .background(canSend ? palette.ink : palette.raised, in: Circle())
                        .shadow(color: palette.glow.opacity(canSend && !palette.isLight ? 0.35 : 0), radius: 10)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .focusable(false)
                .disabled(!canSend)
                .help("Send")
            }
        }
    }

    private var modelChip: some View {
        Select(
            icon: "bolt",
            // As omp lists them: every model is its selector, `provider/id`,
            // and the chip names the provider so a subscription model and the
            // same model through a gateway never look alike.
            items: (session?.modelList ?? []).map { model in
                Select.Item(id: model.selector, title: model.name, detail: model.selector, badge: model.provider)
            },
            selected: session?.model?.selector,
            placeholder: "No model",
            plain: true,
            help: session?.model.map { "\($0.selector) — the model that answers" } ?? "The model that answers"
        ) { item in
            if let found = session?.modelList.first(where: { $0.selector == item.id }) {
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

    private var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !images.isEmpty
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        let attached = images
        draft = ""
        images = []
        // omp refuses a plain prompt while a turn runs; like its own Enter,
        // a message written meanwhile steers the turn in progress.
        Task { await store.send(text, behavior: working ? "steer" : nil, images: attached) }
    }

    /// Puts what the menu chose into the message: a mention where the
    /// message ends, a command at its start, or a whole message.
    private func insert(_ insertion: ComposerMenu.Insertion) {
        switch insertion {
        case .mention(let text):
            let joiner = draft.isEmpty || draft.hasSuffix(" ") || draft.hasSuffix("\n") ? "" : " "
            draft += joiner + text + " "
        case .command(let name):
            let rest = draft.trimmingCharacters(in: .whitespaces)
            draft = "/\(name) " + rest
        case .message(let text):
            draft = text
        }
        focused = true
    }

    /// The images going with the next message, each with a way to drop it.
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(images.enumerated()), id: \.offset) { index, image in
                    HStack(spacing: 7) {
                        if let data = Data(base64Encoded: image.data), let picture = NSImage(data: data) {
                            Image(nsImage: picture)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 26, height: 26)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        Text(image.name)
                            .font(.system(size: 12))
                            .foregroundStyle(palette.inkDim)
                            .lineLimit(1)
                        Button {
                            images.remove(at: index)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(palette.inkFaint)
                        }
                        .buttonStyle(.plain)
                        .focusable(false)
                        .help("Leave this image out")
                    }
                    .padding(.leading, 4)
                    .padding(.trailing, 10)
                    .padding(.vertical, 4)
                    .glass(radius: 9, raised: true)
                }
            }
        }
    }
}

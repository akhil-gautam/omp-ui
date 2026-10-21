import SwiftUI
import OMPCore

/// The conversation.
struct TranscriptView: View {
    @Bindable var store: AppStore

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if let session = store.active {
                        if session.blocks.isEmpty {
                            GreetingView(store: store)
                        } else {
                            ForEach(session.blocks) { block in
                                BlockView(block: block)
                                    .id(block.id)
                            }
                        }
                        if let request = session.pendingRequest {
                            DialogView(request: request, store: store)
                        }
                    } else {
                        GreetingView(store: store)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .frame(maxWidth: Theme.contentWidth)
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: store.active?.blocks.count) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }
}

/// The greeting, shown while there is nothing to read.
struct GreetingView: View {
    @Bindable var store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("WHAT ARE WE BUILDING")
                .font(Theme.label(10))
                .foregroundStyle(Theme.accent)
                .tracking(0.2)
            Text(store.userName.isEmpty ? "What are we building?" : "What are we building, \(store.userName)?")
                .font(Theme.heading(30))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let session = store.active {
                Text("omp is ready in \(session.project.name).")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkDim)
            } else {
                Text("Add a project to give omp a place to work.")
                    .font(Theme.body(13))
                    .foregroundStyle(Theme.inkDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 60)
    }
}

/// One entry of the transcript.
struct BlockView: View {
    let block: Block

    var body: some View {
        switch block {
        case .user(_, let text):
            Text(Markdown.inline(text))
                .font(Theme.body(13.5))
                .foregroundStyle(Theme.ink)
                .textSelection(.enabled)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(Theme.panel, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.hairline, lineWidth: 1)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
        case .text(_, let text):
            MarkdownView(source: text)
        case .thinking(_, let text):
            // Thinking is always shown: it is the reasoning, not a summary.
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.system(size: 10))
                    Text("THINKING")
                        .font(Theme.label(9))
                        .tracking(0.14)
                }
                .foregroundStyle(Theme.inkFaint)
                MarkdownView(source: text)
                    .foregroundStyle(Theme.inkDim)
            }
            .padding(.leading, 10)
            .overlay(alignment: .leading) {
                Rectangle().fill(Theme.hairline).frame(width: 2)
            }
        case .tool(_, let name, let args, let output, let isError, let running):
            ToolCallView(name: name, args: args, output: output, isError: isError, running: running)
        }
    }
}

/// A tool call: one quiet line, opened only when it is asked for.
struct ToolCallView: View {
    let name: String
    let args: JSONValue?
    let output: String?
    let isError: Bool
    let running: Bool

    @State private var expanded = false
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.inkFaint)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .opacity(hovering || expanded ? 1 : 0)
                    Image(systemName: isError ? "exclamationmark.triangle" : "wrench.and.screwdriver")
                        .font(.system(size: 9))
                        .foregroundStyle(isError ? Theme.danger : Theme.inkFaint)
                    Text(name)
                        .font(Theme.code(11))
                        .foregroundStyle(Theme.inkFaint)
                    if running {
                        Circle()
                            .fill(Theme.accent)
                            .frame(width: 4, height: 4)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focusable(false)
            .onHover { hovering = $0 }

            if expanded {
                if let args, !args.isNull {
                    Labelled(title: "ARGUMENTS", text: args.pretty)
                }
                if let output, !output.isEmpty {
                    Labelled(title: "RESULT", text: output)
                }
            }
        }
        .padding(.vertical, 1)
    }
}

/// A labelled piece of a tool call.
private struct Labelled: View {
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(Theme.label(9))
                .foregroundStyle(Theme.inkFaint)
                .tracking(0.12)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(Theme.code(11.5))
                    .foregroundStyle(Theme.inkDim)
                    .textSelection(.enabled)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.codeBackground, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Theme.hairlineSoft, lineWidth: 1)
            }
        }
    }
}

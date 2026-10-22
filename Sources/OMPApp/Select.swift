import SwiftUI
import OMPCore

/// A chip that opens a list of choices.
///
/// The list is searchable once it is long enough to need it, and the
/// selection is marked so the reader knows where they are.
struct Select: View {
    @Environment(\.palette) private var palette
    struct Item: Identifiable, Hashable {
        var id: String
        var title: String
        var detail: String?
        /// Said beside the title on the chip, when the title alone could name
        /// two different things.
        var badge: String?

        init(id: String, title: String, detail: String? = nil, badge: String? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
            self.badge = badge
        }

        /// What the row says when the pointer rests on it.
        var tip: String {
            guard let detail, !detail.isEmpty else { return title }
            return "\(title) — \(detail)"
        }
    }

    let icon: String
    let items: [Item]
    let selected: String?
    let placeholder: String
    /// A header chip has no plate of its own.
    var plain = false
    /// What the chip is for, shown when the pointer rests on it.
    var help: String?
    /// A second list under the first, under its own heading — for the model
    /// picker, the providers not signed in yet, the way omp's model hub
    /// shows them below the ones that are.
    var more: [Item] = []
    var moreTitle: String = ""
    /// What a row of the second list offers, shown at its end.
    var moreAction: String = ""
    let onSelect: (Item) -> Void

    @State private var open = false

    @State private var query = ""

    /// A list longer than this is worth searching.
    private var searches: Bool { items.count + more.count > 12 }

    private var filtered: [Item] { narrowed(items) }

    private func narrowed(_ list: [Item]) -> [Item] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return list }
        return list.filter { Select.matches($0, needle) }
    }

    /// Whether a row matches what the reader typed: its title, its detail or
    /// its id. A model's id is its selector, so "anthropic" finds Anthropic's
    /// own models and the ones other providers serve from it, as omp's model
    /// list does.
    static func matches(_ item: Item, _ needle: String) -> Bool {
        let needle = needle.lowercased()
        guard !needle.isEmpty else { return true }
        return item.title.lowercased().contains(needle)
            || (item.detail?.lowercased().contains(needle) ?? false)
            || item.id.lowercased().contains(needle)
    }

    private var current: Item? { items.first { $0.id == selected } }

    private var title: String { current?.title ?? placeholder }

    var body: some View {
        Button {
            open = true
            query = ""
        } label: {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10.5))
                Text(title)
                    .font(Theme.body(12))
                    .lineLimit(1)
                if let badge = current?.badge {
                    Text(badge)
                        .font(Theme.body(11))
                        .foregroundStyle(palette.inkFaint)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(palette.inkFaint)
            }
            .foregroundStyle(palette.inkDim)
            .padding(.horizontal, plain ? 0 : 9)
            .padding(.vertical, plain ? 0 : 5)
            .background(
                plain ? AnyShapeStyle(.clear) : AnyShapeStyle(palette.raised),
                in: RoundedRectangle(cornerRadius: 7, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(help ?? "\(current?.tip ?? title) — choose another")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            list
                .frame(minWidth: 280, maxWidth: 440)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            if searches {
                HStack(spacing: 7) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.inkFaint)
                    TextField("Search", text: $query)
                        .textFieldStyle(.plain)
                        .font(Theme.body(12.5))
                        .foregroundStyle(palette.ink)
                        .help("Type to narrow the list")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.hairlineSoft).frame(height: 1)
                }
            }

            ScrollView {
                // The list can hold hundreds of models, so the rows are made
                // as they are scrolled to rather than all at once.
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filtered) { item in
                        row(item, action: nil)
                    }
                    let others = narrowed(more)
                    if !others.isEmpty {
                        Text(moreTitle.uppercased())
                            .font(Theme.label(9.5))
                            .foregroundStyle(palette.inkFaint)
                            .tracking(0.4)
                            .padding(.horizontal, 12)
                            .padding(.top, filtered.isEmpty ? 4 : 12)
                            .padding(.bottom, 4)
                        ForEach(others) { item in
                            row(item, action: moreAction)
                        }
                    }
                    if filtered.isEmpty && others.isEmpty {
                        Text("Nothing matches.")
                            .font(Theme.body(12))
                            .foregroundStyle(palette.inkFaint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: more.isEmpty ? 320 : 400)
        }
        .background(palette.panel)
        .background(PopoverBackground(colour: palette.panel))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 26, y: 10)
    }

    /// One row: its title and detail, and either the mark of the current
    /// choice or what choosing it does.
    private func row(_ item: Item, action: String?) -> some View {
        Button {
            onSelect(item)
            open = false
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(Theme.body(12.5))
                        .foregroundStyle(action == nil ? palette.ink : palette.inkDim)
                        .lineLimit(1)
                    if let detail = item.detail {
                        Text(detail)
                            .font(Theme.body(11))
                            .foregroundStyle(palette.inkFaint)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                Spacer(minLength: 8)
                if let action {
                    Text(action)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.ground)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 3)
                        .background(palette.ink, in: Capsule())
                } else if item.id == selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(palette.accent)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(item.id == selected ? palette.raised : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(item.tip)
    }
}

/// The popover's arrow is drawn by the system in the colour of the window it
/// belongs to, so the window is told what the panel's colour is.
struct PopoverBackground: NSViewRepresentable {
    let colour: Color

    func makeNSView(context: Context) -> NSView {
        let view = Observer()
        view.colour = NSColor(colour)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let observer = nsView as? Observer else { return }
        observer.colour = NSColor(colour)
        observer.apply()
    }

    /// A view that knows when it has been put in a window.
    final class Observer: NSView {
        var colour: NSColor?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let colour else { return }
            window?.backgroundColor = colour
            window?.isOpaque = false
        }
    }
}

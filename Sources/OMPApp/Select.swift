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

        init(id: String, title: String, detail: String? = nil) {
            self.id = id
            self.title = title
            self.detail = detail
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
    let onSelect: (Item) -> Void

    @State private var open = false
    @State private var query = ""

    /// A list longer than this is worth searching.
    private var searches: Bool { items.count > 12 }

    private var filtered: [Item] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return items }
        return items.filter {
            $0.title.lowercased().contains(needle) || ($0.detail?.lowercased().contains(needle) ?? false)
        }
    }

    private var title: String {
        items.first { $0.id == selected }?.title ?? placeholder
    }

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
        .help(help ?? "\(title) — choose another")
        .popover(isPresented: $open, arrowEdge: .bottom) {
            list
                .frame(minWidth: 280, maxWidth: 380)
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
                VStack(alignment: .leading, spacing: 1) {
                    ForEach(filtered) { item in
                        Button {
                            onSelect(item)
                            open = false
                        } label: {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title)
                                        .font(Theme.body(12.5))
                                        .foregroundStyle(palette.ink)
                                        .lineLimit(1)
                                    if let detail = item.detail {
                                        Text(detail)
                                            .font(Theme.body(11))
                                            .foregroundStyle(palette.inkFaint)
                                            .lineLimit(1)
                                            .truncationMode(.head)
                                    }
                                }
                                Spacer(minLength: 8)
                                if item.id == selected {
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
                    if filtered.isEmpty {
                        Text("Nothing matches.")
                            .font(Theme.body(12))
                            .foregroundStyle(palette.inkFaint)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 320)
        }
        .background(palette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 26, y: 10)
    }
}

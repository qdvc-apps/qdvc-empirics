import AppKit
import SwiftUI

/// A column of a `DataTable`: a title, a fixed width (or flexible), how to
/// sort by it, and what each cell shows.
struct DataColumn<Row> {
    var title: String
    /// A fixed width; nil shares the remaining width with the other flexible
    /// columns.
    var width: CGFloat?
    var minWidth: CGFloat
    var alignment: Alignment
    /// "Comes before", for sorting by this column; nil if it doesn't sort.
    var order: ((Row, Row) -> Bool)?
    var cell: (Row) -> AnyView

    init<Cell: View>(_ title: String, width: CGFloat? = nil, minWidth: CGFloat = 60, alignment: Alignment = .leading,
                     order: ((Row, Row) -> Bool)? = nil, @ViewBuilder cell: @escaping (Row) -> Cell) {
        self.title = title
        self.width = width
        self.minWidth = minWidth
        self.alignment = alignment
        self.order = order
        self.cell = { AnyView(cell($0)) }
    }

    /// Sorts text the way Finder does (numbers in order, case ignored).
    static func text(_ value: @escaping (Row) -> String) -> (Row, Row) -> Bool {
        { a, b in value(a).localizedStandardCompare(value(b)) == .orderedAscending }
    }

    static func number(_ value: @escaping (Row) -> Int) -> (Row, Row) -> Bool {
        { a, b in value(a) < value(b) }
    }
}

/// A table for the list pages: a header of sortable columns, alternating
/// rows, click to select, double-click (or Return) to open, ↑ ↓ to move,
/// right-click for the row's menu.
///
/// Built from a SwiftUI ScrollView rather than SwiftUI's `Table`: with
/// `Table` (an AppKit table view) in the detail column, the sidebar's rows
/// were thrown out of place (pushed up under the window buttons) whenever
/// a table page opened. See docs/MAINTENANCE.md.
struct DataTable<Row: Identifiable, MenuContent: View>: View where Row.ID == String {
    let rows: [Row]
    let columns: [DataColumn<Row>]
    @Binding var selection: String?
    var defaultSort: Int
    var emptyText: String
    var onOpen: (String) -> Void
    var menu: (Row) -> MenuContent

    @State private var sortColumn: Int?
    @State private var ascending = true
    @FocusState private var focused: Bool

    init(rows: [Row], columns: [DataColumn<Row>], selection: Binding<String?>, defaultSort: Int = 0,
         emptyText: String = "Nothing here yet.", onOpen: @escaping (String) -> Void,
         @ViewBuilder menu: @escaping (Row) -> MenuContent) {
        self.rows = rows
        self.columns = columns
        self._selection = selection
        self.defaultSort = defaultSort
        self.emptyText = emptyText
        self.onOpen = onOpen
        self.menu = menu
    }

    private var sorted: [Row] {
        let col = sortColumn ?? defaultSort
        guard columns.indices.contains(col), let order = columns[col].order else { return rows }
        let list = rows.sorted(by: order)
        return ascending ? list : list.reversed()
    }

    var body: some View {
        let shown = sorted
        VStack(spacing: 0) {
            header
            Divider()
            if shown.isEmpty {
                Text(emptyText)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(shown.enumerated()), id: \.element.id) { index, row in
                                rowView(row, index: index)
                                    .id(row.id)
                            }
                        }
                    }
                    .focusable()
                    .focusEffectDisabled()
                    .focused($focused)
                    .onKeyPress(.upArrow) {
                        step(-1, in: shown, proxy: proxy)
                        return .handled
                    }
                    .onKeyPress(.downArrow) {
                        step(1, in: shown, proxy: proxy)
                        return .handled
                    }
                    .onKeyPress(.return) {
                        if let s = selection, shown.contains(where: { $0.id == s }) { onOpen(s) }
                        return .handled
                    }
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { c in
                headerCell(c)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private func headerCell(_ c: Int) -> some View {
        let column = columns[c]
        let active = (sortColumn ?? defaultSort) == c && column.order != nil
        let label = HStack(spacing: 3) {
            Text(column.title)
                .font(.callout.weight(active ? .semibold : .regular))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if active {
                Image(systemName: ascending ? "chevron.up" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        Button {
            guard column.order != nil else { return }
            if (sortColumn ?? defaultSort) == c {
                ascending.toggle()
            } else {
                sortColumn = c
                ascending = true
            }
        } label: {
            label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(column.order == nil ? column.title : "Sort by \(column.title)")
        .modifier(ColumnFrame(width: column.width, minWidth: column.minWidth, alignment: column.alignment))
    }

    private func rowView(_ row: Row, index: Int) -> some View {
        let selected = row.id == selection
        return HStack(spacing: 0) {
            ForEach(columns.indices, id: \.self) { c in
                columns[c].cell(row)
                    .lineLimit(1)
                    .modifier(ColumnFrame(width: columns[c].width, minWidth: columns[c].minWidth,
                                          alignment: columns[c].alignment))
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(rowBackground(selected: selected, index: index))
        .contentShape(Rectangle())
        .onTapGesture {
            // One handler (not separate single and double taps, which would
            // delay every click by the double-click interval).
            focused = true
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2 {
                onOpen(row.id)
            } else {
                selection = row.id
            }
        }
        .contextMenu { menu(row) }
    }

    private func rowBackground(selected: Bool, index: Int) -> Color {
        if selected { return Color.accentColor.opacity(focused ? 0.28 : 0.16) }
        return index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.035)
    }

    private func step(_ delta: Int, in rows: [Row], proxy: ScrollViewProxy) {
        guard !rows.isEmpty else { return }
        let current = selection.flatMap { s in rows.firstIndex { $0.id == s } }
        let next: Int
        if let current {
            next = max(0, min(rows.count - 1, current + delta))
        } else {
            next = delta > 0 ? 0 : rows.count - 1
        }
        selection = rows[next].id
        proxy.scrollTo(rows[next].id)
    }
}

/// A cell's frame: fixed width, or flexible with a minimum.
private struct ColumnFrame: ViewModifier {
    var width: CGFloat?
    var minWidth: CGFloat
    var alignment: Alignment

    func body(content: Content) -> some View {
        if let width {
            content
                .padding(.horizontal, 6)
                .frame(width: width, alignment: alignment)
        } else {
            content
                .padding(.horizontal, 6)
                .frame(minWidth: minWidth, maxWidth: .infinity, alignment: alignment)
        }
    }
}

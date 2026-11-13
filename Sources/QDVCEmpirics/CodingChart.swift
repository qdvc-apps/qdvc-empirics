import AppKit
import EmpiricsCore
import SwiftUI

/// Reports › Coding Chart: the active layer's empirical files on the
/// left, linked (M:N) to the open codes with evidence in them, linked to
/// the theorising codes they are evidence for; theorising codes built on other theorising
/// codes sit further right. Every item is one line (icon, title, working
/// identifier). Click an item to see it in the inspector and light up what
/// it is linked to; double-click to open it.
///
/// Like every page, it starts with its scrolling content at the top, with
/// the bar below (docs/MAINTENANCE.md §Layout).
struct CodingChartPage: View {
    @Environment(AppModel.self) private var model
    @State private var includeUnlinked = false

    static let nodeWidth: CGFloat = 220
    static let nodeHeight: CGFloat = 26
    static let rowGap: CGFloat = 8
    static let columnGap: CGFloat = 96
    static let headerHeight: CGFloat = 34
    static let margin: CGFloat = 20

    var body: some View {
        let chart = CodingChart.make(model.project, layer: model.inductiveLayer?.key ?? "", includeUnlinked: includeUnlinked)
        VStack(spacing: 0) {
            if chart.columns.allSatisfy(\.isEmpty) {
                ContentUnavailableView("Nothing to Chart Yet", systemImage: "point.3.connected.trianglepath.dotted",
                                       description: Text(chart.unlinked > 0
                                           ? "Nothing in \(model.inductiveLayer?.name ?? "this layer") is linked yet. Apply open codes to text, and build theorising codes from them."
                                           : "Apply open codes to text in \(model.inductiveLayer?.name ?? "this layer"), and build theorising codes from them."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ChartCanvas(model: model, chart: chart)
            }
            footer(chart)
        }
    }

    func footer(_ chart: CodingChart) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                LayerMenu(model: model)
                    .fixedSize()
                Toggle("Show Unlinked Items", isOn: $includeUnlinked)
                    .toggleStyle(.checkbox)
                    .help("Also show empirical files, open codes and theorising codes that nothing links to yet")
                Spacer(minLength: 8)
                Text(summary(chart))
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .lineLimit(1)
            }
            .controlSize(.small)
            .padding(8)
        }
    }

    func summary(_ chart: CodingChart) -> String {
        let files = chart.columns.first?.count ?? 0
        let open = chart.columns.count > 1 ? chart.columns[1].count : 0
        let theorising = chart.columns.dropFirst(2).reduce(0) { $0 + $1.count }
        var text = "\(files) file\(files == 1 ? "" : "s") · \(open) open · \(theorising) theorising code\(theorising == 1 ? "" : "s")"
        if chart.unlinked > 0 { text += " · \(chart.unlinked) unlinked not shown" }
        return text
    }
}

/// The chart itself: column headings, Bézier links in a Canvas, and the
/// items. (Takes the model directly: its items carry context menus.)
struct ChartCanvas: View {
    let model: AppModel
    let chart: CodingChart

    typealias P = CodingChartPage

    struct Layout {
        var frames: [String: CGRect] = [:]
        var size: CGSize = .zero
        var headers: [(title: String, x: CGFloat)] = []
    }

    static func layout(_ chart: CodingChart) -> Layout {
        var l = Layout()
        let tallest = chart.columns.map(\.count).max() ?? 0
        let fullHeight = CGFloat(tallest) * (P.nodeHeight + P.rowGap) - P.rowGap
        for (c, column) in chart.columns.enumerated() {
            let x = P.margin + CGFloat(c) * (P.nodeWidth + P.columnGap)
            let height = CGFloat(column.count) * (P.nodeHeight + P.rowGap) - P.rowGap
            let top = P.margin + P.headerHeight + max(0, (fullHeight - height) / 2)
            for (r, key) in column.enumerated() {
                l.frames[key] = CGRect(x: x, y: top + CGFloat(r) * (P.nodeHeight + P.rowGap),
                                       width: P.nodeWidth, height: P.nodeHeight)
            }
            let title: String
            switch c {
            case 0: title = "Empirical Files"
            case 1: title = "Open Codes"
            default: title = chart.columns.count > 3 ? "Theorising Codes · Level \(c - 1)" : "Theorising Codes"
            }
            l.headers.append((title, x))
        }
        l.size = CGSize(width: P.margin * 2 + CGFloat(chart.columns.count) * (P.nodeWidth + P.columnGap) - P.columnGap,
                        height: P.margin * 2 + P.headerHeight + max(0, fullHeight))
        return l
    }

    var body: some View {
        let layout = Self.layout(chart)
        let selected = model.tableSelection.flatMap { layout.frames[$0] != nil ? $0 : nil }
        let lit: Set<String> = selected.map { chart.connected(to: $0) } ?? []
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                // Clicking the background clears the selection.
                Color(nsColor: .textBackgroundColor)
                    .contentShape(Rectangle())
                    .onTapGesture { model.tableSelection = nil }
                links(layout, lit: lit, selected: selected)
                    .allowsHitTesting(false)
                ForEach(Array(layout.headers.enumerated()), id: \.offset) { _, h in
                    Text(h.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: P.nodeWidth, alignment: .leading)
                        .offset(x: h.x + 4, y: P.margin)
                }
                ForEach(chart.columns.flatMap { $0 }, id: \.self) { key in
                    if let frame = layout.frames[key] {
                        ChartNode(model: model, key: key, selected: key == selected,
                                  dimmed: selected != nil && !lit.contains(key))
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                    }
                }
            }
            .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    func links(_ layout: Layout, lit: Set<String>, selected: String?) -> some View {
        let edges = chart.edges
        let colours: [String: Color] = Dictionary(uniqueKeysWithValues: edges.map(\.to).uniqued().compactMap { k in
            model.project.code(k).map { (k, $0.color) }
        })
        return Canvas { context, _ in
            for e in edges {
                guard let a = layout.frames[e.from], let b = layout.frames[e.to] else { continue }
                let start = CGPoint(x: a.maxX, y: a.midY)
                let end = CGPoint(x: b.minX, y: b.midY)
                let dx = max(40, (end.x - start.x) / 2)
                var path = Path()
                path.move(to: start)
                path.addCurve(to: end, control1: CGPoint(x: start.x + dx, y: start.y),
                              control2: CGPoint(x: end.x - dx, y: end.y))
                let on = selected != nil && lit.contains(e.from) && lit.contains(e.to)
                let colour = colours[e.to] ?? .gray
                if selected == nil {
                    context.stroke(path, with: .color(colour.opacity(0.45)), lineWidth: 1.2)
                } else if on {
                    context.stroke(path, with: .color(colour.opacity(0.95)), lineWidth: 2.2)
                } else {
                    context.stroke(path, with: .color(Color.gray.opacity(0.12)), lineWidth: 1)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
    }
}

/// One item in the chart: a single line (icon, title, working identifier).
struct ChartNode: View {
    let model: AppModel
    var key: String
    var selected: Bool
    var dimmed: Bool

    var body: some View {
        ItemLine(model: model, key: key, iconWidth: 16)
            .font(.callout)
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(selected ? Color.accentColor.opacity(0.16) : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.14), lineWidth: selected ? 1.5 : 0.5)
            )
            .opacity(dimmed ? 0.35 : 1)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.openKey(key) }
            .simultaneousGesture(TapGesture().onEnded { model.tableSelection = key })
            .contextMenu {
                Button("Open") { model.openKey(key) }
                if let item = model.item(forKey: key) {
                    Button("Add to Working Area") { model.addToWorkingArea(item) }
                        .disabled(model.workingArea.contains(item))
                }
            }
    }
}

extension Sequence where Element: Hashable {
    /// The elements in order, without repeats.
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}

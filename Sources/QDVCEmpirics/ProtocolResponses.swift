import AppKit
import EmpiricsCore
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    /// The protocol shown in Protocol Responses: the one chosen, or the
    /// first.
    var shownReportProtocol: String? {
        reportProtocol.flatMap { project.protocols[$0] != nil ? $0 : nil } ?? project.sortedProtocols.first?.key
    }

    /// The deductive layer the Protocol Responses report reads: the one chosen, else
    /// the active layer if it is deductive, else the first deductive layer
    /// where files follow the shown protocol.
    var shownReportProtocolLayer: String? {
        if let l = reportProtocolLayer, project.layer(l)?.isDeductive == true { return l }
        if let a = activeLayer, a.isDeductive { return a.key }
        if let pr = shownReportProtocol, let l = project.deductiveLayers.first(where: { $0.protocols.values.contains(pr) }) {
            return l.key
        }
        return project.deductiveLayers.first?.key
    }
}

/// Reports › Protocol Responses: one protocol across the empirical files that
/// follow it in a deductive layer. A row per file, a column per protocol
/// item; each cell shows the summary written for that item in that file
/// (the bubble under a protocol label, in the file), with a button for the
/// full answer (the item's prompt and response in the file). Double-click
/// a cell to write or change its summary. The protocol and layer are chosen
/// in the bar below: like every page, it starts with its scrolling content
/// at the top (docs/MAINTENANCE.md §Layout).
struct ProtocolResponsesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let protocols = model.project.sortedProtocols
        let key = model.shownReportProtocol
        let layer = model.shownReportProtocolLayer
        let report = key.flatMap { k in layer.flatMap { ProtocolResponses.make(model.project, protocol: k, layer: $0) } }
        VStack(spacing: 0) {
            if let report {
                if report.studyProtocol.items.isEmpty {
                    ContentUnavailableView("No Items Yet", systemImage: "list.bullet.rectangle",
                                           description: Text("“\(report.studyProtocol.title)” has no items yet. Add them on its page."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if report.rows.isEmpty {
                    ContentUnavailableView("No Files Follow It Here", systemImage: "list.bullet.rectangle",
                                           description: Text("No empirical file follows “\(report.studyProtocol.title)” in \(model.project.layer(report.layer)?.name ?? "this layer") yet. Mark prompts and responses in a file (Q and A), or choose another layer below."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProtocolResponsesTable(model: model, report: report)
                }
            } else if protocols.isEmpty {
                ContentUnavailableView("No Protocols", systemImage: "list.bullet.rectangle",
                                       description: Text("Make a protocol on the Protocols page first."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("No Deductive Layer", systemImage: "square.3.layers.3d",
                                       description: Text("Protocols are applied on deductive layers."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer(protocols: protocols, key: key, layer: layer, report: report)
        }
    }

    func footer(protocols: [StudyProtocol], key: String?, layer: String?, report: ProtocolResponses?) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Picker("Protocol", selection: Binding(
                    get: { key ?? "" },
                    set: { v in
                        model.reportProtocol = v.isEmpty ? nil : v
                        model.tableSelection = nil
                    }
                )) {
                    if protocols.isEmpty { Text("No protocols").tag("") }
                    ForEach(protocols) { pr in Text(model.itemLabel(pr.key)).tag(pr.key) }
                }
                .fixedSize()
                Picker("Layer", selection: Binding(
                    get: { layer ?? "" },
                    set: { v in
                        model.reportProtocolLayer = v.isEmpty ? nil : v
                        model.tableSelection = nil
                    }
                )) {
                    ForEach(model.project.deductiveLayers) { l in Text(l.name).tag(l.key) }
                }
                .fixedSize()
                if let key {
                    Button("Edit Protocol") { model.show(.studyProtocol(key)) }
                }
                Spacer(minLength: 8)
                if let report {
                    Text(summary(report)).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    Button("Copy as CSV") { copyCSV(report) }
                        .help("Copy the summaries to paste into a spreadsheet")
                    Button("Save as CSV…") { saveCSV(report) }
                        .help("Save the summaries as a CSV file")
                }
            }
            .controlSize(.small)
            .padding(8)
        }
    }

    func summary(_ r: ProtocolResponses) -> String {
        let cells = r.rows.flatMap { row in r.studyProtocol.items.map { row.cell($0.key) } }
        let written = cells.filter { !$0.summary.isEmpty }.count
        let marked = cells.filter(\.isMarked).count
        return "\(r.rows.count) file\(r.rows.count == 1 ? "" : "s") · \(marked) item\(marked == 1 ? "" : "s") marked · \(written) summar\(written == 1 ? "y" : "ies")"
    }

    func csv(_ r: ProtocolResponses) -> String {
        r.csv(workingIDs: model.index.workingID, title: { model.pseudonymousTitle($0) })
    }

    func copyCSV(_ r: ProtocolResponses) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv(r), forType: .string)
        model.notice = Notice(text: "Copied the Protocol Responses for “\(r.studyProtocol.title)” as CSV (\(r.rows.count) row\(r.rows.count == 1 ? "" : "s")).")
    }

    func saveCSV(_ r: ProtocolResponses) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = (r.studyProtocol.title.isEmpty ? "Protocol" : r.studyProtocol.title) + " report.csv"
        panel.message = "Save the Protocol Responses summaries as CSV."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(csv(r).utf8).write(to: url, options: .atomic)
        } catch {
            model.errorMessage = "Couldn't save the report.\n\n\(error.localizedDescription)"
        }
    }
}

/// The report's table: a header row pinned at the top (the items), then a
/// row per file. Fixed column widths so the header lines up; the whole
/// table scrolls both ways. (Takes the model directly: rows carry context
/// menus and popovers.)
struct ProtocolResponsesTable: View {
    let model: AppModel
    let report: ProtocolResponses

    static let fileWidth: CGFloat = 230
    static let itemWidth: CGFloat = 240

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(report.rows.enumerated()), id: \.element.id) { i, row in
                        rowView(row, index: i)
                    }
                } header: {
                    header
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    var header: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text("Empirical File")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(width: Self.fileWidth, alignment: .leading)
            ForEach(Array(report.studyProtocol.items.enumerated()), id: \.element.id) { i, item in
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text("\(i + 1)").monospacedDigit().foregroundStyle(Color(nsColor: .protocolSegment))
                    Text(item.label.isEmpty ? "Untitled" : item.label).lineLimit(2)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(width: Self.itemWidth, alignment: .leading)
                .help(item.text.isEmpty ? item.label : item.text)
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    func rowView(_ row: ProtocolResponses.Row, index: Int) -> some View {
        let selected = model.tableSelection == row.file
        return HStack(alignment: .top, spacing: 0) {
            ItemLine(model: model, key: row.file, iconWidth: 16)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: Self.fileWidth, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.show(.file(row.file)) }
            ForEach(report.studyProtocol.items) { item in
                ProtocolResponsesCell(model: model, layer: report.layer, file: row.file, item: item.key, cell: row.cell(item.key))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: Self.itemWidth, alignment: .topLeading)
            }
        }
        .background(selected ? Color.accentColor.opacity(0.18) : (index % 2 == 1 ? Color.primary.opacity(0.035) : Color.clear))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.tableSelection = row.file })
        .contextMenu {
            Button("Open Empirical File") { model.show(.file(row.file)) }
        }
    }
}

/// One cell: the item's summary for the file, a button for the full answer
/// (when the item is marked there), and double-click to write the summary.
struct ProtocolResponsesCell: View {
    let model: AppModel
    var layer: String
    var file: String
    var item: String
    var cell: ProtocolResponses.Cell
    @State private var showAnswer = false
    @State private var editing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !cell.summary.isEmpty {
                Text(cell.summary)
                    .lineLimit(6)
                    .fixedSize(horizontal: false, vertical: true)
            } else if cell.isMarked {
                Text("No summary yet").foregroundStyle(.tertiary)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
            if cell.isMarked {
                Button {
                    showAnswer = true
                } label: {
                    Label("Full Answer", systemImage: "text.quote")
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .font(.caption)
                .help("Read the item's prompt and response in this file")
                .popover(isPresented: $showAnswer, arrowEdge: .bottom) {
                    ProtocolAnswerView(model: model, file: file, item: item, cell: cell)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { editing = true }
        .popover(isPresented: $editing, arrowEdge: .bottom) {
            ProtocolSummaryEditor(model: model, layer: layer, file: file, item: item)
        }
        .help(cell.summary.isEmpty ? "Double-click to write a summary" : cell.summary + "\n\nDouble-click to edit.")
    }
}

/// The full answer for an item in a file: its prompt and response
/// segments' text, each with Show in File.
struct ProtocolAnswerView: View {
    let model: AppModel
    var file: String
    var item: String
    var cell: ProtocolResponses.Cell

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(model.protocolItemTitle(item)).font(.headline)
            Text(model.itemLabel(file)).font(.caption).foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(cell.prompts + cell.responses, id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(cell.prompts.contains(key) ? "Prompt" : "Response")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Color(nsColor: .protocolSegment))
                            Text(text(key))
                                .textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                            Button("Show in File") { model.showSelection(key) }
                                .controlSize(.small)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 380)
        }
        .padding(12)
        .frame(width: 440)
    }

    func text(_ key: String) -> String {
        guard let s = model.project.selection(key) else { return "(This segment no longer exists.)" }
        return model.quoteText(s) ?? "(The text can't be read here: the full-texts folder isn't available on this Mac.)"
    }
}

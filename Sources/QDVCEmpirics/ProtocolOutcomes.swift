import AppKit
import EmpiricsCore
import SwiftUI
import UniformTypeIdentifiers

extension AppModel {
    /// The layer whose codes Protocol Outcomes counts: the one chosen, if it
    /// is of the right kind; else the active layer, if it is; else the
    /// protocol's deductive layer (a priori codes) or the inductive layer the
    /// code pages show.
    var shownOutcomeCodeLayer: String? {
        let kind = outcomeCoding.layerKind
        if let l = outcomeCodeLayer, project.layer(l)?.kind == kind { return l }
        if let a = activeLayer, a.kind == kind { return a.key }
        if kind == .deductive { return shownReportProtocolLayer }
        return inductiveLayer?.key
    }
}

/// Reports › Protocol Outcomes: where codes are grounded, protocol-wise.
/// Choose a protocol (and the deductive layer whose segments count) and a
/// kind of code (a priori, open or theorising, and their layer): a row per
/// code, a column per protocol item's prompt and response, and in each cell
/// how many of the code's instances lie in text marked as that part of that
/// item, shaded by count; then those elsewhere, and the total. Click a cell
/// for its instances. Shows, for instance, how far inductive codes rest on
/// answers to particular questions, or on the interviewer's prompts.
struct ProtocolOutcomesPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let protocols = model.project.sortedProtocols
        let key = model.shownReportProtocol
        let segmentLayer = model.shownReportProtocolLayer
        let codeLayer = model.shownOutcomeCodeLayer
        let report = key.flatMap { k in
            segmentLayer.flatMap { s in
                codeLayer.flatMap { c in
                    ProtocolOutcomes.make(model.project, protocol: k, segmentLayer: s, coding: model.outcomeCoding, codeLayer: c)
                }
            }
        }
        VStack(spacing: 0) {
            if let report {
                if report.studyProtocol.items.isEmpty {
                    ContentUnavailableView("No Items Yet", systemImage: "list.bullet.rectangle",
                                           description: Text("“\(report.studyProtocol.title)” has no items yet. Add them on its page."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if report.rows.isEmpty {
                    ContentUnavailableView("No \(model.outcomeCoding.label)", systemImage: "tag",
                                           description: Text("There are no \(model.outcomeCoding.label.lowercased()) in \(model.project.layer(report.codeLayer)?.name ?? "this layer") yet."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProtocolOutcomesTable(model: model, report: report)
                }
            } else if protocols.isEmpty {
                ContentUnavailableView("No Protocols", systemImage: "list.bullet.rectangle",
                                       description: Text("Make a protocol on the Protocols page first."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView("Nothing to Count", systemImage: "square.3.layers.3d",
                                       description: Text("Choose a deductive layer for the protocol's segments, and a layer with \(model.outcomeCoding.label.lowercased()), below."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer(protocols: protocols, key: key, segmentLayer: segmentLayer, codeLayer: codeLayer, report: report)
        }
    }

    func footer(protocols: [StudyProtocol], key: String?, segmentLayer: String?, codeLayer: String?,
                report: ProtocolOutcomes?) -> some View {
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
                .help("The protocol, and below, the deductive layer whose prompts and responses count")
                Picker("in", selection: Binding(
                    get: { segmentLayer ?? "" },
                    set: { v in model.reportProtocolLayer = v.isEmpty ? nil : v }
                )) {
                    ForEach(model.project.deductiveLayers) { l in Text(l.name).tag(l.key) }
                }
                .fixedSize()
                Divider().frame(height: 16)
                Picker("Codes", selection: Binding(
                    get: { model.outcomeCoding },
                    set: { v in
                        model.outcomeCoding = v
                        model.tableSelection = nil
                    }
                )) {
                    ForEach(OutcomeCoding.allCases, id: \.self) { c in Text(c.label).tag(c) }
                }
                .fixedSize()
                Picker("from", selection: Binding(
                    get: { codeLayer ?? "" },
                    set: { v in model.outcomeCodeLayer = v.isEmpty ? nil : v }
                )) {
                    ForEach(model.project.layers.filter { $0.kind == model.outcomeCoding.layerKind }) { l in
                        Text(l.name).tag(l.key)
                    }
                }
                .fixedSize()
                Spacer(minLength: 8)
                if let report {
                    Text(summary(report)).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    Button("Copy as CSV") { copyCSV(report) }
                        .help("Copy the counts to paste into a spreadsheet")
                    Button("Save as CSV…") { saveCSV(report) }
                        .help("Save the counts as a CSV file")
                }
            }
            .controlSize(.small)
            .padding(8)
        }
    }

    func summary(_ r: ProtocolOutcomes) -> String {
        let all = r.rows.reduce(0) { $0 + $1.instances.count }
        let elsewhere = r.rows.reduce(0) { $0 + $1.elsewhere.count }
        return "\(r.rows.count) code\(r.rows.count == 1 ? "" : "s") · \(all) instance\(all == 1 ? "" : "s") · \(all - elsewhere) in the protocol"
    }

    func csv(_ r: ProtocolOutcomes) -> String {
        r.csv(workingIDs: model.index.workingID, title: { model.itemTitle($0) })
    }

    func copyCSV(_ r: ProtocolOutcomes) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv(r), forType: .string)
        model.notice = Notice(text: "Copied Protocol Outcomes for “\(r.studyProtocol.title)” as CSV (\(r.rows.count) row\(r.rows.count == 1 ? "" : "s")).")
    }

    func saveCSV(_ r: ProtocolOutcomes) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = (r.studyProtocol.title.isEmpty ? "Protocol" : r.studyProtocol.title) + " outcomes.csv"
        panel.message = "Save the Protocol Outcomes counts as CSV."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(csv(r).utf8).write(to: url, options: .atomic)
        } catch {
            model.errorMessage = "Couldn't save the report.\n\n\(error.localizedDescription)"
        }
    }
}

/// The counts: a header row pinned at the top (each item's prompt and
/// response), a row per code. Fixed widths; scrolls both ways. (Takes the
/// model directly: cells carry popovers.)
struct ProtocolOutcomesTable: View {
    let model: AppModel
    let report: ProtocolOutcomes

    static let codeWidth: CGFloat = 230
    static let countWidth: CGFloat = 92

    var body: some View {
        let peak = max(1, report.maxCount)
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(report.rows.enumerated()), id: \.element.id) { i, row in
                        rowView(row, index: i, peak: peak)
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
            Text(report.coding.label)
                .padding(.horizontal, 8)
                .frame(width: Self.codeWidth, alignment: .leading)
            ForEach(Array(report.studyProtocol.items.enumerated()), id: \.element.id) { i, item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(i + 1)").monospacedDigit().foregroundStyle(Color(nsColor: .protocolSegment))
                        Text(item.label.isEmpty ? "Untitled" : item.label).lineLimit(1)
                    }
                    .padding(.horizontal, 8)
                    .help(item.text.isEmpty ? item.label : item.text)
                    HStack(spacing: 0) {
                        ForEach(ProtocolPart.allCases, id: \.self) { part in
                            Text(part.label)
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .frame(width: Self.countWidth, alignment: .trailing)
                        }
                    }
                }
                .frame(width: 2 * Self.countWidth, alignment: .leading)
                .overlay(alignment: .leading) { Divider() }
            }
            Text("Elsewhere")
                .padding(.horizontal, 8)
                .frame(width: Self.countWidth, alignment: .trailing)
                .help("Instances outside every prompt and response of the protocol (or in files that don't follow it in this layer)")
                .overlay(alignment: .leading) { Divider() }
            Text("Total")
                .padding(.horizontal, 8)
                .frame(width: Self.countWidth, alignment: .trailing)
        }
        .font(.callout.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    func rowView(_ row: ProtocolOutcomes.Row, index: Int, peak: Int) -> some View {
        let selected = model.tableSelection == row.code
        return HStack(alignment: .center, spacing: 0) {
            ItemLine(model: model, key: row.code, iconWidth: 16)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: Self.codeWidth, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.showTag(row.code) }
            ForEach(report.columns, id: \.self) { column in
                OutcomeCell(model: model, instances: row.cells[column] ?? [], peak: peak,
                            title: "\(model.itemTitle(row.code)) · \(model.protocolItemTitle(column.item)) · \(column.part.label)")
                    .frame(width: Self.countWidth)
            }
            OutcomeCell(model: model, instances: row.elsewhere, peak: peak, title: "\(model.itemTitle(row.code)) · Elsewhere")
                .frame(width: Self.countWidth)
            Text("\(row.instances.count)")
                .monospacedDigit()
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
                .frame(width: Self.countWidth, alignment: .trailing)
        }
        .background(selected ? Color.accentColor.opacity(0.18) : (index % 2 == 1 ? Color.primary.opacity(0.035) : Color.clear))
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded { model.tableSelection = row.code })
        .contextMenu {
            Button("Open \(model.itemKind(row.code))") { model.showTag(row.code) }
        }
    }
}

/// A count, shaded by how large it is; click it for the instances.
struct OutcomeCell: View {
    let model: AppModel
    var instances: [String]
    var peak: Int
    var title: String
    @State private var showing = false

    var body: some View {
        let n = instances.count
        Text(n == 0 ? "–" : "\(n)")
            .monospacedDigit()
            .foregroundStyle(n == 0 ? Color.secondary.opacity(0.6) : Color.primary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .background(Color(nsColor: .protocolSegment).opacity(n == 0 ? 0 : 0.08 + 0.37 * Double(n) / Double(max(1, peak))))
            .contentShape(Rectangle())
            .onTapGesture { if n > 0 { showing = true } }
            .help(n == 0 ? "" : "\(n) instance\(n == 1 ? "" : "s"): click to read them")
            .popover(isPresented: $showing, arrowEdge: .bottom) {
                OutcomeInstances(model: model, title: title, instances: instances)
            }
    }
}

/// The instances behind a count: each selection's text, its file, and Show
/// in File.
struct OutcomeInstances: View {
    let model: AppModel
    var title: String
    var instances: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline).lineLimit(2)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(instances, id: \.self) { key in
                        if let s = model.project.selection(key) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(model.itemLabel(s.fileKey))
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Text(model.quoteText(s) ?? "(The text can't be read here.)")
                                    .lineLimit(8)
                                    .textSelection(.enabled)
                                    .fixedSize(horizontal: false, vertical: true)
                                Button("Show in File") { model.showSelection(key) }
                                    .controlSize(.small)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 400)
        }
        .padding(12)
        .frame(width: 440)
    }
}

import AppKit
import EmpiricsCore
import SwiftUI
import UniformTypeIdentifiers

/// Reporting › Attribute Sheet Report: every response to one attribute sheet, as a table
/// (one row per response sheet, plus the associated items nobody has
/// answered yet; one column per question). The attribute sheet is chosen in the
/// bar below the report: like every page, it starts with its scrolling
/// content at the top (docs/MAINTENANCE.md §Layout).
struct AttributeSheetReportPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let books = model.project.sortedAttributeSheets
        let key = model.shownReportAttributeSheet
        let report = key.flatMap { k in
            AttributeSheetReport.make(model.project, attributeSheet: k, title: { model.itemTitle($0) },
                                person: { model.personName($0) ?? "" })
        }
        VStack(spacing: 0) {
            if let report {
                if report.rows.isEmpty {
                    ContentUnavailableView("No Responses Yet", systemImage: "tablecells",
                                           description: Text("“\(report.attributeSheet.title)” isn't associated with any empirical file, interviewee, open code or axial code yet. Add it from their inspectors."))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ReportTable(model: model, report: report)
                }
            } else {
                ContentUnavailableView("No Attribute Sheets", systemImage: "text.book.closed",
                                       description: Text("Make an attribute sheet on the Attribute Sheets page first."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            footer(books: books, key: key, report: report)
        }
    }

    func footer(books: [AttributeSheet], key: String?, report: AttributeSheetReport?) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Picker("Attribute Sheet", selection: Binding(
                    get: { key ?? "" },
                    set: { v in
                        model.reportAttributeSheet = v.isEmpty ? nil : v
                        model.tableSelection = nil
                    }
                )) {
                    if books.isEmpty { Text("No attribute sheets").tag("") }
                    ForEach(books) { cb in Text(model.itemLabel(cb.key)).tag(cb.key) }
                }
                .fixedSize()
                if let key {
                    Button("Edit Attribute Sheet") { model.show(.attributeSheet(key)) }
                }
                Spacer(minLength: 8)
                if let report {
                    Text(summary(report)).font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                    Button("Copy as CSV") { copyCSV(report) }
                        .help("Copy the report to paste into a spreadsheet (names are pseudonyms)")
                    Button("Save as CSV…") { saveCSV(report) }
                        .help("Save the report as a CSV file (names are pseudonyms)")
                }
            }
            .controlSize(.small)
            .padding(8)
        }
    }

    func summary(_ r: AttributeSheetReport) -> String {
        let complete = r.rows.filter { $0.status == .complete }.count
        let flagged = r.rows.filter { $0.status == .flagged }.count
        let open = r.rows.filter { $0.status == .notStarted }.count
        return "\(complete) complete · \(flagged) flagged · \(open) not started"
    }

    /// CSV with pseudonyms only, whatever View › Show Real Names says.
    func csv(_ r: AttributeSheetReport) -> String {
        r.csv(workingIDs: model.index.workingID,
              title: { model.pseudonymousTitle($0) },
              kind: { model.itemKind($0) },
              person: { model.project.personName($0) ?? "" })
    }

    func copyCSV(_ r: AttributeSheetReport) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv(r), forType: .string)
        model.notice = Notice(text: "Copied the report for “\(r.attributeSheet.title)” as CSV (\(r.rows.count) row\(r.rows.count == 1 ? "" : "s")).")
    }

    func saveCSV(_ r: AttributeSheetReport) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = (r.attributeSheet.title.isEmpty ? "Attribute Sheet" : r.attributeSheet.title) + " report.csv"
        panel.message = "Save the attribute sheet report as CSV. Names are pseudonyms."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try Data(csv(r).utf8).write(to: url, options: .atomic)
        } catch {
            model.errorMessage = "Couldn't save the report.\n\n\(error.localizedDescription)"
        }
    }
}

/// The report's table: a header row pinned at the top, then one row per
/// response sheet. Columns have fixed widths so the header lines up; the
/// whole table scrolls both ways. (Takes the model directly: rows carry
/// context menus.)
struct ReportTable: View {
    let model: AppModel
    let report: AttributeSheetReport

    static let itemWidth: CGFloat = 250
    static let researcherWidth: CGFloat = 130
    static let statusWidth: CGFloat = 110

    static func width(_ q: AttributeSheetQuestion) -> CGFloat {
        q.type == .text ? 240 : 170
    }

    var body: some View {
        let showResearcher = !model.project.researchers.isEmpty
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                Section {
                    ForEach(Array(report.rows.enumerated()), id: \.element.id) { i, row in
                        rowView(row, index: i, showResearcher: showResearcher)
                    }
                } header: {
                    header(showResearcher: showResearcher)
                }
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    func header(showResearcher: Bool) -> some View {
        HStack(alignment: .bottom, spacing: 0) {
            headCell("Item", width: Self.itemWidth)
            if showResearcher { headCell("Researcher", width: Self.researcherWidth) }
            headCell("Status", width: Self.statusWidth)
            ForEach(report.attributeSheet.questions) { q in
                HStack(spacing: 3) {
                    Text(q.label).lineLimit(1)
                    RequirementMark(requirement: q.requirement)
                }
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 7)
                .frame(width: Self.width(q), alignment: .leading)
                .help(q.text.isEmpty ? q.label : q.text)
            }
        }
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }

    func headCell(_ title: String, width: CGFloat) -> some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 7)
            .frame(width: width, alignment: .leading)
    }

    func rowView(_ row: AttributeSheetReport.Row, index: Int, showResearcher: Bool) -> some View {
        let selected = model.tableSelection == row.target
        return HStack(alignment: .top, spacing: 0) {
            ItemLine(model: model, key: row.target, iconWidth: 16)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: Self.itemWidth, alignment: .leading)
            if showResearcher {
                Text(row.researcher.isEmpty ? "—" : (model.personName(row.researcher) ?? "—"))
                    .foregroundStyle(row.researcher.isEmpty ? HierarchicalShapeStyle.tertiary : HierarchicalShapeStyle.primary)
                    .lineLimit(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: Self.researcherWidth, alignment: .leading)
            }
            status(row)
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(width: Self.statusWidth, alignment: .leading)
            ForEach(report.attributeSheet.questions) { q in
                answer(row, q)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .frame(width: Self.width(q), alignment: .leading)
            }
        }
        .background(selected ? Color.accentColor.opacity(0.18) : (index % 2 == 1 ? Color.primary.opacity(0.035) : Color.clear))
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open(row) }
        .simultaneousGesture(TapGesture().onEnded { model.tableSelection = row.target })
        .contextMenu {
            Button("Open \(model.itemKind(row.target))") { model.openKey(row.target) }
            Button(row.sheet == nil ? "Fill In Response Sheet…" : "Open Response Sheet…") { open(row) }
        }
    }

    /// Double-click: the response sheet (this Mac's researcher's own, or
    /// theirs to fill in).
    func open(_ row: AttributeSheetReport.Row) {
        model.openResponseSheet(attributeSheet: report.attributeSheet.key, target: row.target)
    }

    @ViewBuilder
    func status(_ row: AttributeSheetReport.Row) -> some View {
        switch row.status {
        case .notStarted:
            Label("Not started", systemImage: "circle.dashed").foregroundStyle(.secondary)
        case .flagged:
            Label("Flagged", systemImage: "exclamationmark.circle.fill").foregroundStyle(.orange)
                .help("Unanswered: " + row.completeness.missingFlagged.map(\.label).joined(separator: ", "))
        case .complete:
            Label("Complete", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
    }

    @ViewBuilder
    func answer(_ row: AttributeSheetReport.Row, _ q: AttributeSheetQuestion) -> some View {
        let values = row.answer(q.key)?.values ?? []
        if !values.isEmpty {
            let text = values.joined(separator: q.type == .chooseMany ? ", " : "")
            Text(text)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .help(text)
        } else if row.sheet != nil, q.requirement != .optional {
            Text("Unanswered").foregroundStyle(.orange)
                .help("Mandatory question without an answer")
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

import AppKit
import EmpiricsCore
import SwiftUI

// The list pages of the sidebar: plain tables. Selecting a row shows it in
// the inspector; double-clicking opens its page and puts it in the Working
// Area.

extension EmpiricalFile {
    var statusOrder: Int { CodingStatus.allCases.firstIndex(of: status) ?? 0 }
    var sortID: String { customID.isEmpty ? displayTitle : customID }
    var kindLabel: String { kind.label }
}

extension QDACode {
    var evidenceCount: Int { evidence.count }
    var questionCount: Int { questions.count }
}

extension Codebook {
    var questionCount: Int { questions.count }
    var appliesToLabel: String {
        CodebookTarget.allCases.filter { appliesTo.contains($0) }.map(\.label).joined(separator: ", ")
    }
}

/// The bar under a table: add buttons, a filter, a count.
struct TableFooter<Leading: View>: View {
    var count: String
    @Binding var filter: String
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        HStack(spacing: 8) {
            leading()
            Spacer()
            Text(count).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            TextField("Filter", text: $filter)
                .textFieldStyle(.roundedBorder)
                .frame(width: 200)
        }
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.bar)
    }
}

/// The line under a page's title: what this page is.
struct PageHeader: View {
    var title: String
    var subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.title2.weight(.semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Empirical files

struct FilesTable: View {
    @Environment(AppModel.self) private var model

    var columns: [DataColumn<EmpiricalFile>] {
        let model = self.model
        var c: [DataColumn<EmpiricalFile>] = []
        c.append(DataColumn<EmpiricalFile>("Status", width: 120, order: DataColumn<EmpiricalFile>.number { $0.statusOrder }) { (f: EmpiricalFile) in
            Label(f.status.label, systemImage: f.status.symbol).foregroundStyle(f.status.tint)
        })
        c.append(DataColumn<EmpiricalFile>("ID", width: 130, order: DataColumn<EmpiricalFile>.text { $0.customID }) { (f: EmpiricalFile) in
            Text(f.customID).font(.body.monospaced())
        })
        c.append(DataColumn<EmpiricalFile>("Title", minWidth: 140, order: DataColumn<EmpiricalFile>.text { $0.displayTitle }) { (f: EmpiricalFile) in
            Text(f.displayTitle)
        })
        c.append(DataColumn<EmpiricalFile>("Date", width: 100, order: DataColumn<EmpiricalFile>.text { $0.date }) { (f: EmpiricalFile) in
            Text(f.date).monospacedDigit()
        })
        c.append(DataColumn<EmpiricalFile>("Kind", width: 90, order: DataColumn<EmpiricalFile>.text { $0.kindLabel }) { (f: EmpiricalFile) in
            Text(f.kindLabel)
        })
        c.append(DataColumn<EmpiricalFile>("Selections", width: 84, alignment: .trailing,
                            order: DataColumn<EmpiricalFile>.number { model.index.selectionCount[$0.key] ?? 0 }) { (f: EmpiricalFile) in
            Text("\(model.index.selectionCount[f.key] ?? 0)").monospacedDigit()
        })
        c.append(DataColumn<EmpiricalFile>("Location", minWidth: 120, order: DataColumn<EmpiricalFile>.text { $0.path }) { (f: EmpiricalFile) in
            Text(f.path).font(.caption.monospaced()).foregroundStyle(.secondary)
        })
        return c
    }

    var body: some View {
        @Bindable var model = model
        let coded = model.project.files.values.filter { $0.status == .coded }.count
        VStack(spacing: 0) {
            PageHeader(title: "Empirical Files",
                       subtitle: "Transcripts, notes and articles in the full-texts folder. Double-click one to code it.")
            Divider()
            DataTable(rows: model.visibleFiles, columns: columns, selection: $model.tableSelection, defaultSort: 1,
                      emptyText: "No files yet. Add them from the full-texts folder with Add below.",
                      onOpen: { key in model.show(.file(key)) }) { (f: EmpiricalFile) in
                Button("Open") { model.show(.file(f.key)) }
                Button("Add to Working Area") { model.addToWorkingArea(.file(f.key)) }
                    .disabled(model.workingArea.contains(.file(f.key)))
                Divider()
                ForEach(CodingStatus.allCases, id: \.self) { s in
                    Button("Mark as \(s.label)") { model.setStatus(s, file: f.key) }
                        .disabled(f.status == s)
                }
                Divider()
                Button("Remove from Project…") { model.removeFile(f.key) }
            }
            TableFooter(count: "\(coded) of \(model.project.files.count) coded", filter: $model.fileFilter) {
                Menu {
                    Button("Add Files…") { model.addFilesPanel() }
                    Button("Add New Files from Full-Texts Folder…") { model.scanForNewFiles() }
                    Divider()
                    Button("Choose Full-Texts Folder…") { model.chooseFullTextsFolder() }
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .fixedSize()
                Button("Next File Not Yet Coded") { model.nextUncodedFile() }
            }
        }
    }
}

// MARK: - Codes

struct CodesTable: View {
    @Environment(AppModel.self) private var model
    let kind: CodeKind
    @State private var filter = ""

    var columns: [DataColumn<QDACode>] {
        let model = self.model
        var c: [DataColumn<QDACode>] = []
        c.append(DataColumn<QDACode>("Name", minWidth: 160, order: DataColumn<QDACode>.text { $0.name }) { (code: QDACode) in
            HStack(spacing: 6) {
                CodeDot(color: code.color)
                Text(code.name)
            }
        })
        c.append(DataColumn<QDACode>("Evidence", width: 80, alignment: .trailing, order: DataColumn<QDACode>.number { $0.evidenceCount }) { (code: QDACode) in
            Text("\(code.evidence.count)").monospacedDigit()
        })
        c.append(DataColumn<QDACode>("Files", width: 60, alignment: .trailing,
                            order: DataColumn<QDACode>.number { model.index.filesForCode[$0.key]?.count ?? 0 }) { (code: QDACode) in
            Text("\(model.index.filesForCode[code.key]?.count ?? 0)").monospacedDigit()
        })
        c.append(DataColumn<QDACode>("Evidence For", minWidth: 120, order: DataColumn<QDACode>.text { self.parentNames($0) }) { (code: QDACode) in
            Text(self.parentNames(code)).foregroundStyle(.secondary)
        })
        c.append(DataColumn<QDACode>("Questions", width: 84, alignment: .trailing, order: DataColumn<QDACode>.number { $0.questionCount }) { (code: QDACode) in
            Text(code.questions.isEmpty ? "" : "\(code.questions.count)").monospacedDigit()
        })
        c.append(DataColumn<QDACode>("Quick", width: 56, alignment: .trailing,
                            order: DataColumn<QDACode>.number { model.quickSlot(of: $0.key) ?? 99 }) { (code: QDACode) in
            Text(model.quickSlot(of: code.key).map { "\($0)" } ?? "").monospacedDigit()
        })
        return c
    }

    var body: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all: [QDACode] = (model.activeLayer.map { Array($0.codes.values) } ?? []).filter { $0.kind == kind }
        let shown: [QDACode] = q.isEmpty ? all : all.filter { c in
            c.name.localizedCaseInsensitiveContains(q) || c.description.localizedCaseInsensitiveContains(q)
        }
        let what = kind == .open ? "Codes evidenced directly by selections" : "Codes built from open codes and other axial codes"
        let layerName = model.activeLayer?.name ?? ""
        VStack(spacing: 0) {
            PageHeader(title: kind == .open ? "Open Codes" : "Axial Codes",
                       subtitle: "\(what), in the layer “\(layerName)”. Double-click one to open its evidence.")
            Divider()
            DataTable(rows: shown, columns: columns, selection: $model.tableSelection, defaultSort: 0,
                      emptyText: kind == .open ? "No open codes in this layer yet." : "No axial codes in this layer yet.",
                      onOpen: { key in model.show(.code(key)) }) { (code: QDACode) in
                Button("Open") { model.show(.code(code.key)) }
                Button("Add to Working Area") { model.addToWorkingArea(.code(code.key)) }
                    .disabled(model.workingArea.contains(.code(code.key)))
                if code.kind == .open {
                    Menu("Quick Code") {
                        ForEach(1...9, id: \.self) { n in
                            Button("\(n)") { model.assignQuickCode(code.key, slot: n) }
                        }
                        Divider()
                        Button("None") {
                            if let s = model.quickSlot(of: code.key) { model.assignQuickCode(nil, slot: s) }
                        }
                    }
                }
                if model.project.layers.count > 1 {
                    Button("Move to Layer…") { model.sheet = .moveToLayer(code.key) }
                }
                Divider()
                Button("Delete Code…") { model.deleteCode(code.key) }
            }
            TableFooter(count: "\(all.count) code\(all.count == 1 ? "" : "s")", filter: $filter) {
                Button {
                    model.sheet = .newCode(kind: kind, parent: nil, child: nil)
                } label: {
                    Label(kind == .open ? "New Open Code" : "New Axial Code", systemImage: "plus")
                }
                LayerMenu(model: model)
                    .fixedSize()
            }
        }
    }

    func parentNames(_ c: QDACode) -> String {
        (model.index.parents[c.key] ?? []).compactMap { model.project.code($0)?.name }.sorted().joined(separator: ", ")
    }
}

// MARK: - Codebooks

struct CodebooksTable: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var columns: [DataColumn<Codebook>] {
        var c: [DataColumn<Codebook>] = []
        c.append(DataColumn<Codebook>("Title", minWidth: 180, order: DataColumn<Codebook>.text { $0.title }) { (cb: Codebook) in
            Label(cb.title, systemImage: "text.book.closed")
        })
        c.append(DataColumn<Codebook>("Questions", width: 84, alignment: .trailing, order: DataColumn<Codebook>.number { $0.questionCount }) { (cb: Codebook) in
            Text("\(cb.questions.count)").monospacedDigit()
        })
        c.append(DataColumn<Codebook>("Applies To", minWidth: 160, order: DataColumn<Codebook>.text { $0.appliesToLabel }) { (cb: Codebook) in
            Text(cb.appliesToLabel)
        })
        c.append(DataColumn<Codebook>("Response Sheets", width: 150) { (cb: Codebook) in
            Text(self.sheetSummary(cb)).foregroundStyle(.secondary)
        })
        return c
    }

    var body: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all: [Codebook] = Array(model.project.codebooks.values)
        let shown: [Codebook] = q.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(q) }
        VStack(spacing: 0) {
            PageHeader(title: "Codebooks",
                       subtitle: "Questions answered about each file, open code or axial code they are associated with. Double-click one to edit its questions.")
            Divider()
            DataTable(rows: shown, columns: columns, selection: $model.tableSelection, defaultSort: 0,
                      emptyText: "No codebooks yet.",
                      onOpen: { key in model.show(.codebook(key)) }) { (cb: Codebook) in
                Button("Open") { model.show(.codebook(cb.key)) }
                Button("Add to Working Area") { model.addToWorkingArea(.codebook(cb.key)) }
                    .disabled(model.workingArea.contains(.codebook(cb.key)))
                Divider()
                Button("Delete Codebook…") { model.deleteCodebook(cb.key) }
            }
            TableFooter(count: "\(all.count) codebook\(all.count == 1 ? "" : "s")", filter: $filter) {
                Button {
                    model.newCodebook()
                } label: {
                    Label("New Codebook", systemImage: "plus")
                }
            }
        }
    }

    func sheetSummary(_ cb: Codebook) -> String {
        let sheets = model.project.responses.values.filter { $0.id.codebook == cb.key }
        guard !sheets.isEmpty else { return "None yet" }
        let complete = sheets.filter { SheetCompleteness.of($0.answers, against: cb).isComplete }.count
        return "\(sheets.count) (\(complete) complete)"
    }
}

// MARK: - People

/// A person's real name for a table cell: shown, hidden, or not mapped.
/// (Table cells take the model directly rather than from the environment.)
struct RealNameCell: View {
    let model: AppModel
    var key: String

    var body: some View {
        if let real = model.realNames[key] {
            if model.showRealNames {
                Text(real)
            } else {
                Text("Hidden").foregroundStyle(.tertiary).help("View › Show Real Names")
            }
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }
}

struct ResearchersTable: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var columns: [DataColumn<Researcher>] {
        let model = self.model
        var c: [DataColumn<Researcher>] = []
        c.append(DataColumn<Researcher>("First Name", minWidth: 110, order: DataColumn<Researcher>.text { $0.firstName }) { (r: Researcher) in
            Text(r.firstName)
        })
        c.append(DataColumn<Researcher>("Last Name", minWidth: 110, order: DataColumn<Researcher>.text { $0.lastName }) { (r: Researcher) in
            Text(r.lastName)
        })
        c.append(DataColumn<Researcher>("Real Name", minWidth: 120) { (r: Researcher) in
            RealNameCell(model: model, key: r.key)
        })
        c.append(DataColumn<Researcher>("This Mac", width: 74, alignment: .center) { (r: Researcher) in
            Image(systemName: "checkmark").opacity(r.key == model.currentResearcher ? 1 : 0)
        })
        c.append(DataColumn<Researcher>("Layers", minWidth: 100) { (r: Researcher) in
            Text(model.project.layers.filter { $0.researcher == r.key }.map(\.name).joined(separator: ", "))
                .foregroundStyle(.secondary)
        })
        return c
    }

    var body: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all = model.project.researchers
        let shown: [Researcher] = q.isEmpty ? all : all.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
        VStack(spacing: 0) {
            PageHeader(title: "Researchers",
                       subtitle: "The people doing the analysis, by pseudonym. Real names can come from a mapping file in the full-texts folder (Project Settings).")
            HStack {
                Text("This Mac's researcher:")
                Picker("This Mac's researcher", selection: Binding(
                    get: { model.currentResearcher ?? "" },
                    set: { model.setCurrentResearcher($0.isEmpty ? nil : $0) }
                )) {
                    Text("Not chosen").tag("")
                    ForEach(model.project.researchers) { r in Text(model.personName(r.key) ?? "").tag(r.key) }
                }
                .labelsHidden()
                .fixedSize()
                Text("Your selections and codebook answers are filed under this name.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            Divider()
            DataTable(rows: shown, columns: columns, selection: $model.tableSelection, defaultSort: 1,
                      emptyText: "No researchers yet.",
                      onOpen: { key in model.show(.researcher(key)) }) { (r: Researcher) in
                Button("Open") { model.show(.researcher(r.key)) }
                Button("Add to Working Area") { model.addToWorkingArea(.researcher(r.key)) }
                    .disabled(model.workingArea.contains(.researcher(r.key)))
                Button("This Is Me on This Mac") { model.setCurrentResearcher(r.key) }
                Divider()
                Button("Delete Researcher") { model.perform("Delete Researcher") { p in p.deleteResearcher(r.key) } }
            }
            TableFooter(count: "\(all.count) researcher\(all.count == 1 ? "" : "s")", filter: $filter) {
                Button {
                    model.newPerson(.researchers)
                } label: {
                    Label("New Researcher", systemImage: "plus")
                }
            }
        }
    }
}

struct IntervieweesTable: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var columns: [DataColumn<Interviewee>] {
        let model = self.model
        var c: [DataColumn<Interviewee>] = []
        c.append(DataColumn<Interviewee>("First Name", minWidth: 110, order: DataColumn<Interviewee>.text { $0.firstName }) { (i: Interviewee) in
            Text(i.firstName)
        })
        c.append(DataColumn<Interviewee>("Last Name", minWidth: 110, order: DataColumn<Interviewee>.text { $0.lastName }) { (i: Interviewee) in
            Text(i.lastName)
        })
        c.append(DataColumn<Interviewee>("Real Name", minWidth: 120) { (i: Interviewee) in
            RealNameCell(model: model, key: i.key)
        })
        c.append(DataColumn<Interviewee>("Consent Form", width: 120) { (i: Interviewee) in
            ConsentStatus(model: model, interviewee: i)
        })
        c.append(DataColumn<Interviewee>("Transcripts", width: 90, alignment: .trailing,
                            order: DataColumn<Interviewee>.number { model.transcripts(of: $0.key).count }) { (i: Interviewee) in
            Text("\(model.transcripts(of: i.key).count)").monospacedDigit()
        })
        return c
    }

    var body: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all = model.project.interviewees
        let shown: [Interviewee] = q.isEmpty ? all : all.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
        VStack(spacing: 0) {
            PageHeader(title: "Interviewees",
                       subtitle: "Participants, by pseudonym. Real names can come from a mapping file in the full-texts folder (Project Settings); consent forms stay there too.")
            Divider()
            DataTable(rows: shown, columns: columns, selection: $model.tableSelection, defaultSort: 1,
                      emptyText: "No interviewees yet.",
                      onOpen: { key in model.show(.interviewee(key)) }) { (i: Interviewee) in
                Button("Open") { model.show(.interviewee(i.key)) }
                Button("Add to Working Area") { model.addToWorkingArea(.interviewee(i.key)) }
                    .disabled(model.workingArea.contains(.interviewee(i.key)))
                Button("Choose Consent Form…") { model.chooseConsentForm(for: i.key) }
                Divider()
                Button("Delete Interviewee") { model.perform("Delete Interviewee") { p in p.deleteInterviewee(i.key) } }
            }
            TableFooter(count: "\(all.count) interviewee\(all.count == 1 ? "" : "s")", filter: $filter) {
                Button {
                    model.newPerson(.interviewees)
                } label: {
                    Label("New Interviewee", systemImage: "plus")
                }
            }
        }
    }
}

struct ConsentStatus: View {
    let model: AppModel
    var interviewee: Interviewee

    var body: some View {
        if interviewee.consentForm.isEmpty {
            Text("None").foregroundStyle(.tertiary)
        } else if model.fullTexts?.exists(interviewee.consentForm) == true {
            Label("On file", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
        } else {
            Label("Missing", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
        }
    }
}

extension AppModel {
    /// Files where an interviewee (or researcher) is an assigned speaker.
    func transcripts(of person: String) -> [EmpiricalFile] {
        project.speakerMaps.values
            .filter { m in m.assignments.contains { $0.person == person } }
            .compactMap { project.files[$0.fileKey] }
            .sorted { $0.sortID.localizedStandardCompare($1.sortID) == .orderedAscending }
    }

    func newPerson(_ kind: PeopleKind) {
        var made = ""
        perform(kind == .researchers ? "New Researcher" : "New Interviewee") { p in
            if kind == .researchers {
                made = p.newKey(Keys.researcher)
                p.researchers.append(Researcher(key: made, firstName: "New", lastName: "Researcher"))
            } else {
                made = p.newKey(Keys.interviewee)
                p.interviewees.append(Interviewee(key: made, firstName: "New", lastName: "Interviewee"))
            }
        }
        tableSelection = made
    }

    func newCodebook() {
        let key = project.newKey(Keys.codebook)
        perform("New Codebook") { p in
            p.codebooks[key] = Codebook(key: key, title: "New Codebook", appliesTo: [.files])
        }
        show(.codebook(key))
    }

    func deleteCodebook(_ key: String) {
        guard let cb = project.codebooks[key] else { return }
        let sheets = project.responses.keys.filter { $0.codebook == key }.count
        let alert = NSAlert()
        alert.messageText = "Delete the codebook “\(cb.title)”?"
        alert.informativeText = sheets == 0
            ? "It is removed from every file and code it is associated with."
            : "Its \(sheets) response sheet\(sheets == 1 ? "" : "s") are deleted too. You can undo this while the project is open."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform("Delete Codebook") { p in p.deleteCodebook(key) }
    }
}

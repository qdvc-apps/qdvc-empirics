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
            Text(subtitle).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Empirical files

struct FilesTable: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\EmpiricalFile.sortID)]

    var body: some View {
        @Bindable var model = model
        let rows: [EmpiricalFile] = model.visibleFiles.sorted(using: sortOrder)
        let coded = model.project.files.values.filter { $0.status == .coded }.count
        VStack(spacing: 0) {
            PageHeader(title: "Empirical Files",
                       subtitle: "Transcripts, notes and articles in the full-texts folder. Double-click one to code it.")
            Divider()
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("Status", value: \EmpiricalFile.statusOrder) { (f: EmpiricalFile) in
                    Label(f.status.label, systemImage: f.status.symbol)
                        .foregroundStyle(f.status.tint)
                }
                .width(min: 90, ideal: 110, max: 130)
                TableColumn("ID", value: \EmpiricalFile.customID) { (f: EmpiricalFile) in
                    Text(f.customID).font(.body.monospaced())
                }
                .width(min: 60, ideal: 120, max: 200)
                TableColumn("Title", value: \EmpiricalFile.displayTitle)
                TableColumn("Date", value: \EmpiricalFile.date)
                    .width(min: 70, ideal: 90, max: 120)
                TableColumn("Kind", value: \EmpiricalFile.kindLabel)
                    .width(min: 60, ideal: 80, max: 110)
                TableColumn("Selections") { (f: EmpiricalFile) in
                    Text("\(model.index.selectionCount[f.key] ?? 0)").monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 90)
                TableColumn("Location", value: \EmpiricalFile.path) { (f: EmpiricalFile) in
                    Text(f.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
            }
            .contextMenu(forSelectionType: String.self) { keys in
                if let key = keys.first, let f = model.project.files[key] {
                    Button("Open") { model.show(.file(key)) }
                    Button("Add to Working Area") { model.addToWorkingArea(.file(key)) }
                        .disabled(model.workingArea.contains(.file(key)))
                    Divider()
                    ForEach(CodingStatus.allCases, id: \.self) { s in
                        Button("Mark as \(s.label)") { model.setStatus(s, file: key) }
                            .disabled(f.status == s)
                    }
                    Divider()
                    Button("Remove from Project…") { model.removeFile(key) }
                }
            } primaryAction: { keys in
                if let key = keys.first { model.show(.file(key)) }
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
    @State private var sortOrder = [KeyPathComparator(\QDACode.name)]
    @State private var filter = ""

    var body: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all: [QDACode] = (model.activeLayer.map { Array($0.codes.values) } ?? []).filter { $0.kind == kind }
        let shown: [QDACode] = q.isEmpty ? all : all.filter { c in
            c.name.localizedCaseInsensitiveContains(q) || c.description.localizedCaseInsensitiveContains(q)
        }
        let rows: [QDACode] = shown.sorted(using: sortOrder)
        VStack(spacing: 0) {
            PageHeader(title: kind == .open ? "Open Codes" : "Axial Codes",
                       subtitle: (kind == .open
                                  ? "Codes evidenced directly by selections"
                                  : "Codes built from open codes and other axial codes")
                           + " in the layer “\(model.activeLayer?.name ?? "")”. Double-click one to open its evidence.")
            Divider()
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("Name", value: \QDACode.name) { (c: QDACode) in
                    HStack(spacing: 6) {
                        CodeDot(color: c.color)
                        Text(c.name)
                    }
                }
                TableColumn("Evidence", value: \QDACode.evidenceCount) { (c: QDACode) in
                    Text("\(c.evidence.count)").monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 90)
                TableColumn("Files") { (c: QDACode) in
                    Text("\(model.index.filesForCode[c.key]?.count ?? 0)").monospacedDigit()
                }
                .width(min: 40, ideal: 50, max: 70)
                TableColumn("Evidence For") { (c: QDACode) in
                    Text(parentNames(c)).foregroundStyle(.secondary).lineLimit(1)
                }
                TableColumn("Questions", value: \QDACode.questionCount) { (c: QDACode) in
                    Text(c.questions.isEmpty ? "" : "\(c.questions.count)").monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 90)
                TableColumn("Quick") { (c: QDACode) in
                    Text(model.quickSlot(of: c.key).map { "\($0)" } ?? "").monospacedDigit()
                }
                .width(min: 40, ideal: 44, max: 60)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                if let key = keys.first, let code = model.project.code(key) {
                    Button("Open") { model.show(.code(key)) }
                    Button("Add to Working Area") { model.addToWorkingArea(.code(key)) }
                        .disabled(model.workingArea.contains(.code(key)))
                    if code.kind == .open {
                        Menu("Quick Code") {
                            ForEach(1...9, id: \.self) { n in
                                Button("\(n)") { model.assignQuickCode(key, slot: n) }
                            }
                            Divider()
                            Button("None") {
                                if let s = model.quickSlot(of: key) { model.assignQuickCode(nil, slot: s) }
                            }
                        }
                    }
                    if model.project.layers.count > 1 {
                        Button("Move to Layer…") { model.sheet = .moveToLayer(key) }
                    }
                    Divider()
                    Button("Delete Code…") { model.deleteCode(key) }
                }
            } primaryAction: { keys in
                if let key = keys.first { model.show(.code(key)) }
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
    @State private var sortOrder = [KeyPathComparator(\Codebook.title)]
    @State private var filter = ""

    var body: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all: [Codebook] = Array(model.project.codebooks.values)
        let shown: [Codebook] = q.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(q) }
        let rows: [Codebook] = shown.sorted(using: sortOrder)
        VStack(spacing: 0) {
            PageHeader(title: "Codebooks",
                       subtitle: "Sets of questions answered about each empirical file, open code or axial code they are associated with. Double-click one to edit its questions.")
            Divider()
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("Title", value: \Codebook.title) { (cb: Codebook) in
                    Label(cb.title, systemImage: "text.book.closed")
                }
                TableColumn("Questions", value: \Codebook.questionCount) { (cb: Codebook) in
                    Text("\(cb.questions.count)").monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 90)
                TableColumn("Applies To", value: \Codebook.appliesToLabel)
                TableColumn("Response Sheets") { (cb: Codebook) in
                    Text(sheetSummary(cb)).foregroundStyle(.secondary)
                }
            }
            .contextMenu(forSelectionType: String.self) { keys in
                if let key = keys.first {
                    Button("Open") { model.show(.codebook(key)) }
                    Button("Add to Working Area") { model.addToWorkingArea(.codebook(key)) }
                        .disabled(model.workingArea.contains(.codebook(key)))
                    Divider()
                    Button("Delete Codebook…") { model.deleteCodebook(key) }
                }
            } primaryAction: { keys in
                if let key = keys.first { model.show(.codebook(key)) }
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
    @State private var sortOrder = [KeyPathComparator(\Researcher.lastName)]
    @State private var filter = ""

    var body: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all = model.project.researchers
        let shown: [Researcher] = q.isEmpty ? all : all.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
        let rows: [Researcher] = shown.sorted(using: sortOrder)
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
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            Divider()
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("First Name", value: \Researcher.firstName)
                TableColumn("Last Name", value: \Researcher.lastName)
                TableColumn("Real Name") { (r: Researcher) in RealNameCell(model: model, key: r.key) }
                TableColumn("This Mac") { (r: Researcher) in
                    if r.key == model.currentResearcher { Image(systemName: "checkmark") }
                }
                .width(min: 60, ideal: 70, max: 80)
                TableColumn("Layers") { (r: Researcher) in
                    Text(model.project.layers.filter { $0.researcher == r.key }.map(\.name).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
            .contextMenu(forSelectionType: String.self) { keys in
                if let key = keys.first {
                    Button("Open") { model.show(.researcher(key)) }
                    Button("Add to Working Area") { model.addToWorkingArea(.researcher(key)) }
                        .disabled(model.workingArea.contains(.researcher(key)))
                    Button("This Is Me on This Mac") { model.setCurrentResearcher(key) }
                    Divider()
                    Button("Delete Researcher") { model.perform("Delete Researcher") { p in p.deleteResearcher(key) } }
                }
            } primaryAction: { keys in
                if let key = keys.first { model.show(.researcher(key)) }
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
    @State private var sortOrder = [KeyPathComparator(\Interviewee.lastName)]
    @State private var filter = ""

    var body: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all = model.project.interviewees
        let shown: [Interviewee] = q.isEmpty ? all : all.filter { $0.fullName.localizedCaseInsensitiveContains(q) }
        let rows: [Interviewee] = shown.sorted(using: sortOrder)
        VStack(spacing: 0) {
            PageHeader(title: "Interviewees",
                       subtitle: "Participants, by pseudonym. Real names can come from a mapping file in the full-texts folder (Project Settings); consent forms stay there too.")
            Divider()
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("First Name", value: \Interviewee.firstName)
                TableColumn("Last Name", value: \Interviewee.lastName)
                TableColumn("Real Name") { (i: Interviewee) in RealNameCell(model: model, key: i.key) }
                TableColumn("Consent Form") { (i: Interviewee) in
                    ConsentStatus(model: model, interviewee: i)
                }
                .width(min: 90, ideal: 110, max: 140)
                TableColumn("Transcripts") { (i: Interviewee) in
                    Text("\(model.transcripts(of: i.key).count)").monospacedDigit()
                }
                .width(min: 70, ideal: 80, max: 100)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                if let key = keys.first {
                    Button("Open") { model.show(.interviewee(key)) }
                    Button("Add to Working Area") { model.addToWorkingArea(.interviewee(key)) }
                        .disabled(model.workingArea.contains(.interviewee(key)))
                    Button("Choose Consent Form…") { model.chooseConsentForm(for: key) }
                    Divider()
                    Button("Delete Interviewee") { model.perform("Delete Interviewee") { p in p.deleteInterviewee(key) } }
                }
            } primaryAction: { keys in
                if let key = keys.first { model.show(.interviewee(key)) }
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

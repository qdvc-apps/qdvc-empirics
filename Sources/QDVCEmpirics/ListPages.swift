import AppKit
import EmpiricsCore
import SwiftUI

// The list pages of the sidebar: SwiftUI Tables, used as in QDVC Response
// Letter (the table at the top of the page, a bar below it). Selecting a row
// shows it in the inspector; double-clicking opens its page and puts it in
// the Working Area.

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

/// The bar under a table: add buttons, a filter, a count. (As in QDVC
/// Response Letter's Variables page: below the table, in a VStack; nothing
/// fixed above the table, which starts at the top of the page.)
struct TableFooter<Leading: View>: View {
    var count: String
    @Binding var filter: String
    @ViewBuilder var leading: () -> Leading

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                leading()
                Spacer()
                Text(count).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                TextField("Filter", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
            }
            .controlSize(.small)
            .padding(8)
        }
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
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                // Working identifiers follow alphabetical order of the
                // titles, so sorting by title sorts by number.
                TableColumn("No.", value: \EmpiricalFile.displayTitle) { (f: EmpiricalFile) in
                    WorkingIDCell(model: model, key: f.key)
                }
                .width(min: 50, ideal: 62, max: 80)
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
                    .width(min: 120, ideal: 240)
                TableColumn("Date", value: \EmpiricalFile.date)
                    .width(min: 70, ideal: 90, max: 120)
                TableColumn("Kind", value: \EmpiricalFile.kindLabel)
                    .width(min: 60, ideal: 80, max: 110)
                TableColumn("Selections") { (f: EmpiricalFile) in
                    Text("\(model.index.selectionCount[f.key] ?? 0)").monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 90)
                TableColumn("Codebooks") { (f: EmpiricalFile) in
                    Text(model.codebookTitles(f.key)).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 80, ideal: 160)
                TableColumn("Location", value: \EmpiricalFile.path) { (f: EmpiricalFile) in
                    Text(f.path).font(.caption.monospaced()).foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 200)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                FileTableMenu(model: model, keys: keys)
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
                Text("Double-click a file to code it.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// (Menus take the model directly: they are built apart from the table.)
struct FileTableMenu: View {
    let model: AppModel
    let keys: Set<String>

    var body: some View {
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
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("No.", value: \QDACode.name) { (c: QDACode) in
                    WorkingIDCell(model: model, key: c.key)
                }
                .width(min: 50, ideal: 62, max: 80)
                TableColumn("Name", value: \QDACode.name) { (c: QDACode) in
                    HStack(spacing: 6) {
                        CodeDot(color: c.color)
                        Text(c.name)
                    }
                }
                .width(min: 140, ideal: 240)
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
                .width(min: 100, ideal: 200)
                TableColumn("Questions", value: \QDACode.questionCount) { (c: QDACode) in
                    Text(c.questions.isEmpty ? "" : "\(c.questions.count)").monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 90)
                TableColumn("Codebooks") { (c: QDACode) in
                    Text(model.codebookTitles(c.key)).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 80, ideal: 160)
                TableColumn("Quick") { (c: QDACode) in
                    Text(model.quickSlot(of: c.key).map { "\($0)" } ?? "").monospacedDigit()
                }
                .width(min: 40, ideal: 44, max: 60)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                CodeTableMenu(model: model, keys: keys)
            } primaryAction: { keys in
                if let key = keys.first { model.show(.code(key)) }
            }
            TableFooter(count: "\(all.count) \(kind == .open ? "open" : "axial") code\(all.count == 1 ? "" : "s")", filter: $filter) {
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
        (model.index.parents[c.key] ?? []).filter { model.project.code($0) != nil }
            .sorted { model.itemTitle($0).localizedStandardCompare(model.itemTitle($1)) == .orderedAscending }
            .map { model.itemLabel($0) }
            .joined(separator: ", ")
    }
}

struct CodeTableMenu: View {
    let model: AppModel
    let keys: Set<String>

    var body: some View {
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
            Button(code.kind == .open ? "Delete Open Code…" : "Delete Axial Code…") { model.deleteCode(key) }
        }
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
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("No.", value: \Codebook.title) { (cb: Codebook) in
                    WorkingIDCell(model: model, key: cb.key)
                }
                .width(min: 50, ideal: 62, max: 80)
                TableColumn("Title", value: \Codebook.title) { (cb: Codebook) in
                    Label(cb.title, systemImage: "text.book.closed")
                }
                .width(min: 160, ideal: 260)
                TableColumn("Questions", value: \Codebook.questionCount) { (cb: Codebook) in
                    Text("\(cb.questions.count)").monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 90)
                TableColumn("Applies To", value: \Codebook.appliesToLabel)
                    .width(min: 120, ideal: 220)
                TableColumn("Response Sheets") { (cb: Codebook) in
                    Text(sheetSummary(cb)).foregroundStyle(.secondary)
                }
                .width(min: 100, ideal: 150)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                CodebookTableMenu(model: model, keys: keys)
            } primaryAction: { keys in
                if let key = keys.first { model.show(.codebook(key)) }
            }
            TableFooter(count: "\(all.count) codebook\(all.count == 1 ? "" : "s")", filter: $filter) {
                Button {
                    model.newCodebook()
                } label: {
                    Label("New Codebook", systemImage: "plus")
                }
                Text("Double-click a codebook to edit its questions.").font(.caption).foregroundStyle(.secondary)
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

struct CodebookTableMenu: View {
    let model: AppModel
    let keys: Set<String>

    var body: some View {
        if let key = keys.first {
            Button("Open") { model.show(.codebook(key)) }
            Button("Add to Working Area") { model.addToWorkingArea(.codebook(key)) }
                .disabled(model.workingArea.contains(.codebook(key)))
            Divider()
            Button("Show Report") {
                model.reportCodebook = key
                model.sidebar = .codebookReport
            }
            Divider()
            Button("Delete Codebook…") { model.deleteCodebook(key) }
        }
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
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("No.", value: \Researcher.fullName) { (r: Researcher) in
                    WorkingIDCell(model: model, key: r.key)
                }
                .width(min: 44, ideal: 56, max: 70)
                TableColumn("First Name", value: \Researcher.firstName)
                    .width(min: 90, ideal: 140)
                TableColumn("Last Name", value: \Researcher.lastName)
                    .width(min: 90, ideal: 140)
                TableColumn("Real Name") { (r: Researcher) in RealNameCell(model: model, key: r.key) }
                    .width(min: 90, ideal: 160)
                TableColumn("This Mac") { (r: Researcher) in
                    Image(systemName: "checkmark").opacity(r.key == model.currentResearcher ? 1 : 0)
                }
                .width(min: 60, ideal: 70, max: 80)
                TableColumn("Layers") { (r: Researcher) in
                    Text(model.project.layers.filter { $0.researcher == r.key }.map(\.name).joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
                .width(min: 80, ideal: 160)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                PersonTableMenu(model: model, keys: keys, researchers: true)
            } primaryAction: { keys in
                if let key = keys.first { model.show(.researcher(key)) }
            }
            TableFooter(count: "\(all.count) researcher\(all.count == 1 ? "" : "s")", filter: $filter) {
                Button {
                    model.newPerson(.researchers)
                } label: {
                    Label("New Researcher", systemImage: "plus")
                }
                Text("This Mac:").font(.caption).foregroundStyle(.secondary)
                Picker("This Mac's researcher", selection: Binding(
                    get: { model.currentResearcher ?? "" },
                    set: { model.setCurrentResearcher($0.isEmpty ? nil : $0) }
                )) {
                    Text("Not chosen").tag("")
                    ForEach(model.project.researchers) { r in Text(model.personName(r.key) ?? "").tag(r.key) }
                }
                .labelsHidden()
                .fixedSize()
                .help("Who you are on this Mac: your selections and codebook answers are filed under this name")
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
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("No.", value: \Interviewee.fullName) { (i: Interviewee) in
                    WorkingIDCell(model: model, key: i.key)
                }
                .width(min: 44, ideal: 56, max: 70)
                TableColumn("First Name", value: \Interviewee.firstName)
                    .width(min: 90, ideal: 140)
                TableColumn("Last Name", value: \Interviewee.lastName)
                    .width(min: 90, ideal: 140)
                TableColumn("Real Name") { (i: Interviewee) in RealNameCell(model: model, key: i.key) }
                    .width(min: 90, ideal: 160)
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
                PersonTableMenu(model: model, keys: keys, researchers: false)
            } primaryAction: { keys in
                if let key = keys.first { model.show(.interviewee(key)) }
            }
            TableFooter(count: "\(all.count) interviewee\(all.count == 1 ? "" : "s")", filter: $filter) {
                Button {
                    model.newPerson(.interviewees)
                } label: {
                    Label("New Interviewee", systemImage: "plus")
                }
                Text("Names are pseudonyms.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

struct PersonTableMenu: View {
    let model: AppModel
    let keys: Set<String>
    let researchers: Bool

    var body: some View {
        if let key = keys.first {
            let item: SidebarItem = researchers ? .researcher(key) : .interviewee(key)
            Button("Open") { model.show(item) }
            Button("Add to Working Area") { model.addToWorkingArea(item) }
                .disabled(model.workingArea.contains(item))
            if researchers {
                Button("This Is Me on This Mac") { model.setCurrentResearcher(key) }
                Divider()
                Button("Delete Researcher") { model.perform("Delete Researcher") { p in p.deleteResearcher(key) } }
            } else {
                Button("Choose Consent Form…") { model.chooseConsentForm(for: key) }
                Divider()
                Button("Delete Interviewee") { model.perform("Delete Interviewee") { p in p.deleteInterviewee(key) } }
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

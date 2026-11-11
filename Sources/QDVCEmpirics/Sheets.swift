import AppKit
import EmpiricsCore
import PDFKit
import SwiftUI

/// Shows the sheet for a `SheetKind`.
struct SheetHost: View {
    let kind: SheetKind

    var body: some View {
        Group {
            switch kind {
            case .newProject(let url): NewProjectSheet(folder: url)
            case .addFiles(let paths): AddFilesSheet(paths: paths)
            case .speakers(let file): SpeakersSheet(fileKey: file)
            case .response(let id): ResponseSheetView(id: id)
            case .interrelation(let code, let key): InterrelationSheet(codeKey: code, key: key)
            case .consent(let interviewee): ConsentViewer(interviewee: interviewee)
            case .moveToLayer(let item): MoveToLayerSheet(item: item)
            case .newCode(let kind, let parent, let child): NewCodeSheet(kind: kind, parent: parent, child: child)
            }
        }
        .modifier(NoWritingTools())
    }
}

// MARK: - New project

struct NewProjectSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var folder: URL?
    @State private var fullTexts: URL?
    @State private var title = ""
    @State private var firstName = ""
    @State private var lastName = ""

    init(folder: URL?) {
        _folder = State(initialValue: folder)
    }

    var problem: String? {
        guard let folder, let fullTexts else { return nil }
        if Workspace.isWorkspace(folder) { return "That folder already holds a project; open it instead." }
        if !Workspace.isEmptyFolder(folder) { return "The workspace folder must be empty." }
        return AppModel.nestingProblem(workspace: folder, fullTexts: fullTexts)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New Project").font(.title2.weight(.semibold))
            Text("A project keeps its analysis in a **workspace** folder of YAML files, meant for Git. The interview transcripts, documents and consent forms stay in a separate **full-texts** folder that QDVC Empirics only ever reads, and that never goes into the workspace.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Form {
                TextField("Title", text: $title, prompt: Text("e.g. Remote work interviews"))
                LabeledContent("Workspace") {
                    folderButton(folder, placeholder: "Choose an empty folder…") { folder = chooseFolder(create: true, message: "Choose an empty folder for the project's workspace (it will be tracked in Git).") }
                }
                LabeledContent("Full-texts") {
                    folderButton(fullTexts, placeholder: "Choose the full-texts folder…") { fullTexts = chooseFolder(create: false, message: "Choose the folder that holds the full-texts (transcripts, PDFs) and consent forms. It is only ever read.") }
                }
                Section("You (optional)") {
                    TextField("First name", text: $firstName)
                    TextField("Last name", text: $lastName)
                }
            }
            .formStyle(.grouped)
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create Project") {
                    guard let folder, let fullTexts else { return }
                    dismiss()
                    model.createProject(at: folder, title: title, fullTexts: fullTexts, firstName: firstName, lastName: lastName)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(folder == nil || fullTexts == nil || problem != nil)
            }
        }
        .padding(22)
        .frame(width: 580)
    }

    func folderButton(_ url: URL?, placeholder: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "folder")
                Text(url.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? placeholder)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    func chooseFolder(create: Bool, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = create
        panel.allowsMultipleSelection = false
        panel.message = message
        panel.prompt = "Choose"
        return panel.runModal() == .OK ? panel.url : nil
    }
}

// MARK: - Add files

struct AddFilesSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let paths: [String]
    @State private var chosen: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Files from the Full-Texts Folder").font(.title3.weight(.semibold))
            Text("\(paths.count) supported file\(paths.count == 1 ? " isn't" : "s aren't") in the project yet. Consent forms are left out.")
                .foregroundStyle(.secondary)
            List {
                ForEach(paths, id: \.self) { path in
                    Toggle(isOn: Binding(get: { chosen.contains(path) }, set: { on in
                        if on { chosen.insert(path) } else { chosen.remove(path) }
                    })) {
                        HStack {
                            Image(systemName: (FileKind.forPath(path) ?? .text).symbol).foregroundStyle(.secondary)
                            Text(path).lineLimit(1).truncationMode(.middle)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(minHeight: 240)
            HStack {
                Button("Select All") { chosen = Set(paths) }
                Button("Select None") { chosen = [] }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add \(chosen.count) File\(chosen.count == 1 ? "" : "s")") {
                    let list = paths.filter { chosen.contains($0) }
                    dismiss()
                    model.addFiles(list)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 460)
        .onAppear { chosen = Set(paths) }
    }
}

// MARK: - Speakers (Interlocutor layer)

/// Maps the speaker labels found in a transcript to researchers and
/// interviewees, or marks them as not speakers.
struct SpeakersSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let fileKey: String
    @State private var map = SpeakerMap(fileKey: "")
    @State private var extraLabel = ""

    static let notSpeaker = "—not a speaker—"
    static let unassigned = ""

    var body: some View {
        let candidates = model.speakerCandidates(fileKey)
        let labels = labelsToShow(candidates)
        VStack(alignment: .leading, spacing: 12) {
            Text("Speakers").font(.title3.weight(.semibold))
            Text(model.project.files[fileKey]?.displayTitle ?? "").foregroundStyle(.secondary)
            Text("Header lines that look like speaker names were found in this transcript. Choose who each one is. Labels compare without regard to capitals, colons or spacing, so “ALICE BOB:” and “Alice Bob” are the same speaker.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.project.researchers.isEmpty && model.project.interviewees.isEmpty {
                Label("Add researchers and interviewees first (sidebar › Researchers, Interviewees).", systemImage: "person.badge.plus")
                    .foregroundStyle(.orange)
            }
            List {
                ForEach(labels, id: \.self) { label in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(label).fontWeight(.medium)
                            if let c = candidates.first(where: { $0.speaker == TurnDetector.normalise(label) }) {
                                Text("\(c.count) header\(c.count == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Picker(label, selection: binding(for: label)) {
                            Text("Unassigned").tag(Self.unassigned)
                            if !model.project.researchers.isEmpty {
                                Section("Researchers") {
                                    ForEach(model.project.researchers) { r in Text(model.personName(r.key) ?? "").tag(r.key) }
                                }
                            }
                            if !model.project.interviewees.isEmpty {
                                Section("Interviewees") {
                                    ForEach(model.project.interviewees) { i in Text(model.personName(i.key) ?? "").tag(i.key) }
                                }
                            }
                            Divider()
                            Text("Not a speaker").tag(Self.notSpeaker)
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                }
            }
            .frame(minHeight: 220)
            HStack {
                TextField("Another speaker label, exactly as in the header lines", text: $extraLabel)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addExtra)
                Button("Add", action: addExtra)
                    .disabled(extraLabel.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .controlSize(.small)
            HStack {
                Button("Suggest from Names") { suggest(labels) }
                    .help("Match labels to researchers' and interviewees' names")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let m = map
                    model.perform("Assign Speakers") { p in
                        if m.isEmpty { p.speakerMaps[fileKey] = nil } else { p.speakerMaps[fileKey] = m }
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 560, height: 560)
        .onAppear {
            map = model.project.speakerMaps[fileKey] ?? SpeakerMap(fileKey: fileKey)
            if map.assignments.isEmpty { suggest(labelsToShow(candidates)) }
        }
    }

    func labelsToShow(_ candidates: [SpeakerCandidate]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for l in candidates.map(\.label) + map.assignments.map(\.label) + map.ignored {
            if seen.insert(TurnDetector.normalise(l)).inserted { result.append(l) }
        }
        return result
    }

    func binding(for label: String) -> Binding<String> {
        let n = TurnDetector.normalise(label)
        return Binding(
            get: {
                if map.ignored.contains(where: { TurnDetector.normalise($0) == n }) { return Self.notSpeaker }
                return map.assignments.first { TurnDetector.normalise($0.label) == n }?.person ?? Self.unassigned
            },
            set: { v in
                map.assignments.removeAll { TurnDetector.normalise($0.label) == n }
                map.ignored.removeAll { TurnDetector.normalise($0) == n }
                if v == Self.notSpeaker {
                    map.ignored.append(n)
                } else if !v.isEmpty {
                    map.assignments.append(SpeakerAssignment(label: label, person: v))
                }
            }
        )
    }

    func suggest(_ labels: [String]) {
        for label in labels where map.person(for: label) == nil {
            let n = TurnDetector.normalise(label)
            guard !map.ignored.contains(where: { TurnDetector.normalise($0) == n }) else { continue }
            if let p = TurnDetector.suggest(label, researchers: model.project.researchers, interviewees: model.project.interviewees) {
                map.assignments.append(SpeakerAssignment(label: label, person: p))
            }
        }
    }

    func addExtra() {
        let label = extraLabel.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: ":"))
        guard !label.isEmpty else { return }
        if map.person(for: label) == nil {
            map.assignments.append(SpeakerAssignment(label: label,
                                                     person: TurnDetector.suggest(label, researchers: model.project.researchers,
                                                                                  interviewees: model.project.interviewees) ?? ""))
            map.assignments.removeAll { $0.person.isEmpty && TurnDetector.normalise($0.label) != TurnDetector.normalise(label) }
        }
        extraLabel = ""
    }
}

// MARK: - Interrelations

struct InterrelationSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let codeKey: String
    let key: String?
    @State private var type = ""
    @State private var members: [String] = []
    @State private var description = ""
    @State private var newType = ""

    var body: some View {
        let code = model.project.code(codeKey)
        VStack(alignment: .leading, spacing: 12) {
            Text(key == nil ? "New Interrelation" : "Interrelation").font(.title3.weight(.semibold))
            if let code {
                Text("Between pieces of evidence for “\(code.name)”").foregroundStyle(.secondary)
                Picker("Type", selection: $type) {
                    ForEach(model.project.settings.interrelationTypes, id: \.self) { Text($0).tag($0) }
                    if !type.isEmpty && !model.project.settings.interrelationTypes.contains(type) {
                        Text(type).tag(type)
                    }
                }
                .fixedSize()
                HStack {
                    TextField("New type", text: $newType)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 200)
                    Button("Add Type") {
                        let t = newType.trimmingCharacters(in: .whitespaces)
                        guard !t.isEmpty else { return }
                        if !model.project.settings.interrelationTypes.contains(t) {
                            model.perform("Add Interrelation Type") { p in p.settings.interrelationTypes.append(t) }
                        }
                        type = t
                        newType = ""
                    }
                    .disabled(newType.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .controlSize(.small)
                Text("Items (choose two or more)").font(.caption).foregroundStyle(.secondary)
                List {
                    ForEach(code.evidence, id: \.target) { e in
                        Toggle(isOn: Binding(get: { members.contains(e.target) }, set: { on in
                            if on { members.append(e.target) } else { members.removeAll { $0 == e.target } }
                        })) {
                            Text(model.evidenceLabel(e.target)).lineLimit(3)
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .frame(minHeight: 200)
                TextField("How do they relate?", text: $description, axis: .vertical)
                    .lineLimit(3...10)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                if let key {
                    Button("Delete", role: .destructive) {
                        model.perform("Delete Interrelation") { p in
                            guard var c = p.code(codeKey) else { return }
                            c.interrelations.removeAll { $0.key == key }
                            p.updateCode(c)
                        }
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    let t = type, m = members, d = description
                    model.perform(key == nil ? "New Interrelation" : "Edit Interrelation") { p in
                        if let key {
                            guard var c = p.code(codeKey), let i = c.interrelations.firstIndex(where: { $0.key == key }) else { return }
                            c.interrelations[i].type = t
                            c.interrelations[i].members = m
                            c.interrelations[i].description = d
                            p.updateCode(c)
                        } else {
                            p.addInterrelation(code: codeKey, type: t, members: m, description: d)
                        }
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(members.count < 2 || type.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 560, height: 580)
        .onAppear {
            if let key, let x = model.project.code(codeKey)?.interrelations.first(where: { $0.key == key }) {
                type = x.type
                members = x.members
                description = x.description
            } else {
                type = model.project.settings.interrelationTypes.first ?? ""
            }
        }
    }
}

// MARK: - Move to layer

struct MoveToLayerSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: String
    @State private var target = ""

    var body: some View {
        let component = model.project.component(of: item)
        let from = model.index.layerOf[item]
        let others = model.project.layers.filter { $0.key != from }
        VStack(alignment: .leading, spacing: 14) {
            Text("Move to Another Layer").font(.title3.weight(.semibold))
            Text("Selections, open codes and axial codes exist in one layer only, so everything linked to this item moves with it: \(component.selections.count) selection\(component.selections.count == 1 ? "" : "s"), \(model.codeCounts(Array(component.codes))).")
                .fixedSize(horizontal: false, vertical: true)
            if !component.codes.isEmpty {
                let names = component.codes.filter { model.project.code($0) != nil }.map { model.itemLabel($0) }.sorted()
                Text("Open and axial codes: " + names.prefix(12).joined(separator: ", ") + (names.count > 12 ? "…" : ""))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Picker("Move to", selection: $target) {
                ForEach(others) { l in Text(l.name).tag(l.key) }
            }
            .fixedSize()
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Move") {
                    let t = target
                    dismiss()
                    model.moveToLayer(item, layer: t)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(target.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 480)
        .onAppear { target = others.first?.key ?? "" }
    }
}

// MARK: - New code

struct NewCodeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let kind: CodeKind
    let parent: String?
    let child: String?
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("New \(kind.label)").font(.title3.weight(.semibold))
            if let parent, let p = model.project.code(parent) {
                Text("It will be evidence for “\(p.name)”.").foregroundStyle(.secondary)
            }
            if let child, let c = model.project.code(child) {
                Text("“\(c.name)” will be evidence for it.").foregroundStyle(.secondary)
            }
            Text(kind == .open ? "Open codes are evidenced directly by selections." : "Axial codes are built from open codes and other axial codes.")
                .font(.callout).foregroundStyle(.secondary)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(create)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Create", action: create)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    func create() {
        let n = name.trimmingCharacters(in: .whitespaces)
        guard !n.isEmpty else { return }
        dismiss()
        model.newCode(kind: kind, name: n, parent: parent, child: child)
    }
}

// MARK: - Consent form viewer

/// A consent form, shown read-only inside the app (never handed to another
/// app that might save it).
struct ConsentViewer: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let interviewee: String

    var body: some View {
        let person = model.project.interviewee(interviewee)
        VStack(spacing: 0) {
            HStack {
                Text("Consent form: \(model.personName(interviewee) ?? "")").font(.headline)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            .padding(12)
            Divider()
            if let path = person?.consentForm, let ft = model.fullTexts, let data = try? ft.data(path), let doc = PDFDocument(data: data) {
                ReadOnlyPDF(document: doc)
            } else {
                ContentUnavailableView("Consent Form Not Available", systemImage: "doc.questionmark",
                                       description: Text("It isn't in the full-texts folder on this Mac."))
            }
        }
        .frame(width: 680, height: 820)
    }
}

struct ReadOnlyPDF: NSViewRepresentable {
    let document: PDFDocument

    func makeCoordinator() -> LinkBlocker { LinkBlocker() }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.document = document
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {}

    /// Swallows link clicks, so no browser is ever opened.
    final class LinkBlocker: NSObject, PDFViewDelegate {
        nonisolated func pdfViewWillClick(onLink sender: PDFView, with url: URL) {}
    }
}

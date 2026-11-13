import AppKit
import EmpiricsCore
import SwiftUI

/// The inspector follows the page: on a file, its Selection and File tabs;
/// on a code, the code; on an attribute sheet, where it is used; on a list page,
/// the row selected in the table.
struct InspectorView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        switch model.sidebar {
        case .file(let key):
            VStack(spacing: 0) {
                Picker("Inspector", selection: $model.inspectorTab) {
                    ForEach(InspectorTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(10)
                Divider()
                InspectorScroll {
                    if model.inspectorTab == .selection {
                        SelectionInspector()
                    } else {
                        FileInspector(fileKey: key)
                    }
                }
            }
        case .code(let key):
            InspectorScroll { codeEditor(key) }
        case .attributeSheet(let key):
            InspectorScroll { AttributeSheetUsage(attributeSheetKey: key) }
        case .researcher(let key), .interviewee(let key):
            InspectorScroll { PersonRelated(key: key) }
        case .files:
            if let key = model.tableSelection, model.project.files[key] != nil {
                InspectorScroll { FileInspector(fileKey: key) }
            } else {
                nothing("Select a file to see its details.")
            }
        case .openCodes, .axialCodes:
            if let key = model.tableSelection, model.project.code(key) != nil {
                InspectorScroll { codeEditor(key) }
            } else {
                nothing("Select a code to see and edit it.")
            }
        case .attributeSheets:
            if let key = model.tableSelection, model.project.attributeSheets[key] != nil {
                InspectorScroll { AttributeSheetSummary(attributeSheetKey: key) }
            } else {
                nothing("Select an attribute sheet to see it.")
            }
        case .researchers, .interviewees:
            if let key = model.tableSelection, model.keyExists(key) {
                InspectorScroll { PersonForm(key: key, compact: true) }
            } else {
                nothing("Select someone to see their card.")
            }
        case .codingChart:
            if let key = model.tableSelection, model.project.files[key] != nil {
                InspectorScroll { FileInspector(fileKey: key) }
            } else if let key = model.tableSelection, model.project.code(key) != nil {
                InspectorScroll { codeEditor(key) }
            } else {
                nothing("Click a file, open code or axial code in the chart to see it here.")
            }
        case .attributeSheetReport:
            if let key = model.tableSelection, model.project.files[key] != nil {
                InspectorScroll { FileInspector(fileKey: key) }
            } else if let key = model.tableSelection, model.project.code(key) != nil {
                InspectorScroll { codeEditor(key) }
            } else if let key = model.tableSelection, model.project.interviewee(key) != nil {
                InspectorScroll { PersonForm(key: key, compact: true) }
            } else if let cb = model.shownReportAttributeSheet {
                InspectorScroll { AttributeSheetSummary(attributeSheetKey: cb) }
            } else {
                nothing("Choose an attribute sheet below the report.")
            }
        default:
            nothing("Nothing to inspect on this page.")
        }
    }

    @ViewBuilder
    func codeEditor(_ key: String) -> some View {
        if let code = model.project.code(key) {
            CodeEditor(code: code)
        }
    }

    func nothing(_ text: String) -> some View {
        ContentUnavailableView("No Selection", systemImage: "sidebar.trailing", description: Text(text))
    }
}

/// The inspector's scrolling, padded column.
struct InspectorScroll<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ScrollView {
            content()
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Selection

struct SelectionInspector: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if let key = model.focusedSelection, let s = model.project.selection(key) {
            focused(key, s)
        } else if model.hasTextSelection {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Selected Text", trailing: model.activeLayer?.name)
                QuoteBlock(text: model.textSelectionQuote, lineLimit: 12)
                HStack {
                    Button("Open Code…") { model.paletteVisible = true }.buttonStyle(.borderedProminent)
                        .help("Apply an open code to the selected text")
                    Button("Highlight Only") { model.highlightOnly() }
                    Button("Irrelevant") { model.toggleIrrelevant() }
                }
                .controlSize(.small)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "highlighter",
                                   description: Text("Click a highlight in the text to see its open codes and memos, or select text to code it."))
                .padding(.top, 40)
        }
    }

    @ViewBuilder
    func focused(_ key: String, _ s: CodeSelection) -> some View {
        let layer = model.index.layerOf[key].flatMap { model.project.layer($0) }
        let codes = (model.index.codesForSelection[key] ?? []).compactMap { layer?.codes[$0] }
        let colour = codes.first?.color ?? .gray
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: s.irrelevant ? "Irrelevant Text" : "Selection", trailing: layer?.name)
            if model.isLost(key) {
                Label("This selection's text could not be found after the file changed. Select the right text and choose Resize, or delete it.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            QuoteBlock(text: model.quoteText(s) ?? "(The text isn't available: quotes aren't stored in this project and the full-text isn't loaded.)",
                       color: s.irrelevant ? .gray : colour, lineLimit: 14)
            details(s)

            if s.irrelevant {
                Text("Irrelevant text can never be evidence for an open code in this layer.")
                    .font(.callout).foregroundStyle(.secondary)
                Button("Mark Relevant Again") {
                    model.focusedSelection = key
                    model.toggleIrrelevant()
                }
            } else {
                SectionHeader(title: "Open Codes", trailing: codes.isEmpty ? nil : "\(codes.count)")
                if codes.isEmpty {
                    Text("No open code yet.").foregroundStyle(.secondary)
                }
                ForEach(codes) { code in
                    EvidenceMemoRow(holder: code, target: key, shown: code)
                }
                HStack {
                    Button {
                        if model.openFileKey != s.fileKey { model.showSelection(key) }
                        model.paletteVisible = true
                    } label: {
                        Label("Add Open Code…", systemImage: "plus")
                    }
                    Spacer()
                    Button("Mark Irrelevant") { model.toggleIrrelevant() }
                        .disabled(!codes.isEmpty)
                        .help(codes.isEmpty ? "Mark this text irrelevant" : "Evidence can't be irrelevant: remove its open codes first")
                }
                .controlSize(.small)
            }

            Divider()
            HStack {
                if model.project.layers.count > 1 {
                    Button("Move to Layer…") { model.sheet = .moveToLayer(key) }
                }
                if model.hasTextSelection {
                    Button("Resize to Text Selection") { model.resizeFocusedToTextSelection() }
                }
                Spacer()
                Button(role: .destructive) {
                    model.deleteSelection(key)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    func details(_ s: CodeSelection) -> some View {
        let file = model.project.files[s.fileKey]
        VStack(alignment: .leading, spacing: 3) {
            if let file {
                Button {
                    model.showSelection(s.key)
                } label: {
                    Label(file.displayTitle, systemImage: file.kind.symbol).lineLimit(1)
                }
                .buttonStyle(.link)
            }
            if let first = s.first, let page = first.page {
                Text(s.spans.count > 1 ? "Pages \(page + 1)–\((s.spans.last?.page ?? page) + 1)" : "Page \(page + 1)")
                    .foregroundStyle(.secondary)
            }
            if model.project.settings.interlocutorLayer, let first = s.first, first.page == nil,
               let turn = TurnDetector.turn(at: first.start, in: model.turns(s.fileKey)) {
                Label(model.speakerName(turn.label, in: s.fileKey), systemImage: "person.wave.2")
                    .foregroundStyle(Color(nsColor: model.speakerColor(turn.label, in: s.fileKey)))
            }
            if !s.by.isEmpty || !s.created.isEmpty {
                Text([s.by.isEmpty ? nil : model.personName(s.by), s.created.isEmpty ? nil : String(s.created.prefix(10))]
                        .compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.tertiary)
            }
        }
        .font(.callout)
    }
}

/// One piece of evidence for a code, with the interpretation memo: why it
/// is evidence for the code. On a selection, `holder` and `shown` are the
/// same code; inside an axial code, `shown` is the code that is evidence.
struct EvidenceMemoRow: View {
    @Environment(AppModel.self) private var model
    var holder: QDACode
    var target: String
    var shown: QDACode

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                CodeDot(color: shown.color)
                Button(shown.name) { model.showCode(shown.key) }
                    .buttonStyle(.plain)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer(minLength: 4)
                WorkingBadge(text: model.wid(shown.key), color: shown.color)
                Button {
                    model.removeCode(holder.key, from: target)
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help(holder.key == shown.key ? "Remove this open code from the selection" : "Remove from \(holder.name)")
            }
            TextField("Why is this evidence for “\(holder.name)”?", text: Binding(
                get: { model.project.code(holder.key)?.memo(for: target) ?? "" },
                set: { model.setMemo(code: holder.key, target: target, $0) }
            ), axis: .vertical)
            .lineLimit(1...8)
            .textFieldStyle(.roundedBorder)
            .font(.callout)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(shown.color.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(shown.color.opacity(0.3), lineWidth: 0.5))
    }
}

// MARK: - Code

struct CodeEditor: View {
    @Environment(AppModel.self) private var model
    var code: QDACode

    var body: some View {
        let key = code.key
        let layerKey = model.index.layerOf[key] ?? ""
        let layer = model.project.layer(layerKey)
        VStack(alignment: .leading, spacing: 14) {
            InspectorTitle(model: model, title: code.kind.label, key: key, trailing: layer?.name)
            TextField("Name", text: Binding(get: { model.project.code(key)?.name ?? "" },
                                            set: { v in model.editCode(key) { $0.name = v } }))
                .textFieldStyle(.roundedBorder)
                .font(.title3)
            HStack {
                Picker("Kind", selection: Binding(get: { code.kind }, set: { k in
                    model.perform("Change Kind") { p in try p.setKind(code: key, k) }
                })) {
                    ForEach(CodeKind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .disabled(!code.evidence.isEmpty)
                .help(code.evidence.isEmpty ? "Open codes take selections as evidence; axial codes take codes" : "Remove the evidence to change the kind")
                if code.kind == .open {
                    Picker("Quick", selection: Binding(get: { model.quickSlot(of: key) ?? 0 }, set: { n in
                        if n == 0 {
                            if let s = model.quickSlot(of: key) { model.assignQuickCode(nil, slot: s) }
                        } else {
                            model.assignQuickCode(key, slot: n)
                        }
                    })) {
                        Text("None").tag(0)
                        ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .frame(width: 110)
                    .help("Quick code number: press it in the document to apply this code")
                }
            }
            ColourSwatches(selected: code.colour) { c in model.editCode(key) { $0.colour = c } }
            TextField("Description: what this code means, when to use it", text: Binding(
                get: { model.project.code(key)?.description ?? "" },
                set: { v in model.editCode(key) { $0.description = v } }
            ), axis: .vertical)
            .lineLimit(2...10)
            .textFieldStyle(.roundedBorder)

            evidence(code)
            partOf(code)

            SectionHeader(title: "Comments")
            StringListEditor(items: code.comments, placeholder: "Comment", addTitle: "Add Comment") { list in
                model.editCode(key) { $0.comments = list }
            }
            SectionHeader(title: "Questions")
            Text("Unresolved matters, to come back to.").font(.caption).foregroundStyle(.secondary)
            StringListEditor(items: code.questions, placeholder: "Question", addTitle: "Add Question") { list in
                model.editCode(key) { $0.questions = list }
            }

            interrelations(code)

            SectionHeader(title: "Attribute Sheets")
            AttributeSheetAssociations(target: key, kind: code.kind == .open ? .openCodes : .axialCodes)

            Divider()
            HStack {
                if model.project.layers.count > 1 {
                    Button("Move to Layer…") { model.sheet = .moveToLayer(key) }
                }
                Spacer()
                Button(role: .destructive) {
                    model.deleteCode(key)
                } label: {
                    Label(code.kind == .open ? "Delete Open Code…" : "Delete Axial Code…", systemImage: "trash")
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    func evidence(_ code: QDACode) -> some View {
        let key = code.key
        if code.kind == .open {
            let files = model.index.filesForCode[key]?.count ?? 0
            HStack {
                Text("\(code.evidence.count) selection\(code.evidence.count == 1 ? "" : "s") in \(files) file\(files == 1 ? "" : "s")")
                    .foregroundStyle(.secondary)
                Spacer()
                if model.sidebar != .code(key) {
                    Button("Show Evidence") { model.showCode(key) }
                        .controlSize(.small)
                }
            }
        } else {
            SectionHeader(title: "Built From", trailing: "\(code.evidence.count)")
            let layer = model.index.layerOf[key].flatMap { model.project.layer($0) }
            ForEach(code.evidence, id: \.target) { e in
                if let child = layer?.codes[e.target] {
                    EvidenceMemoRow(holder: code, target: e.target, shown: child)
                }
            }
            HStack {
                let candidates = (layer?.codes.values.map { $0 } ?? [])
                    .filter { model.project.evidenceProblem(code: key, target: $0.key) == nil }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                Menu("Add Open or Axial Code") {
                    ForEach(candidates) { c in
                        Button(model.itemLabel(c.key)) { model.addEvidence(code: key, target: c.key) }
                    }
                    if !candidates.isEmpty { Divider() }
                    Button("New Open Code…") { model.sheet = .newCode(kind: .open, parent: key, child: nil) }
                    Button("New Axial Code…") { model.sheet = .newCode(kind: .axial, parent: key, child: nil) }
                }
                .fixedSize()
                Spacer()
                if model.sidebar != .code(key) {
                    Button("Show Evidence") { model.showCode(key) }
                }
            }
            .controlSize(.small)
        }
    }

    @ViewBuilder
    func partOf(_ code: QDACode) -> some View {
        let key = code.key
        let parents = (model.index.parents[key] ?? []).compactMap { model.project.code($0) }
        let layer = model.index.layerOf[key].flatMap { model.project.layer($0) }
        let axial = (layer?.codes.values.map { $0 } ?? [])
            .filter { $0.kind == .axial && model.project.evidenceProblem(code: $0.key, target: key) == nil }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        SectionHeader(title: "Evidence For", trailing: parents.isEmpty ? nil : "\(parents.count)")
        FlowChips(codes: parents) { parent in
            model.perform("Remove from \(parent.name)") { p in p.removeEvidence(code: parent.key, target: key) }
        }
        Menu("Add to Axial Code") {
            ForEach(axial) { a in
                Button(model.itemLabel(a.key)) { model.addEvidence(code: a.key, target: key) }
            }
            if !axial.isEmpty { Divider() }
            Button("New Axial Code…") { model.sheet = .newCode(kind: .axial, parent: nil, child: key) }
        }
        .fixedSize()
        .controlSize(.small)
    }

    @ViewBuilder
    func interrelations(_ code: QDACode) -> some View {
        let key = code.key
        SectionHeader(title: "Interrelations", trailing: code.interrelations.isEmpty ? nil : "\(code.interrelations.count)")
        Text("How two or more pieces of this code's evidence relate.").font(.caption).foregroundStyle(.secondary)
        ForEach(code.interrelations) { x in
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(x.type.isEmpty ? "Untyped" : x.type)
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.15)))
                    Text("\(x.members.count) items").font(.caption).foregroundStyle(.secondary)
                    if x.members.count < 2 {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                            .help("An interrelation needs at least two items")
                    }
                    Spacer()
                    Button("Edit…") { model.sheet = .interrelation(code: key, key: x.key) }
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                }
                ForEach(x.members, id: \.self) { m in
                    Text("• " + model.evidenceLabel(m))
                        .font(.caption)
                        .lineLimit(2)
                        .foregroundStyle(.secondary)
                }
                if !x.description.isEmpty {
                    Text(x.description).font(.callout).lineLimit(6)
                }
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        }
        Button {
            model.sheet = .interrelation(code: key, key: nil)
        } label: {
            Label("New Interrelation…", systemImage: "plus")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .disabled(code.evidence.count < 2)
        .help(code.evidence.count < 2 ? "Needs at least two pieces of evidence" : "Comment on how pieces of evidence relate")
    }
}

extension AppModel {
    /// A short label for an evidence item: a quote excerpt or a code name.
    func evidenceLabel(_ key: String) -> String {
        if project.code(key) != nil { return itemLabel(key) }
        if let s = project.selection(key) {
            let file = project.files[s.fileKey]?.displayTitle ?? ""
            let q = quoteText(s).map { String($0.replacingOccurrences(of: "\n", with: " ").prefix(90)) } ?? "(text not available)"
            return "“\(q)” — \(file)"
        }
        return "(removed)"
    }
}

/// Code chips that wrap, each with a remove button.
struct FlowChips: View {
    @Environment(AppModel.self) private var model
    var codes: [QDACode]
    var remove: (QDACode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(codes) { c in
                HStack(spacing: 4) {
                    CodeChip(code: c, compact: true, badge: model.wid(c.key))
                        .onTapGesture { model.showCode(c.key) }
                    Button {
                        remove(c)
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from \(c.name)")
                }
            }
        }
    }
}

struct ColourSwatches: View {
    var selected: String
    var choose: (String) -> Void

    var body: some View {
        HStack(spacing: 5) {
            ForEach(CodePalette.colours, id: \.self) { hex in
                Button {
                    choose(hex)
                } label: {
                    Circle()
                        .fill(Color(nsColor: NSColor.hex(hex) ?? .gray))
                        .frame(width: 16, height: 16)
                        .overlay(Circle().strokeBorder(Color.primary.opacity(selected.uppercased() == hex ? 0.8 : 0.1),
                                                       lineWidth: selected.uppercased() == hex ? 2 : 0.5))
                }
                .buttonStyle(.plain)
                .help(hex)
            }
            ColorPicker("", selection: Binding(
                get: { Color(nsColor: NSColor.hex(selected) ?? .gray) },
                set: { choose(NSColor($0).hexString) }
            ), supportsOpacity: false)
            .labelsHidden()
            .help("Another colour")
        }
    }
}

// MARK: - File

struct FileInspector: View {
    @Environment(AppModel.self) private var model
    let fileKey: String

    var body: some View {
        if let file = model.project.files[fileKey] {
            editor(fileKey, file)
        } else {
            ContentUnavailableView("File Removed", systemImage: "doc",
                                   description: Text("This file is no longer in the project."))
                .padding(.top, 40)
        }
    }

    @ViewBuilder
    func editor(_ key: String, _ file: EmpiricalFile) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorTitle(model: model, title: "Empirical File", key: key, trailing: file.kind.label)
            if model.sidebar == .files {
                Button("Open File") { model.show(.file(key)) }
                    .controlSize(.small)
            }
            LabeledField("Title") {
                TextField(file.fileName, text: Binding(get: { model.project.files[key]?.title ?? "" },
                                                       set: { v in model.editFile(key) { $0.title = v } }))
                    .textFieldStyle(.roundedBorder)
            }
            LabeledField("ID") {
                TextField("e.g. SF-2026-KXV-01", text: Binding(get: { model.project.files[key]?.customID ?? "" },
                                                               set: { v in model.editFile(key) { $0.customID = v } }))
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
            }
            LabeledField("Date") {
                HStack {
                    if let date = Stamp.parseDay(file.date) {
                        DatePicker("Date", selection: Binding(get: { date }, set: { d in model.editFile(key) { $0.date = Stamp.day(d) } }),
                                   displayedComponents: .date)
                            .labelsHidden()
                            .datePickerStyle(.field)
                        Button {
                            model.editFile(key) { $0.date = "" }
                        } label: {
                            Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("No date")
                    } else if !file.date.isEmpty {
                        TextField("YYYY-MM-DD", text: Binding(get: { model.project.files[key]?.date ?? "" },
                                                              set: { v in model.editFile(key) { $0.date = v } }))
                            .textFieldStyle(.roundedBorder)
                    } else {
                        Button("Add Date") { model.editFile(key) { $0.date = Stamp.day() } }
                            .controlSize(.small)
                    }
                }
            }
            LabeledField("Status") {
                Picker("Status", selection: Binding(get: { file.status }, set: { model.setStatus($0, file: key) })) {
                    ForEach(CodingStatus.allCases, id: \.self) { Label($0.label, systemImage: $0.symbol).tag($0) }
                }
                .labelsHidden()
            }
            LabeledField("Location") {
                VStack(alignment: .leading, spacing: 4) {
                    Text(file.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(3)
                    Button("Update from New Version…") { model.updateFile(key) }
                        .controlSize(.small)
                        .help("Point this file at a corrected or re-exported version of its full-text, keeping its coding")
                }
            }
            fingerprint(key, file)
            stats(key)

            SectionHeader(title: "Attribute Sheets")
            AttributeSheetAssociations(target: key, kind: .files)

            if model.project.settings.interlocutorLayer, file.kind.isText {
                SectionHeader(title: "Speakers")
                let map = model.project.speakerMaps[key]
                let candidates = model.speakerCandidates(key)
                if candidates.isEmpty && (map?.assignments.isEmpty ?? true) {
                    Text("No speaker header lines found.").foregroundStyle(.secondary).font(.callout)
                } else {
                    ForEach(candidates, id: \.speaker) { c in
                        HStack {
                            Text(c.label).lineLimit(1)
                            Spacer()
                            if map?.ignored.contains(c.speaker) == true {
                                Text("Not a speaker").foregroundStyle(.tertiary)
                            } else if let p = model.person(forSpeaker: c.label, in: key), let name = model.personName(p) {
                                Text(name).foregroundStyle(Color(nsColor: model.speakerColor(c.label, in: key)))
                            } else {
                                Text("Unassigned").foregroundStyle(.orange)
                            }
                        }
                        .font(.callout)
                    }
                }
                Button("Speakers…") { model.sheet = .speakers(key) }
                    .controlSize(.small)
            }

            Divider()
            HStack {
                Spacer()
                Button(role: .destructive) {
                    model.removeFile(key)
                } label: {
                    Label("Remove from Project…", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    func fingerprint(_ key: String, _ file: EmpiricalFile) -> some View {
        let _ = model.documentsRevision
        if let current = model.documents.fingerprints[key] {
            if current == file.fingerprint {
                Label("Unchanged since it was catalogued", systemImage: "checkmark.seal")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Changed since it was catalogued", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    func stats(_ key: String) -> some View {
        let here = model.activeLayer?.selections[key] ?? []
        let coded = here.filter { !$0.irrelevant && !(model.index.codesForSelection[$0.key] ?? []).isEmpty }.count
        let irrelevant = here.filter(\.irrelevant).count
        let codes = Set(here.flatMap { model.index.codesForSelection[$0.key] ?? [] }).count
        Text("In \(model.activeLayer?.name ?? "this layer"): \(coded) coded selection\(coded == 1 ? "" : "s"), \(codes) open code\(codes == 1 ? "" : "s"), \(here.count - coded - irrelevant) uncoded, \(irrelevant) irrelevant.")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// A label above a field, as in the inspector of Pages and Keynote.
struct LabeledField<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            content()
        }
    }
}

// MARK: - Attribute Sheet associations

/// The attribute sheets associated with a file or code: this Mac's researcher's
/// sheet for each (complete, flagged or not started), who else answered,
/// and adding or removing attribute sheets.
struct AttributeSheetAssociations: View {
    @Environment(AppModel.self) private var model
    var target: String
    var kind: AttributeSheetTarget

    var body: some View {
        let books = model.project.attributeSheets(for: target)
        let available = model.project.sortedAttributeSheets.filter { $0.appliesTo.contains(kind) && !books.contains($0) }
        VStack(alignment: .leading, spacing: 6) {
            if books.isEmpty {
                Text("No attribute sheets.").foregroundStyle(.secondary).font(.callout)
            }
            ForEach(books) { cb in
                row(cb)
            }
            Menu("Add Attribute Sheet") {
                ForEach(available) { cb in
                    Button(model.itemLabel(cb.key)) {
                        model.perform("Add Attribute Sheet") { p in try p.associate(attributeSheet: cb.key, with: target) }
                    }
                }
                if available.isEmpty {
                    Text("No other attribute sheets apply to \(kind.label.lowercased())")
                }
                Divider()
                Button("Edit Attribute Sheets…") { model.sidebar = .attributeSheets }
            }
            .fixedSize()
            .controlSize(.small)
        }
    }

    @ViewBuilder
    func row(_ cb: AttributeSheet) -> some View {
        let mine = model.responseID(attributeSheet: cb.key, target: target).flatMap { model.project.responses[$0] }
        let completeness = SheetCompleteness.of(mine?.answers ?? [:], against: cb)
        let others = model.sheets(attributeSheet: cb.key, target: target).filter { $0.id != mine?.id }
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                if mine == nil {
                    Image(systemName: "circle.dashed").foregroundStyle(.secondary).help("Not filled in yet")
                } else if completeness.isComplete {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).help("Complete")
                } else {
                    Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.orange)
                        .help("Mandatory questions unanswered: \(completeness.missingFlagged.map(\.label).joined(separator: ", "))")
                }
                Text(cb.title).lineLimit(1)
                WorkingBadge(text: model.wid(cb.key), color: nil)
                Spacer()
                Button(mine == nil ? "Fill In…" : "Edit…") { model.openResponseSheet(attributeSheet: cb.key, target: target) }
                    .controlSize(.small)
                Menu {
                    Button("Remove Attribute Sheet") {
                        model.perform("Remove Attribute Sheet") { p in p.dissociate(attributeSheet: cb.key, from: target) }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            if mine != nil {
                Text("\(completeness.answered) of \(completeness.total) answered")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !others.isEmpty {
                Text("Also answered by " + others.map { model.personName($0.id.researcher) ?? "someone" }.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}

import AppKit
import EmpiricsCore
import SwiftUI

/// A codebook's own page: its title, what it applies to, and its
/// questions, each with a short label, the full question, the kind of
/// answer, and whether it is mandatory.
struct CodebookEditor: View {
    @Environment(AppModel.self) private var model
    var codebook: Codebook
    var delete: () -> Void

    var body: some View {
        let key = codebook.key
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    TextField("Title", text: Binding(get: { model.project.codebooks[key]?.title ?? "" },
                                                     set: { v in model.edit { $0.codebooks[key]?.title = v } }))
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                    WorkingBadge(text: model.wid(key), color: nil)
                }
                TextField("Description (what this codebook is for)", text: Binding(
                    get: { model.project.codebooks[key]?.description ?? "" },
                    set: { v in model.edit { $0.codebooks[key]?.description = v } }
                ), axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
                HStack(spacing: 16) {
                    Text("Applies to").foregroundStyle(.secondary)
                    ForEach(CodebookTarget.allCases, id: \.self) { t in
                        Toggle(t.label, isOn: Binding(get: { codebook.appliesTo.contains(t) }, set: { on in
                            model.perform("Change Codebook") { p in
                                if on { p.codebooks[key]?.appliesTo.insert(t) } else { p.codebooks[key]?.appliesTo.remove(t) }
                            }
                        }))
                        .toggleStyle(.checkbox)
                    }
                }
                usage
                Divider()
                HStack {
                    Text("Questions").font(.headline)
                    Spacer()
                    HStack(spacing: 10) {
                        RequirementMark(requirement: .blocking)
                        Text("blocks saving").font(.caption).foregroundStyle(.secondary)
                        RequirementMark(requirement: .flagged)
                        Text("flagged").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if codebook.questions.isEmpty {
                    Text("No questions yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(codebook.questions.enumerated()), id: \.element.key) { i, q in
                    QuestionEditor(codebook: key, question: q, index: i, count: codebook.questions.count)
                }
                Button {
                    model.perform("Add Question") { p in
                        let q = CodebookQuestion(key: p.newKey(Keys.question), label: "Question \((p.codebooks[key]?.questions.count ?? 0) + 1)")
                        p.codebooks[key]?.questions.append(q)
                    }
                } label: {
                    Label("Add Question", systemImage: "plus")
                }
                Divider()
                HStack {
                    Spacer()
                    Button(role: .destructive, action: delete) { Label("Delete Codebook…", systemImage: "trash") }
                        .controlSize(.small)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    var usage: some View {
        let files = model.project.files.values.filter { $0.codebooks.contains(codebook.key) }.count
        let codes = model.project.layers.flatMap { $0.codes.values }.filter { $0.codebooks.contains(codebook.key) }.count
        let sheets = model.project.responses.values.filter { $0.id.codebook == codebook.key }
        let complete = sheets.filter { SheetCompleteness.of($0.answers, against: codebook).isComplete }.count
        Text("Associated with \(files) file\(files == 1 ? "" : "s") and \(codes) code\(codes == 1 ? "" : "s") · \(sheets.count) response sheet\(sheets.count == 1 ? "" : "s"), \(complete) complete")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct QuestionEditor: View {
    @Environment(AppModel.self) private var model
    var codebook: String
    var question: CodebookQuestion
    var index: Int
    var count: Int

    private func update(_ change: @escaping (inout CodebookQuestion) -> Void) {
        let qk = question.key
        model.edit { p in
            guard let i = p.codebooks[codebook]?.questions.firstIndex(where: { $0.key == qk }) else { return }
            change(&p.codebooks[codebook]!.questions[i])
        }
    }

    var body: some View {
        let q = question
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index + 1).").font(.headline).monospacedDigit().foregroundStyle(.secondary)
                TextField("Label", text: Binding(get: { q.label }, set: { v in
                    update { $0.label = String(v.prefix(CodebookQuestion.maxLabelLength)) }
                }))
                .textFieldStyle(.roundedBorder)
                .frame(width: 170)
                Text("\(q.label.count)/\(CodebookQuestion.maxLabelLength)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(q.label.count >= CodebookQuestion.maxLabelLength ? Color.orange : Color.secondary)
                RequirementMark(requirement: q.requirement)
                Spacer()
                Button {
                    model.perform("Move Question") { p in
                        guard index > 0 else { return }
                        p.codebooks[codebook]?.questions.swapAt(index, index - 1)
                    }
                } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0)
                .help("Move up")
                Button {
                    model.perform("Move Question") { p in
                        guard index < count - 1 else { return }
                        p.codebooks[codebook]?.questions.swapAt(index, index + 1)
                    }
                } label: { Image(systemName: "arrow.down") }
                .disabled(index >= count - 1)
                .help("Move down")
                Button {
                    model.perform("Delete Question") { p in p.deleteQuestion(q.key, from: codebook) }
                } label: { Image(systemName: "trash") }
                .help("Delete the question (and its answers)")
            }
            .buttonStyle(.borderless)
            TextField("The full question", text: Binding(get: { q.text }, set: { v in update { $0.text = v } }), axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 16) {
                Picker("Answer", selection: Binding(get: { q.type }, set: { v in
                    model.perform("Change Answer Type") { p in
                        guard let i = p.codebooks[codebook]?.questions.firstIndex(where: { $0.key == q.key }) else { return }
                        p.codebooks[codebook]!.questions[i].type = v
                    }
                })) {
                    ForEach(QuestionType.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .fixedSize()
                Picker("Requirement", selection: Binding(get: { q.requirement }, set: { v in
                    model.perform("Change Requirement") { p in
                        guard let i = p.codebooks[codebook]?.questions.firstIndex(where: { $0.key == q.key }) else { return }
                        p.codebooks[codebook]!.questions[i].requirement = v
                    }
                })) {
                    ForEach(Requirement.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .fixedSize()
            }
            if q.type.usesOptions {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Options").font(.caption).foregroundStyle(.secondary)
                        StringListEditor(items: q.options, placeholder: "Option", addTitle: "Add Option", multiline: false) { list in
                            update { $0.options = list }
                        }
                    }
                    .frame(maxWidth: 360, alignment: .leading)
                    Toggle("Strictly predefined", isOn: Binding(get: { q.strict }, set: { v in
                        model.perform(v ? "Make List Strict" : "Allow New Options") { p in
                            guard let i = p.codebooks[codebook]?.questions.firstIndex(where: { $0.key == q.key }) else { return }
                            p.codebooks[codebook]!.questions[i].strict = v
                        }
                    }))
                    .toggleStyle(.checkbox)
                    .help("If off, researchers can add options while coding; new options join this list")
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

// MARK: - Response sheet

/// Answering a codebook about one file or code. Mandatory, blocking
/// questions must be answered before the sheet can be saved; mandatory,
/// non-blocking ones are flagged but don't stop it.
struct ResponseSheetView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let id: ResponseID
    @State private var answers: [String: Answer] = [:]
    @State private var newOptions: [String: String] = [:]
    @State private var loaded = false

    var body: some View {
        let codebook = model.project.codebooks[id.codebook]
        VStack(spacing: 0) {
            if let codebook {
                let completeness = SheetCompleteness.of(answers, against: codebook)
                VStack(alignment: .leading, spacing: 4) {
                    Text(codebook.title).font(.title2.weight(.semibold))
                    Text(targetTitle).foregroundStyle(.secondary)
                    if !id.researcher.isEmpty {
                        Text("Answers by \(model.personName(id.researcher) ?? "unknown researcher")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if !codebook.description.isEmpty {
                        Text(codebook.description).font(.callout).padding(.top, 4)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        ForEach(codebook.questions) { q in
                            questionView(q, flagged: completeness.missingFlagged.contains(q),
                                         blocking: completeness.missingBlocking.contains(q))
                        }
                        if codebook.questions.isEmpty {
                            Text("This codebook has no questions yet.").foregroundStyle(.secondary)
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Divider()
                HStack {
                    if !completeness.missingBlocking.isEmpty {
                        Label("Answer \(completeness.missingBlocking.map(\.label).joined(separator: ", ")) to save.",
                              systemImage: "asterisk")
                            .foregroundStyle(.red)
                            .font(.callout)
                            .lineLimit(2)
                    } else if !completeness.missingFlagged.isEmpty {
                        Label("Still to answer: \(completeness.missingFlagged.map(\.label).joined(separator: ", ")). You can save now and come back.",
                              systemImage: "exclamationmark.circle")
                            .foregroundStyle(.orange)
                            .font(.callout)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                    Button("Save") {
                        var sheet = model.project.responses[id] ?? ResponseSheet(id: id)
                        sheet.answers = answers
                        if model.perform("Save Response Sheet", { p in try p.saveSheet(sheet) }) { dismiss() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!completeness.canSave)
                }
                .padding(16)
            } else {
                Text("This codebook no longer exists.").padding(40)
                Button("Close") { dismiss() }.padding(.bottom, 20)
            }
        }
        .frame(width: 620, height: 640)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            answers = model.project.responses[id]?.answers ?? [:]
        }
    }

    var targetTitle: String {
        if let f = model.project.files[id.target] { return "File: " + f.displayTitle }
        if let c = model.project.code(id.target) { return "\(c.kind.label): \(c.name)" }
        return id.target
    }

    @ViewBuilder
    func questionView(_ q: CodebookQuestion, flagged: Bool, blocking: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(q.label).font(.headline)
                RequirementMark(requirement: q.requirement)
                if flagged {
                    Text("unanswered").font(.caption).foregroundStyle(.orange)
                }
            }
            if !q.text.isEmpty {
                Text(q.text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            switch q.type {
            case .text:
                TextField("Answer", text: Binding(
                    get: { if case .text(let t) = answers[q.key] { return t } else { return "" } },
                    set: { answers[q.key] = .text($0) }
                ), axis: .vertical)
                .lineLimit(2...10)
                .textFieldStyle(.roundedBorder)
            case .chooseOne:
                let current: String = { if case .one(let v) = answers[q.key] { return v } else { return "" } }()
                let options = q.options + (current.isEmpty || q.options.contains(current) ? [] : [current])
                Picker(q.label, selection: Binding(get: { current }, set: { answers[q.key] = .one($0) })) {
                    Text("—").tag("")
                    ForEach(options, id: \.self) { Text($0).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.radioGroup)
                if !q.strict { newOption(q) }
            case .chooseMany:
                let current: [String] = { if case .many(let v) = answers[q.key] { return v } else { return [] } }()
                let options = q.options + current.filter { !q.options.contains($0) }
                ForEach(options, id: \.self) { o in
                    Toggle(o, isOn: Binding(get: { current.contains(o) }, set: { on in
                        var list = current.filter { $0 != o }
                        if on { list.append(o) }
                        answers[q.key] = .many(options.filter { list.contains($0) })
                    }))
                    .toggleStyle(.checkbox)
                }
                if !q.strict { newOption(q) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(blocking ? Color.red.opacity(0.06) : flagged ? Color.orange.opacity(0.06) : .clear))
    }

    /// For lists that aren't strictly predefined: a new option, chosen at
    /// once (and added to the codebook when the sheet is saved).
    @ViewBuilder
    func newOption(_ q: CodebookQuestion) -> some View {
        HStack {
            TextField("Another option…", text: Binding(get: { newOptions[q.key] ?? "" }, set: { newOptions[q.key] = $0 }))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 260)
                .onSubmit { addOption(q) }
            Button("Add") { addOption(q) }
                .disabled((newOptions[q.key] ?? "").trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .controlSize(.small)
    }

    func addOption(_ q: CodebookQuestion) {
        let v = (newOptions[q.key] ?? "").trimmingCharacters(in: .whitespaces)
        guard !v.isEmpty else { return }
        if q.type == .chooseOne {
            answers[q.key] = .one(v)
        } else {
            var list: [String] = { if case .many(let l) = answers[q.key] { return l } else { return [] } }()
            if !list.contains(v) { list.append(v) }
            answers[q.key] = .many(list)
        }
        newOptions[q.key] = ""
    }
}

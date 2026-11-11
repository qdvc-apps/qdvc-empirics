import AppKit
import EmpiricsCore
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

// Updating an empirical file in place (File › Update Empirical File…): the
// file keeps its key, coding, codebooks, response sheets and speakers, and
// is pointed at a new version of its full-text (a corrected transcript, a
// re-exported PDF) in the full-texts folder, with its selections found again
// in the new text. The full-texts folder is only read, as always: the old
// version stays where it is. A wizard in three steps: choose the new
// version, check what of the coding can be found in it, confirm.

/// A speaker label of the file's Interlocutor layer, and whether the new
/// version still has header lines for it.
struct SpeakerCheck: Identifiable {
    var label: String
    var person: String
    var found: Bool

    var id: String { label }
}

/// A proposed new version of a file's full-text, checked against the file's
/// selections in every layer.
struct FileUpdatePlan {
    var fileKey: String
    /// The new version, relative to the full-texts folder.
    var path: String
    var kind: FileKind
    var fingerprint: String
    var checks: [Anchoring.Check]
    /// Whether the version the selections were made on could still be read,
    /// to take the text to look for from it (irrelevant selections, and all
    /// selections when quotes aren't stored).
    var hadOldText: Bool
    var speakers: [SpeakerCheck]
    var samePath: Bool
    var sameContent: Bool

    var unchanged: Int { checks.filter { $0.fate == .unchanged }.count }
    var moved: Int { checks.filter { if case .moved = $0.fate { return true } else { return false } }.count }
    var unverified: Int { checks.filter { $0.fate == .unverified }.count }
    var lost: Int { checks.filter { $0.fate == .lost }.count }
}

extension AppModel {
    /// What choosing a new version gave.
    enum NewVersionChoice {
        case cancelled
        case chosen(String)
        case problem(String)
    }

    /// The file whose update File › Update Empirical File… starts: the open
    /// file, or the file selected in the Empirical Files table.
    var fileToUpdate: String? {
        if let k = openFileKey { return k }
        if sidebar == .files, let k = tableSelection, project.files[k] != nil { return k }
        return nil
    }

    /// Starts updating a file from a new version of its full-text.
    func updateFile(_ key: String) {
        guard project.files[key] != nil else { return }
        guard fullTexts != nil else {
            chooseFullTextsFolder()
            return
        }
        sheet = .updateFile(key)
    }

    /// The text of each page of a full-text (one "page" for text files).
    func pageTexts(_ data: Data, kind: FileKind) -> [String]? {
        if kind == .pdf {
            guard let doc = PDFDocument(data: data) else { return nil }
            return (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
        }
        return [TextNormaliser.text(from: data)]
    }

    /// The version of a file's full-text its selections were made on, if it
    /// can still be read: the copy read this session, or the file itself,
    /// as long as it still has the catalogued fingerprint.
    func cataloguedPages(_ key: String) -> [String]? {
        guard let file = project.files[key], !file.fingerprint.isEmpty else { return nil }
        if let pages = documents.pages[key], documents.fingerprints[key] == file.fingerprint { return pages }
        guard let ft = fullTexts, ft.exists(file.path), let data = try? ft.data(file.path),
              "sha256:" + SHA256.hex(data) == file.fingerprint else { return nil }
        return pageTexts(data, kind: file.kind)
    }

    /// Asks for the new version of a file: a file of the same sort (text or
    /// PDF) inside the full-texts folder, not catalogued as another file.
    func chooseNewVersion(for key: String) -> NewVersionChoice {
        guard let file = project.files[key] else { return .problem("This file is no longer in the project.") }
        guard let ft = fullTexts else { return .problem("The full-texts folder isn't set on this Mac.") }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = ft.url((file.path as NSString).deletingLastPathComponent)
        if file.kind == .pdf {
            panel.allowedContentTypes = [.pdf]
        } else {
            var types: [UTType] = [.plainText]
            if let md = UTType(filenameExtension: "md") { types.append(md) }
            if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
            panel.allowedContentTypes = types
        }
        panel.prompt = "Choose"
        panel.message = "Choose the new version of “\(file.displayTitle)” in the full-texts folder. It is only ever read."
        guard panel.runModal() == .OK, let url = panel.url else { return .cancelled }
        guard let rel = ft.relativePath(of: url) else {
            return .problem("“\(url.lastPathComponent)” isn't in the full-texts folder. QDVC Empirics never copies or writes into that folder: move the new version there yourself, then choose it.")
        }
        guard let kind = FileKind.forPath(rel) else {
            return .problem("“\(url.lastPathComponent)” isn't a plain-text, Markdown or PDF file.")
        }
        guard kind.isText == file.kind.isText else {
            return .problem(file.kind == .pdf
                ? "“\(file.displayTitle)” is coded on PDF pages, so its new version must be a PDF too."
                : "“\(file.displayTitle)” is coded as text, so its new version must be a plain-text or Markdown file, not a PDF.")
        }
        if let other = project.file(path: rel), other.key != key {
            return .problem("“\(rel)” is already in the project as \(itemLabel(other.key)).")
        }
        return .chosen(rel)
    }

    /// Reads a proposed new version and checks every selection of the file
    /// against it. Changes nothing.
    func planUpdate(file key: String, path: String) throws -> FileUpdatePlan {
        guard let file = project.files[key] else { throw RuleError("This file is no longer in the project.") }
        guard let ft = fullTexts else { throw RuleError("The full-texts folder isn't set on this Mac.") }
        let kind = FileKind.forPath(path) ?? file.kind
        let data: Data
        do {
            data = try ft.data(path)
        } catch {
            throw RuleError("Couldn't read “\(path)” from the full-texts folder: \(error.localizedDescription)")
        }
        guard let pages = pageTexts(data, kind: kind) else {
            throw RuleError("“\((path as NSString).lastPathComponent)” can't be read as a PDF.")
        }
        let fingerprint = "sha256:" + SHA256.hex(data)
        let old = cataloguedPages(key)
        let checks = Anchoring.check(project, file: key, newPages: pages, oldPages: old)
        var speakers: [SpeakerCheck] = []
        if kind.isText, let map = project.speakerMaps[key], let text = pages.first {
            let found = Set(TurnDetector.candidates(in: text).map(\.speaker))
            speakers = map.assignments.map { a in
                SpeakerCheck(label: a.label, person: a.person, found: found.contains(TurnDetector.normalise(a.label)))
            }
        }
        return FileUpdatePlan(fileKey: key, path: path, kind: kind, fingerprint: fingerprint, checks: checks,
                              hadOldText: old != nil, speakers: speakers, samePath: path == file.path,
                              sameContent: fingerprint == file.fingerprint)
    }

    /// Points the file at its new version and moves its selections, as
    /// checked: one step of Edit › Undo.
    func applyUpdate(_ plan: FileUpdatePlan, deleteLost: Bool) {
        let key = plan.fileKey
        guard let file = project.files[key] else { return }
        let done = perform("Update Empirical File") { p in
            Anchoring.apply(plan.checks, to: &p, deleteLost: deleteLost)
            p.files[key]?.path = plan.path
            p.files[key]?.kind = plan.kind
            p.files[key]?.fingerprint = plan.fingerprint
        }
        guard done else { return }
        let lost = plan.checks.filter { $0.fate == .lost }.map(\.selection)
        lostSelections.subtract(plan.checks.map(\.selection))
        if !deleteLost { lostSelections.formUnion(lost) }
        var text = "Updated “\(file.displayTitle)”" + (plan.samePath ? "." : " to \(plan.path).")
        var parts: [String] = []
        if plan.unchanged > 0 { parts.append("\(plan.unchanged) selection\(plan.unchanged == 1 ? "" : "s") unchanged") }
        if plan.moved > 0 { parts.append("\(plan.moved) moved with the text") }
        if plan.unverified > 0 { parts.append("\(plan.unverified) kept where \(plan.unverified == 1 ? "it was" : "they were"), unchecked") }
        if !lost.isEmpty { parts.append("\(lost.count) not found (\(deleteLost ? "deleted" : "kept and flagged"))") }
        if !parts.isEmpty { text += " " + parts.joined(separator: ", ") + "." }
        notice = Notice(text: text, isWarning: !lost.isEmpty && !deleteLost)
    }
}

// MARK: - The wizard

struct UpdateFileSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let fileKey: String

    enum Stage: Int, CaseIterable {
        case choose
        case check
        case confirm

        var title: String {
            switch self {
            case .choose: return "Choose the new version"
            case .check: return "Check the coding against it"
            case .confirm: return "Confirm"
            }
        }
    }

    @State private var stage: Stage = .choose
    @State private var path: String?
    @State private var plan: FileUpdatePlan?
    @State private var problem: String?
    @State private var deleteLost = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let file = model.project.files[fileKey] {
                Group {
                    switch stage {
                    case .choose: chooseStage(file)
                    case .check: checkStage(file)
                    case .confirm: confirmStage(file)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ContentUnavailableView("File Removed", systemImage: "doc",
                                       description: Text("This file is no longer in the project."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            buttons
        }
        .frame(width: 660, height: 580)
    }

    // MARK: Parts

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Update Empirical File").font(.title2.weight(.semibold))
            HStack(spacing: 6) {
                ItemLine(model: model, key: fileKey, iconWidth: 16)
                    .fixedSize()
                Spacer()
                Text("Step \(stage.rawValue + 1) of \(Stage.allCases.count): \(stage.title)")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }

    var buttons: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if stage != .choose {
                Button("Back") {
                    problem = nil
                    stage = Stage(rawValue: stage.rawValue - 1) ?? .choose
                }
            }
            switch stage {
            case .choose:
                Button("Check") { check() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(path == nil)
            case .check:
                Button("Continue") { stage = .confirm }
                    .keyboardShortcut(.defaultAction)
                    .disabled(plan == nil)
            case .confirm:
                Button("Update File") {
                    guard let plan else { return }
                    let delete = deleteLost
                    dismiss()
                    model.applyUpdate(plan, deleteLost: delete)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(plan == nil)
            }
        }
        .padding(16)
    }

    // MARK: Step 1: choose

    func chooseStage(_ file: EmpiricalFile) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Point this file at a new version of its full-text, such as a corrected transcript or a re-exported PDF. The file keeps its title, ID, date, status, coding, codebooks, response sheets and speakers; its selections are looked for in the new version in the next step.")
                .fixedSize(horizontal: false, vertical: true)
            Text("The new version must be in the full-texts folder. Nothing there is changed: the current version stays where it is.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                GridRow {
                    Text("Current version").foregroundStyle(.secondary)
                    Label(file.path, systemImage: file.kind.symbol)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
                GridRow {
                    Text("New version").foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        if let path {
                            Label(path, systemImage: (FileKind.forPath(path) ?? file.kind).symbol)
                                .font(.callout.monospaced())
                                .textSelection(.enabled)
                        } else {
                            Text("None chosen yet").foregroundStyle(.tertiary)
                        }
                        Button(path == nil ? "Choose…" : "Change…") { choose() }
                            .controlSize(.small)
                    }
                }
            }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
    }

    func choose() {
        switch model.chooseNewVersion(for: fileKey) {
        case .cancelled:
            break
        case .chosen(let rel):
            path = rel
            plan = nil
            problem = nil
        case .problem(let message):
            problem = message
        }
    }

    func check() {
        guard let path else { return }
        do {
            let p = try model.planUpdate(file: fileKey, path: path)
            if p.samePath && p.sameContent {
                problem = "That is the version already catalogued for this file, so there is nothing to update. Choose the new version."
                return
            }
            plan = p
            problem = nil
            stage = .check
        } catch {
            problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: Step 2: check

    @ViewBuilder
    func checkStage(_ file: EmpiricalFile) -> some View {
        if let plan {
            VStack(alignment: .leading, spacing: 12) {
                if plan.checks.isEmpty {
                    Text("This file has no selections in any layer, so there is nothing to find again.")
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 18) {
                        tally(plan.unchanged, "Unchanged", symbol: "checkmark.circle.fill", color: .green)
                        tally(plan.moved, "Moved", symbol: "arrow.down.right.circle.fill", color: .blue)
                        tally(plan.unverified, "Unchecked", symbol: "questionmark.circle.fill", color: .secondary)
                        tally(plan.lost, "Not found", symbol: "exclamationmark.triangle.fill", color: .orange)
                    }
                    if plan.unverified > 0 {
                        Text(plan.hadOldText
                            ? "Unchecked selections have no text to look for; they keep their positions, which may now point at different text."
                            : "The version these selections were made on can't be read any more, so selections without a stored quote (irrelevant text always, and every selection when the project doesn't store quotes) can't be checked; they keep their positions, which may now point at different text.")
                            .font(.callout).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(sorted(plan.checks)) { c in
                            CheckRow(model: model, check: c, showLayer: model.project.layers.count > 1)
                        }
                        if !plan.speakers.isEmpty {
                            SectionHeader(title: "Speakers (Interlocutor layer)")
                                .padding(.top, 8)
                            ForEach(plan.speakers) { s in
                                HStack(spacing: 6) {
                                    Image(systemName: s.found ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                                        .foregroundStyle(s.found ? Color.green : Color.orange)
                                    Text(s.label)
                                    Text("→ " + (model.personName(s.person) ?? "someone")).foregroundStyle(.secondary)
                                    Spacer()
                                    if !s.found {
                                        Text("No header lines in the new version").font(.caption).foregroundStyle(.orange)
                                    }
                                }
                                .font(.callout)
                            }
                        }
                        Text("Codebooks, response sheets, the title, ID, date and status stay with the file whatever happens.")
                            .font(.caption).foregroundStyle(.secondary)
                            .padding(.top, 8)
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(20)
        }
    }

    func tally(_ n: Int, _ title: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol).foregroundStyle(n == 0 ? Color.secondary.opacity(0.5) : color)
            Text("\(n)").font(.title3.weight(.semibold)).monospacedDigit()
            Text(title).foregroundStyle(.secondary)
        }
    }

    /// Not found first, then unchecked, moved and unchanged; by position
    /// within each.
    func sorted(_ checks: [Anchoring.Check]) -> [Anchoring.Check] {
        func rank(_ f: Anchoring.Fate) -> Int {
            switch f {
            case .lost: return 0
            case .unverified: return 1
            case .moved: return 2
            case .unchanged: return 3
            }
        }
        var position: [String: TextSpan] = [:]
        for c in checks {
            if let first = model.project.selection(c.selection)?.first { position[c.selection] = first }
        }
        return checks.sorted { a, b in
            let ra = rank(a.fate), rb = rank(b.fate)
            if ra != rb { return ra < rb }
            if let pa = position[a.selection], let pb = position[b.selection], pa != pb { return pa < pb }
            return a.selection < b.selection
        }
    }

    // MARK: Step 3: confirm

    @ViewBuilder
    func confirmStage(_ file: EmpiricalFile) -> some View {
        if let plan {
            let what: String = plan.samePath
                ? "“\(file.displayTitle)” will use the new contents of \(plan.path)."
                : "“\(file.displayTitle)” will use \(plan.path) instead of \(file.path)."
            VStack(alignment: .leading, spacing: 16) {
                Text(what)
                    .fixedSize(horizontal: false, vertical: true)
                Text(summary(plan))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if plan.lost > 0 {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(plan.lost) selection\(plan.lost == 1 ? "" : "s") could not be found in the new version:")
                        Picker("Selections not found", selection: $deleteLost) {
                            Text("Keep \(plan.lost == 1 ? "it" : "them") where \(plan.lost == 1 ? "it was" : "they were"), flagged, to resize or delete later").tag(false)
                            Text("Delete \(plan.lost == 1 ? "it" : "them"), with \(plan.lost == 1 ? "its" : "their") evidence links and memos").tag(true)
                        }
                        .pickerStyle(.radioGroup)
                        .labelsHidden()
                    }
                }
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.title2)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Consider making a Git commit first").fontWeight(.semibold)
                        Text("If the workspace is in Git, commit it before going on. You can then inspect the diff of what this update changed, and restore the previous version straight away if it isn't right. Edit › Undo also reverses it while the project stays open.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.08)))
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    func summary(_ plan: FileUpdatePlan) -> String {
        guard !plan.checks.isEmpty else { return "The file has no selections to move." }
        var parts: [String] = []
        if plan.unchanged > 0 { parts.append("\(plan.unchanged) selection\(plan.unchanged == 1 ? " stays" : "s stay") as \(plan.unchanged == 1 ? "it is" : "they are")") }
        if plan.moved > 0 { parts.append("\(plan.moved) move\(plan.moved == 1 ? "s" : "") with the text") }
        if plan.unverified > 0 { parts.append("\(plan.unverified) keep\(plan.unverified == 1 ? "s its position" : " their positions"), unchecked") }
        if plan.lost > 0 { parts.append("\(plan.lost) can't be found") }
        return parts.joined(separator: "; ") + "."
    }
}

/// One selection in the wizard's check: what became of it, where (layer),
/// its text and its open codes.
struct CheckRow: View {
    let model: AppModel
    var check: Anchoring.Check
    var showLayer: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            icon
                .frame(width: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(fateText).font(.caption.weight(.semibold)).foregroundStyle(fateColor)
                    if showLayer, let layer = model.project.layer(check.layer) {
                        Text(layer.name).font(.caption).foregroundStyle(.secondary)
                    }
                    if check.irrelevant {
                        Text("Irrelevant").font(.caption).foregroundStyle(.tertiary)
                    }
                    ForEach(model.index.codesForSelection[check.selection] ?? [], id: \.self) { c in
                        WorkingBadge(text: model.wid(c), color: model.itemAccent(c))
                    }
                }
                if check.quote.isEmpty {
                    Text("No text to look for").font(.callout).italic().foregroundStyle(.tertiary)
                } else {
                    Text(check.quote)
                        .font(.system(.callout, design: .serif))
                        .foregroundStyle(check.irrelevant ? Color.secondary : Color.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.04)))
    }

    @ViewBuilder
    var icon: some View {
        switch check.fate {
        case .unchanged: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .moved: Image(systemName: "arrow.down.right.circle.fill").foregroundStyle(.blue)
        case .unverified: Image(systemName: "questionmark.circle.fill").foregroundStyle(.secondary)
        case .lost: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
    }

    var fateText: String {
        switch check.fate {
        case .unchanged: return "Unchanged"
        case .moved: return "Moved"
        case .unverified: return "Unchecked"
        case .lost: return "Not found"
        }
    }

    var fateColor: Color {
        switch check.fate {
        case .unchanged: return .green
        case .moved: return .blue
        case .unverified: return .secondary
        case .lost: return .orange
        }
    }
}

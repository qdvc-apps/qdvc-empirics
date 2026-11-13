import AppKit
import EmpiricsCore
import SwiftUI
import UniformTypeIdentifiers

// The coding operations behind the document view, the coding bar, the
// quick-code palette, the menus and the inspector.
extension AppModel {

    // MARK: Text selection from the document

    /// The document's text selection changed (spans of length > 0), or was
    /// cleared (empty).
    func documentSelectionChanged(file: String, spans: [TextSpan]) {
        textSelection = spans.filter { $0.length > 0 }
        textSelectionFile = textSelection.isEmpty ? nil : file
        if textSelection.isEmpty { paletteVisible = false }
    }

    /// A click (no text selected) at `offset` on `page`: focus the innermost
    /// selection of the active layer there, or none.
    func documentClicked(file: String, page: Int?, offset: Int) {
        let hit = (activeLayer?.selections[file] ?? [])
            .filter { $0.contains(page: page, offset: offset) }
            .min { $0.totalLength < $1.totalLength }
        focusedSelection = hit?.key
        if hit != nil {
            inspectorTab = .selection
        } else if inspectorTab == .selection {
            inspectorTab = .file
        }
    }

    /// The text currently selected in the document.
    var textSelectionQuote: String {
        guard let file = textSelectionFile, let pages = pages(file) else { return "" }
        return TextNormaliser.quote(textSelection, pages: pages)
    }

    var hasTextSelection: Bool { !textSelection.isEmpty && textSelectionFile != nil }

    /// What ⌘K and the quick codes act on: the text selection if there is
    /// one, otherwise the focused selection.
    var canCode: Bool { hasTextSelection || focusedSelection != nil }

    private func clearTextSelection() {
        textSelection = []
        textSelectionFile = nil
        clearTextSelectionRevision += 1
    }

    /// Makes (or finds) a selection from the document's text selection.
    private func selectionFromText(irrelevant: Bool, in p: inout Project) throws -> String {
        guard let file = textSelectionFile else { throw RuleError("Select some text first.") }
        let quote = irrelevant ? "" : textSelectionQuote
        return try p.addSelection(layer: activeLayerKey, file: file, spans: textSelection, quote: quote,
                                  irrelevant: irrelevant, by: currentResearcher ?? "")
    }

    /// Codes the text selection (or the focused selection) with a code.
    func applyCode(_ codeKey: String) {
        guard let code = project.code(codeKey) else { return }
        guard code.kind == .open else {
            showProblem(RuleError("Selections are evidence for open codes. \(code.name) is an axial code: add open codes to it from the Code inspector."))
            return
        }
        var target: String?
        let ok = perform("Apply Open Code “\(code.name)”") { p in
            let s: String
            if hasTextSelection {
                s = try selectionFromText(irrelevant: false, in: &p)
            } else if let f = focusedSelection {
                s = f
            } else {
                throw RuleError("Select some text first.")
            }
            if p.code(codeKey)?.hasEvidence(s) == true { target = s; return }
            try p.addEvidence(code: codeKey, target: s)
            target = s
        }
        guard ok, let target else { return }
        noteUsed(codeKey)
        focusedSelection = target
        inspectorTab = .selection
        paletteVisible = false
        if hasTextSelection { clearTextSelection() }
    }

    /// Creates an open code (or uses the one with that name) and applies it.
    func applyNewCode(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let existing = project.code(named: trimmed, inLayer: activeLayerKey), existing.kind == .open {
            applyCode(existing.key)
            return
        }
        var created: String?
        var target: String?
        let ok = perform("New Open Code “\(trimmed)”") { p in
            let s: String
            if hasTextSelection {
                s = try selectionFromText(irrelevant: false, in: &p)
            } else if let f = focusedSelection {
                s = f
            } else {
                throw RuleError("Select some text first.")
            }
            let c = try p.addCode(layer: activeLayerKey, kind: .open, name: trimmed, by: currentResearcher ?? "")
            try p.addEvidence(code: c, target: s)
            created = c
            target = s
        }
        guard ok, let created, let target else { return }
        noteUsed(created)
        focusedSelection = target
        inspectorTab = .selection
        paletteVisible = false
        if hasTextSelection { clearTextSelection() }
    }

    func applyQuickCode(_ slot: Int) {
        guard (1...9).contains(slot) else { return }
        let key = quickCodes[slot - 1]
        guard !key.isEmpty else {
            notice = Notice(text: "Quick code \(slot) isn't set yet. The first nine codes you use get 1–9; or right-click a code and choose Quick Code.")
            return
        }
        applyCode(key)
    }

    /// Makes a selection without a code (to come back to).
    func highlightOnly() {
        var made: String?
        let ok = perform("Highlight") { p in made = try selectionFromText(irrelevant: false, in: &p) }
        guard ok, let made else { return }
        focusedSelection = made
        inspectorTab = .selection
        clearTextSelection()
    }

    /// Marks the selected text (or the focused selection) irrelevant; on an
    /// irrelevant focused selection, unmarks it.
    func toggleIrrelevant() {
        if hasTextSelection {
            var made: String?
            let ok = perform("Mark Irrelevant") { p in made = try selectionFromText(irrelevant: true, in: &p) }
            if ok {
                focusedSelection = made
                clearTextSelection()
            }
        } else if let key = focusedSelection, let s = project.selection(key) {
            perform(s.irrelevant ? "Mark Relevant" : "Mark Irrelevant") { p in try p.setIrrelevant(key, !s.irrelevant) }
        }
    }

    func deleteSelection(_ key: String) {
        perform("Delete Selection") { p in p.deleteSelection(key) }
        if focusedSelection == key { focusedSelection = nil }
        lostSelections.remove(key)
    }

    func deleteFocusedSelection() {
        guard let key = focusedSelection else { return }
        deleteSelection(key)
    }

    func removeCode(_ code: String, from selection: String) {
        let name = project.code(code)?.name ?? "Code"
        perform("Remove \(name)") { p in p.removeEvidence(code: code, target: selection) }
    }

    /// Gives the focused selection the text now selected in the document.
    func resizeFocusedToTextSelection() {
        guard let key = focusedSelection, hasTextSelection else { return }
        let quote = textSelectionQuote
        let spans = textSelection
        if perform("Change Selection", { p in try p.resizeSelection(key, spans: spans, quote: quote) }) {
            lostSelections.remove(key)
            clearTextSelection()
        }
    }

    func setMemo(code: String, target: String, _ memo: String) {
        edit { $0.setMemo(code: code, target: target, memo: memo) }
    }

    /// Previous or next selection of the active layer in the open file.
    func stepSelection(_ step: Int) {
        guard let file = openFileKey else { return }
        let list = activeLayer?.selections[file] ?? []
        guard !list.isEmpty else { return }
        let current = focusedSelection.flatMap { k in list.firstIndex { $0.key == k } }
        let next: Int
        if let current {
            next = (current + step + list.count) % list.count
        } else {
            next = step > 0 ? 0 : list.count - 1
        }
        showSelection(list[next].key)
    }

    // MARK: Codes

    @discardableResult
    func newCode(kind: CodeKind, name: String, parent: String? = nil, child: String? = nil) -> String? {
        // The layer of the code it joins, or on the code pages the inductive
        // layer they show, or the active layer.
        let onCodePages = sidebar == .openCodes || sidebar == .axialCodes
        let layer = parent.flatMap { index.layerOf[$0] } ?? child.flatMap { index.layerOf[$0] }
            ?? (onCodePages ? inductiveLayer?.key : nil) ?? activeLayerKey
        if let existing = project.code(named: name, inLayer: layer) {
            showProblem(RuleError("This layer already has \(existing.kind == .open ? "an open" : "an axial") code called “\(existing.name)”."))
            return nil
        }
        var made: String?
        perform(kind == .open ? "New Open Code" : "New Axial Code") { p in
            let c = try p.addCode(layer: layer, kind: kind, name: name, by: currentResearcher ?? "")
            if let parent { try p.addEvidence(code: parent, target: c) }
            if let child { try p.addEvidence(code: c, target: child) }
            made = c
        }
        if let made {
            if sidebar == .openCodes || sidebar == .axialCodes {
                sidebar = kind == .open ? .openCodes : .axialCodes
                tableSelection = made
            } else if case .code = sidebar {
                notice = Notice(text: "Created “\(name)”.", action: NoticeAction(title: "Open") { [weak self] in self?.openKey(made) })
            } else {
                show(.code(made))
            }
        }
        return made
    }

    /// Edits a code in place (typing: saved, not on Edit › Undo).
    func editCode(_ key: String, _ change: (inout QDACode) -> Void) {
        edit { p in
            guard var c = p.code(key) else { return }
            change(&c)
            p.updateCode(c)
        }
    }

    func editFile(_ key: String, _ change: (inout EmpiricalFile) -> Void) {
        edit { p in
            guard var f = p.files[key] else { return }
            change(&f)
            p.files[key] = f
        }
    }

    func updateCode(_ code: QDACode) {
        edit { $0.updateCode(code) }
    }

    func deleteCode(_ key: String) {
        guard let code = project.code(key) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete the \(code.kind == .open ? "open" : "axial") code “\(code.name)”?"
        alert.informativeText = code.evidence.isEmpty
            ? "It will be removed from any axial codes it is evidence for."
            : "Its \(code.evidence.count) evidence link\(code.evidence.count == 1 ? "" : "s") and memos go with it; the selections, open codes and axial codes themselves stay. You can undo this."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform(code.kind == .open ? "Delete Open Code" : "Delete Axial Code") { p in p.deleteCode(key) }
        if let i = quickCodes.firstIndex(of: key) { assignQuickCode(nil, slot: i + 1) }
    }

    func addEvidence(code: String, target: String) {
        perform("Add Evidence") { p in try p.addEvidence(code: code, target: target) }
    }

    // MARK: Layers

    func moveToLayer(_ item: String, layer: String) {
        let name = project.layer(layer)?.name ?? "layer"
        var moved = LayerComponent()
        let ok = perform("Move to \(name)") { p in moved = try p.move(item, toLayer: layer) }
        guard ok else { return }
        notice = Notice(text: "Moved \(moved.selections.count) selection\(moved.selections.count == 1 ? "" : "s"), \(codeCounts(Array(moved.codes))) to \(name).",
                        action: NoticeAction(title: "Switch to \(name)") { [weak self] in self?.setActiveLayer(layer) })
        focusedSelection = nil
    }

    func addLayer(named name: String, kind: LayerKind) {
        var key: String?
        perform("New Layer") { p in key = p.addLayer(name: name, kind: kind, researcher: currentResearcher ?? "") }
        if let key { setActiveLayer(key) }
    }

    func deleteLayer(_ key: String) {
        guard let layer = project.layer(key) else { return }
        let alert = NSAlert()
        alert.messageText = "Delete the layer “\(layer.name)”?"
        alert.informativeText = "Its \(layer.selectionCount) selection\(layer.selectionCount == 1 ? "" : "s"), \(codeCounts(Array(layer.codes.keys))) are deleted with it. You can undo this while the project is open."
        alert.addButton(withTitle: "Delete Layer")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform("Delete Layer") { p in try p.deleteLayer(key) }
    }

    // MARK: Files

    /// Asks for files in the full-texts folder to add to the catalogue.
    func addFilesPanel() {
        guard let ft = fullTexts else {
            chooseFullTextsFolder()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.directoryURL = ft.root
        var types: [UTType] = [.plainText, .pdf]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
        panel.allowedContentTypes = types
        panel.prompt = "Add"
        panel.message = "Choose plain-text, Markdown or PDF files inside the full-texts folder. They are only ever read, never changed."
        guard panel.runModal() == .OK else { return }
        var outside: [String] = []
        var paths: [String] = []
        for url in panel.urls {
            guard let rel = ft.relativePath(of: url) else {
                outside.append(url.lastPathComponent)
                continue
            }
            guard FileKind.forPath(rel) != nil else { continue }
            if project.file(path: rel) == nil { paths.append(rel) }
        }
        addFiles(paths)
        if !outside.isEmpty {
            errorMessage = "These files aren't in the full-texts folder, so they weren't added: \(outside.joined(separator: ", ")).\n\nQDVC Empirics never copies or writes into the full-texts folder; move them there yourself, then add them."
        }
    }

    /// Lists files in the full-texts folder that aren't catalogued yet.
    func scanForNewFiles() {
        guard let ft = fullTexts else {
            chooseFullTextsFolder()
            return
        }
        let known = Set(project.files.values.map(\.path))
        let consent = Set(project.interviewees.map(\.consentForm).filter { !$0.isEmpty })
        let found = ft.uncatalogued(known: known, excluding: consent)
        if found.isEmpty {
            notice = Notice(text: "Every supported file in the full-texts folder is already in the project.")
        } else {
            sheet = .addFiles(found)
        }
    }

    func addFiles(_ paths: [String]) {
        guard let ft = fullTexts, !paths.isEmpty else { return }
        var added: [String] = []
        perform(paths.count == 1 ? "Add File" : "Add Files") { p in
            for path in paths where p.file(path: path) == nil {
                guard let kind = FileKind.forPath(path) else { continue }
                let fp = (try? ft.fingerprint(path)) ?? ""
                added.append(p.addFile(path: path, kind: kind, fingerprint: fp))
            }
        }
        if let first = added.first {
            if sidebar != .files { sidebar = .files }
            tableSelection = first
        }
    }

    func removeFile(_ key: String) {
        guard let file = project.files[key] else { return }
        let count = index.selectionCount[key] ?? 0
        let alert = NSAlert()
        alert.messageText = "Remove “\(file.displayTitle)” from the project?"
        alert.informativeText = "Its catalogue entry\(count > 0 ? ", its \(count) selection\(count == 1 ? "" : "s") in every layer" : ""), speakers and response sheets are removed from the workspace. The file itself stays in the full-texts folder, untouched. You can undo this."
        alert.addButton(withTitle: "Remove")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform("Remove File") { p in p.removeFile(key) }
        documents.forget(key)
    }

    func setStatus(_ status: CodingStatus, file: String) {
        perform("Set Status") { p in p.files[file]?.status = status }
    }

    /// The next file not yet coded, after the open one.
    func nextUncodedFile() {
        let files = visibleFiles
        let start = openFileKey.flatMap { k in files.firstIndex { $0.key == k } } ?? -1
        let rotated = Array(files.dropFirst(start + 1)) + Array(files.prefix(start + 1))
        if let next = rotated.first(where: { $0.status != .coded && $0.key != openFileKey }) {
            moveOn(to: next.key)
        } else {
            notice = Notice(text: "Every file is marked Coded.")
        }
    }

    // MARK: Consent forms

    func chooseConsentForm(for interviewee: String) {
        guard let ft = fullTexts else {
            chooseFullTextsFolder()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf]
        panel.directoryURL = ft.root
        panel.prompt = "Choose"
        panel.message = "Choose the signed consent form (a PDF inside the full-texts folder). It stays there; only its location is recorded."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let rel = ft.relativePath(of: url) else {
            errorMessage = "Consent forms must be inside the full-texts folder (never in the workspace). Move it there first."
            return
        }
        perform("Set Consent Form") { p in
            if let i = p.interviewees.firstIndex(where: { $0.key == interviewee }) { p.interviewees[i].consentForm = rel }
        }
    }
}

import AppKit
import EmpiricsCore
import SwiftUI

/// A code as the coding UI shows it: an open code (inductive layers) or an
/// a priori code (deductive layers). The coding bar, palette, stripes and
/// inspector work with these, so they follow the active layer's kind.
struct CodingTag: Identifiable, Equatable {
    var key: String
    var name: String
    /// An open code's description, an a priori code's definition.
    var detail: String
    var nsColor: NSColor
    var isApriori: Bool

    var id: String { key }
    var color: Color { Color(nsColor: nsColor) }
}

extension QDACode {
    var tag: CodingTag { CodingTag(key: key, name: name, detail: description, nsColor: nsColor, isApriori: false) }
}

extension AprioriCode {
    var tag: CodingTag { CodingTag(key: key, name: name, detail: definition, nsColor: nsColor, isApriori: true) }
}

extension NSColor {
    /// Protocol segments (structural, like speaker turns): one colour for all.
    static var protocolSegment: NSColor { .systemIndigo }
}

// Deductive coding: a priori codes and protocol segments on deductive
// layers, and the helpers that let the coding UI follow the layer's kind.
extension AppModel {

    // MARK: Layer kind

    var activeIsDeductive: Bool { activeLayer?.isDeductive == true }

    /// What the active layer applies, in a sentence: "open code" or "a
    /// priori code".
    var codeNoun: String { activeIsDeductive ? "a priori code" : "open code" }

    /// The same, as a title: "Open Code" or "A Priori Code".
    var codeNounTitle: String { activeIsDeductive ? "A Priori Code" : "Open Code" }

    /// "an open code" or "an a priori code".
    var aCodeNoun: String { "an " + codeNoun }

    // MARK: Tags

    /// An open, axial or a priori code as a tag.
    func tag(_ key: String) -> CodingTag? {
        project.code(key)?.tag ?? project.aprioriCodes[key]?.tag
    }

    /// The codes a selection is evidence for, by name: a priori codes in a
    /// deductive layer, open codes in an inductive one.
    func tags(of selection: String, in layer: CodingLayer) -> [CodingTag] {
        let list: [CodingTag]
        if layer.isDeductive {
            list = (index.aprioriForSelection[selection] ?? []).compactMap { project.aprioriCodes[$0]?.tag }
        } else {
            list = (index.codesForSelection[selection] ?? []).compactMap { layer.codes[$0]?.tag }
        }
        return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func tags(of selection: String) -> [CodingTag] {
        guard let layer = index.layerOf[selection].flatMap({ project.layer($0) }) else { return [] }
        return tags(of: selection, in: layer)
    }

    /// The codes the active layer applies: every a priori code on a
    /// deductive layer, the layer's open codes on an inductive one.
    var activeTags: [CodingTag] {
        guard let layer = activeLayer else { return [] }
        if layer.isDeductive { return project.aprioriCodes.values.map(\.tag) }
        return layer.codes.values.filter { $0.kind == .open }.map(\.tag)
    }

    /// A selection's colour: its first code's (by name), protocol colour for
    /// a segment, or grey.
    func selectionColour(_ s: CodeSelection, in layer: CodingLayer) -> NSColor {
        if s.segment != nil { return .protocolSegment }
        let keys = layer.isDeductive ? index.aprioriForSelection[s.key] ?? [] : index.codesForSelection[s.key] ?? []
        let names: [(String, NSColor)] = layer.isDeductive
            ? keys.compactMap { k in project.aprioriCodes[k].map { ($0.name, $0.nsColor) } }
            : keys.compactMap { k in layer.codes[k].map { ($0.name, $0.nsColor) } }
        return names.min { $0.0.localizedCompare($1.0) == .orderedAscending }?.1 ?? .systemGray
    }

    /// Opens an open, axial or a priori code's page.
    func showTag(_ key: String) {
        if project.code(key) != nil {
            showCode(key)
        } else if project.aprioriCodes[key] != nil {
            show(.aprioriCode(key))
        }
    }

    /// The memo on a piece of evidence: why the selection is evidence for
    /// the code (open or a priori).
    func evidenceMemo(code: String, selection: String) -> String {
        if project.aprioriCodes[code] != nil {
            let layer = index.layerOf[selection].flatMap { project.layer($0) }
            return layer?.aprioriEvidence[code]?.first { $0.target == selection }?.memo ?? ""
        }
        return project.code(code)?.memo(for: selection) ?? ""
    }

    func setEvidenceMemo(code: String, selection: String, _ memo: String) {
        if project.aprioriCodes[code] != nil {
            edit { $0.setAprioriMemo(code: code, selection: selection, memo: memo) }
        } else {
            setMemo(code: code, target: selection, memo)
        }
    }

    /// Takes a code (open or a priori) off a selection.
    func removeTag(_ code: String, from selection: String) {
        if let apc = project.aprioriCodes[code] {
            perform("Remove \(apc.name)") { p in p.removeAprioriEvidence(code: code, selection: selection) }
        } else {
            removeCode(code, from: selection)
        }
    }

    // MARK: A priori coding

    /// Codes the text selection (or the focused selection) with an a priori
    /// code, on the active (deductive) layer.
    func applyApriori(_ key: String) {
        guard let apc = project.aprioriCodes[key] else { return }
        guard let layer = activeLayer, layer.isDeductive else {
            showProblem(RuleError("\(apc.name) is an a priori code, and \(activeLayer?.name ?? "this layer") is an inductive layer: switch to a deductive layer to apply it."))
            return
        }
        var target: String?
        let ok = perform("Apply A Priori Code “\(apc.name)”") { p in
            let s: String
            if hasTextSelection {
                s = try selectionFromText(irrelevant: false, in: &p)
            } else if let f = focusedSelection {
                s = f
            } else {
                throw RuleError("Select some text first.")
            }
            target = s
            if p.layer(layer.key)?.aprioriEvidence[key]?.contains(where: { $0.target == s }) == true { return }
            try p.addAprioriEvidence(code: key, selection: s)
        }
        guard ok, let target else { return }
        noteUsed(key)
        focusedSelection = target
        inspectorTab = .selection
        paletteVisible = false
        if hasTextSelection { clearTextSelection() }
    }

    /// Creates an a priori code (or uses the one with that name) and applies
    /// it. A priori codes are project-wide: it joins the A Priori Codes page.
    func applyNewApriori(named name: String) {
        if let existing = project.aprioriCode(named: name) {
            applyApriori(existing.key)
            return
        }
        var created: String?
        var target: String?
        let ok = perform("New A Priori Code “\(name)”") { p in
            let s: String
            if hasTextSelection {
                s = try selectionFromText(irrelevant: false, in: &p)
            } else if let f = focusedSelection {
                s = f
            } else {
                throw RuleError("Select some text first.")
            }
            let c = try p.addAprioriCode(name: name, by: currentResearcher ?? "")
            try p.addAprioriEvidence(code: c, selection: s)
            created = c
            target = s
        }
        guard ok, let created, let target else { return }
        noteUsed(created)
        focusedSelection = target
        inspectorTab = .selection
        paletteVisible = false
        if hasTextSelection { clearTextSelection() }
        notice = Notice(text: "Created the a priori code “\(name)”. Add its definition on its page.",
                        action: NoticeAction(title: "Open") { [weak self] in self?.show(.aprioriCode(created)) })
    }

    // MARK: Protocol segments

    /// The protocol a file follows in the active layer, if set.
    func protocolKey(forFile file: String) -> String? {
        activeLayer?.protocols[file]
    }

    /// The protocols whose items can mark text in a file on the active
    /// layer: the file's protocol, or every protocol while it has none.
    func segmentProtocols(file: String) -> [StudyProtocol] {
        guard activeIsDeductive else { return [] }
        if let k = protocolKey(forFile: file), let pr = project.protocols[k] { return [pr] }
        return project.sortedProtocols
    }

    /// "2 Long sessions": a protocol item's number and label.
    func protocolItemTitle(_ item: String) -> String {
        guard let (_, i) = project.protocolItem(item) else { return "Deleted item" }
        let n = project.protocolItemNumber(item).map { "\($0) " } ?? ""
        return n + (i.label.isEmpty ? "Untitled" : i.label)
    }

    /// "2 Long sessions · Prompt".
    func segmentTitle(_ segment: ProtocolSegment) -> String {
        protocolItemTitle(segment.item) + " · " + segment.part.label
    }

    /// Q and A in the document: the protocol palette, to mark the text as a
    /// prompt or a response. Returns false if it can't open here.
    @discardableResult
    func openProtocolPalette(_ part: ProtocolPart) -> Bool {
        guard canCode, let layer = activeLayer else { return false }
        guard layer.isDeductive else {
            notice = Notice(text: "Protocol segments are marked on deductive layers. Switch layer in the toolbar.")
            return true
        }
        let file = textSelectionFile ?? focusedSelection.flatMap { index.fileOf[$0] } ?? openFileKey ?? ""
        guard !segmentProtocols(file: file).isEmpty else {
            notice = Notice(text: "There are no protocols yet. Make one on the Protocols page.",
                            action: NoticeAction(title: "Protocols") { [weak self] in self?.sidebar = .protocols })
            return true
        }
        paletteVisible = false
        protocolPalette = part
        return true
    }

    /// Marks the text selection as a protocol segment, or makes the focused
    /// selection one (or changes its item or part).
    func markSegment(item: String, part: ProtocolPart) {
        let segment = ProtocolSegment(item: item, part: part)
        var target: String?
        let ok = perform("Mark \(part.label)") { p in
            if hasTextSelection {
                target = try selectionFromText(irrelevant: false, segment: segment, in: &p)
            } else if let f = focusedSelection {
                try p.setSegment(f, segment)
                target = f
            } else {
                throw RuleError("Select some text first.")
            }
        }
        protocolPalette = nil
        guard ok, let target else { return }
        focusedSelection = target
        inspectorTab = .selection
        if hasTextSelection { clearTextSelection() }
        focusDocument()
    }

    /// Makes a protocol segment a plain selection again.
    func clearSegment(_ selection: String) {
        perform("Unmark Protocol Segment") { p in try p.setSegment(selection, nil) }
    }

    /// Sets the protocol a file follows in a deductive layer.
    func setFileProtocol(_ protocolKey: String?, layer: String, file: String) {
        perform(protocolKey == nil ? "Clear Protocol" : "Set Protocol") { p in
            try p.setProtocol(protocolKey, layer: layer, file: file)
        }
    }

    /// Context-menu items for the document (text and PDF views alike).
    func documentMenuItems() -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        let noun = codeNounTitle
        if hasTextSelection {
            items.append(ClosureMenuItem(title: "Apply \(noun)…") { [weak self] in self?.paletteVisible = true })
            if activeIsDeductive {
                items.append(ClosureMenuItem(title: "Mark as Protocol Prompt…") { [weak self] in _ = self?.openProtocolPalette(.prompt) })
                items.append(ClosureMenuItem(title: "Mark as Protocol Response…") { [weak self] in _ = self?.openProtocolPalette(.response) })
            }
            items.append(ClosureMenuItem(title: "Highlight Without \(noun)") { [weak self] in self?.highlightOnly() })
            items.append(ClosureMenuItem(title: "Mark as Irrelevant") { [weak self] in self?.toggleIrrelevant() })
        } else if let key = focusedSelection, let s = project.selection(key) {
            if s.segment != nil {
                items.append(ClosureMenuItem(title: "Change Protocol Item…") { [weak self] in
                    _ = self?.openProtocolPalette(s.segment?.part ?? .response)
                })
                items.append(ClosureMenuItem(title: "Unmark Protocol Segment") { [weak self] in self?.clearSegment(key) })
            } else if !s.irrelevant {
                items.append(ClosureMenuItem(title: "Add \(noun)…") { [weak self] in self?.paletteVisible = true })
            }
            items.append(ClosureMenuItem(title: "Delete Selection") { [weak self] in self?.deleteSelection(key) })
        }
        return items
    }

    /// Single keys shared by the text and PDF views: Q and A (protocol
    /// prompt and response, on deductive layers). Returns true if handled.
    func handleProtocolKey(_ key: String) -> Bool {
        switch key {
        case "q": return openProtocolPalette(.prompt)
        case "a": return openProtocolPalette(.response)
        default: return false
        }
    }

    // MARK: Protocols and a priori codes (pages)

    func newProtocol() {
        var key = ""
        perform("New Protocol") { p in key = p.addProtocol(title: "New Protocol") }
        guard !key.isEmpty else { return }
        show(.studyProtocol(key))
    }

    func addProtocolItem(to protocolKey: String) {
        perform("Add Protocol Item") { p in _ = p.addProtocolItem(to: protocolKey, label: "") }
    }

    /// Changes a protocol (title, description, items' wording and order) in
    /// place: typing is saved, not put on Edit › Undo.
    func editProtocol(_ key: String, _ change: (inout StudyProtocol) -> Void) {
        edit { p in
            guard var pr = p.protocols[key] else { return }
            change(&pr)
            try? p.updateProtocol(pr)
        }
    }

    /// Segments of a protocol item, all layers.
    func segmentCount(item: String) -> Int {
        project.layers.reduce(0) { n, l in n + l.allSelections.filter { $0.segment?.item == item }.count }
    }

    /// Files following a protocol, with the layers they follow it in.
    func filesFollowing(_ protocolKey: String) -> [(file: EmpiricalFile, layers: [CodingLayer])] {
        project.sortedFiles.compactMap { f -> (file: EmpiricalFile, layers: [CodingLayer])? in
            let layers = project.deductiveLayers.filter { $0.protocols[f.key] == protocolKey }
            return layers.isEmpty ? nil : (file: f, layers: layers)
        }
    }

    func deleteProtocolItem(_ item: String) {
        let count = segmentCount(item: item)
        if count > 0 {
            let alert = NSAlert()
            alert.messageText = "Delete the protocol item “\(protocolItemTitle(item))”?"
            alert.informativeText = "Its \(count) segment\(count == 1 ? "" : "s") in the files are deleted too, with its Framework Matrix column. You can undo this."
            alert.addButton(withTitle: "Delete")
            alert.addButton(withTitle: "Cancel")
            alert.buttons.first?.hasDestructiveAction = true
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        perform("Delete Protocol Item") { p in p.deleteProtocolItem(item) }
    }

    func deleteProtocol(_ key: String) {
        guard let pr = project.protocols[key] else { return }
        let segments = pr.items.reduce(0) { $0 + segmentCount(item: $1.key) }
        let files = filesFollowing(key).count
        let alert = NSAlert()
        alert.messageText = "Delete the protocol “\(pr.title)”?"
        alert.informativeText = segments == 0 && files == 0
            ? "No file follows it yet. You can undo this."
            : "\(files) file\(files == 1 ? "" : "s") follow\(files == 1 ? "s" : "") it; its \(segments) segment\(segments == 1 ? "" : "s") are deleted too. You can undo this."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform("Delete Protocol") { p in p.deleteProtocol(key) }
    }

    func newAprioriCode() {
        var key = ""
        perform("New A Priori Code") { p in
            var name = "New A Priori Code"
            var n = 2
            while p.aprioriCode(named: name) != nil {
                name = "New A Priori Code \(n)"
                n += 1
            }
            key = try p.addAprioriCode(name: name, by: currentResearcher ?? "")
        }
        guard !key.isEmpty else { return }
        show(.aprioriCode(key))
    }

    /// Changes an a priori code's codebook entry in place (typing: saved,
    /// not on Edit › Undo). An empty name is kept until it is filled in.
    func editAprioriCode(_ key: String, _ change: (inout AprioriCode) -> Void) {
        edit { p in
            guard var c = p.aprioriCodes[key] else { return }
            change(&c)
            p.aprioriCodes[key] = c
        }
    }

    /// Open and axial codes (any layer) linked to an a priori code, with
    /// their links.
    func links(to apc: String) -> [(code: QDACode, link: CodeLink)] {
        project.layers.flatMap { l -> [(code: QDACode, link: CodeLink)] in
            l.codes.values.flatMap { c -> [(code: QDACode, link: CodeLink)] in
                c.links.filter { $0.aprioriCode == apc }.map { (code: c, link: $0) }
            }
        }
        .sorted { $0.code.name.localizedStandardCompare($1.code.name) == .orderedAscending }
    }

    func deleteAprioriCode(_ key: String) {
        guard let apc = project.aprioriCodes[key] else { return }
        let evidence = index.aprioriEvidenceCount[key] ?? 0
        let linkCount = links(to: key).count
        let alert = NSAlert()
        alert.messageText = "Delete the a priori code “\(apc.name)”?"
        alert.informativeText = evidence == 0 && linkCount == 0
            ? "It isn't applied anywhere yet. You can undo this."
            : "Its \(evidence) piece\(evidence == 1 ? "" : "s") of evidence (the selections stay) and \(linkCount) link\(linkCount == 1 ? "" : "s") from open and axial codes go with it. You can undo this."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform("Delete A Priori Code") { p in p.deleteAprioriCode(key) }
        if let i = quickCodes.firstIndex(of: key) { assignQuickCode(nil, slot: i + 1) }
    }
}

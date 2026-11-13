import Foundation

// Changes to what is defined beforehand and applied on deductive layers:
// protocols and their segments, a priori codes and their evidence, links
// from open and axial codes to a priori codes, and Framework Matrix
// summaries. The rules are listed at the top of Editing.swift.
extension Project {

    // MARK: Protocols

    @discardableResult
    public mutating func addProtocol(title: String) -> String {
        let key = newKey(Keys.studyProtocol)
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        protocols[key] = StudyProtocol(key: key, title: t.isEmpty ? "New Protocol" : t)
        return key
    }

    /// Changes a protocol's title, description and the wording or order of
    /// its items. Items are added and deleted with `addProtocolItem` and
    /// `deleteProtocolItem`, so their segments follow; an update that drops
    /// or adds items is refused.
    public mutating func updateProtocol(_ pr: StudyProtocol) throws {
        guard let old = protocols[pr.key] else { return }
        guard Set(old.items.map(\.key)) == Set(pr.items.map(\.key)) else {
            throw RuleError("Add and delete protocol items one at a time.")
        }
        protocols[pr.key] = pr
    }

    @discardableResult
    public mutating func addProtocolItem(to protocolKey: String, label: String, text: String = "") -> String? {
        guard protocols[protocolKey] != nil else { return nil }
        let key = newKey(Keys.protocolItem)
        let l = label.trimmingCharacters(in: .whitespacesAndNewlines)
        protocols[protocolKey]!.items.append(
            ProtocolItem(key: key, label: l.isEmpty ? "Item \(protocols[protocolKey]!.items.count + 1)" : l, text: text))
        return key
    }

    /// Deletes a protocol item, its segments in every layer and its Framework
    /// Matrix column.
    public mutating func deleteProtocolItem(_ item: String) {
        guard let (pk, _) = protocolItem(item) else { return }
        protocols[pk]!.items.removeAll { $0.key == item }
        for li in layers.indices {
            let segments = layers[li].allSelections.filter { $0.segment?.item == item }.map(\.key)
            for k in segments { deleteSelection(k) }
        }
        dropFrameworkColumns([item])
    }

    /// Deletes a protocol: its segments in every layer, the files' choice of
    /// it, and its items' Framework Matrix columns.
    public mutating func deleteProtocol(_ key: String) {
        guard let pr = protocols[key] else { return }
        let items = Set(pr.items.map(\.key))
        for li in layers.indices {
            let segments = layers[li].allSelections.filter { s in s.segment.map { items.contains($0.item) } ?? false }
            for s in segments { deleteSelection(s.key) }
            for (file, p) in layers[li].protocols where p == key { layers[li].protocols[file] = nil }
        }
        dropFrameworkColumns(items)
        protocols[key] = nil
    }

    /// Sets (or clears, with nil) the protocol a file follows in a deductive
    /// layer. Refused while the file has segments of another protocol there.
    public mutating func setProtocol(_ protocolKey: String?, layer: String, file: String) throws {
        guard let li = layerIndex(layer) else { throw RuleError("That layer no longer exists.") }
        guard layers[li].isDeductive else {
            throw RuleError("\(layers[li].name) is an inductive layer: protocols belong to deductive layers.")
        }
        if let protocolKey, protocols[protocolKey] == nil { throw RuleError("That protocol no longer exists.") }
        guard layers[li].protocols[file] != protocolKey else { return }
        let segments = (layers[li].selections[file] ?? []).filter { $0.segment != nil }
        if !segments.isEmpty {
            throw RuleError("This file has \(segments.count) protocol segment\(segments.count == 1 ? "" : "s") in \(layers[li].name). Remove \(segments.count == 1 ? "it" : "them") before changing its protocol.")
        }
        layers[li].protocols[file] = protocolKey
    }

    /// Why `segment` can't be made in the file on the layer, thrown.
    func checkSegment(_ segment: ProtocolSegment, layerAt li: Int, file: String) throws {
        guard layers[li].isDeductive else {
            throw RuleError("\(layers[li].name) is an inductive layer: protocol segments belong to deductive layers.")
        }
        guard let (pk, _) = protocolItem(segment.item) else { throw RuleError("That protocol item no longer exists.") }
        if let current = layers[li].protocols[file], current != pk {
            let title = protocols[current]?.title ?? "another protocol"
            throw RuleError("In \(layers[li].name) this file follows \(title); a file follows one protocol per layer.")
        }
    }

    /// Makes a selection a protocol segment, changes which item or part it
    /// is, or (with nil) makes it a plain selection again.
    public mutating func setSegment(_ selection: String, _ segment: ProtocolSegment?) throws {
        guard let (li, file, si) = locateSelection(selection) else { return }
        let s = layers[li].selections[file]![si]
        if let segment {
            if s.irrelevant { throw RuleError("Irrelevant text can't be a protocol segment.") }
            if !layers[li].aprioriCodes(for: selection).isEmpty {
                throw RuleError("This selection is evidence for a priori codes, so it can't be a protocol segment. Make a separate selection.")
            }
            try checkSegment(segment, layerAt: li, file: file)
            if layers[li].protocols[file] == nil { layers[li].protocols[file] = protocolItem(segment.item)?.protocolKey }
        }
        layers[li].selections[file]![si].segment = segment
    }

    // MARK: A priori codes

    @discardableResult
    public mutating func addAprioriCode(name: String, by: String = "") throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RuleError("A code needs a name.") }
        let key = newKey(Keys.aprioriCode)
        let colour = CodePalette.next(used: aprioriCodes.values.map(\.colour))
        aprioriCodes[key] = AprioriCode(key: key, name: trimmed, colour: colour, by: by, created: Stamp.now())
        return key
    }

    /// An a priori code with this name (ignoring case), if any.
    public func aprioriCode(named name: String) -> AprioriCode? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return aprioriCodes.values.first { $0.name.compare(n, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    public mutating func updateAprioriCode(_ code: AprioriCode) throws {
        guard aprioriCodes[code.key] != nil else { return }
        guard !code.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RuleError("A code needs a name.")
        }
        aprioriCodes[code.key] = code
    }

    /// Deletes an a priori code, its evidence lists in every layer (the
    /// selections stay), the links to it and its Framework Matrix column.
    public mutating func deleteAprioriCode(_ key: String) {
        aprioriCodes[key] = nil
        for li in layers.indices {
            layers[li].aprioriEvidence[key] = nil
            for ck in layers[li].codes.keys where layers[li].codes[ck]!.links.contains(where: { $0.aprioriCode == key }) {
                layers[li].codes[ck]!.links.removeAll { $0.aprioriCode == key }
            }
        }
        dropFrameworkColumns([key])
    }

    /// An a priori code's evidence in every layer (layer key and evidence),
    /// in layer order.
    public func aprioriEvidence(of code: String) -> [(layer: String, evidence: Evidence)] {
        layers.flatMap { l in (l.aprioriEvidence[code] ?? []).map { (layer: l.key, evidence: $0) } }
    }

    /// A protocol item's number in its protocol (from 1).
    public func protocolItemNumber(_ item: String) -> Int? {
        guard let (pk, _) = protocolItem(item) else { return nil }
        return protocols[pk]?.items.firstIndex { $0.key == item }.map { $0 + 1 }
    }

    /// Why a selection can't be evidence for an a priori code, or nil if it
    /// can.
    public func aprioriEvidenceProblem(code: String, selection: String) -> String? {
        guard let apc = aprioriCodes[code] else { return "That code no longer exists." }
        guard let (li, file, si) = locateSelection(selection) else { return "That selection no longer exists." }
        let layer = layers[li]
        let s = layer.selections[file]![si]
        if !layer.isDeductive { return "A priori codes are applied on deductive layers." }
        if s.irrelevant { return "Irrelevant text can't be evidence." }
        if s.segment != nil { return "This selection is a protocol segment; make a separate selection for \(apc.name)." }
        if layer.aprioriEvidence[code]?.contains(where: { $0.target == selection }) == true {
            return "That is already evidence for \(apc.name)."
        }
        return nil
    }

    /// Adds a selection (on a deductive layer) as evidence for an a priori
    /// code, in the selection's layer.
    public mutating func addAprioriEvidence(code: String, selection: String, memo: String = "") throws {
        if let problem = aprioriEvidenceProblem(code: code, selection: selection) { throw RuleError(problem) }
        guard let (li, _, _) = locateSelection(selection) else { return }
        layers[li].aprioriEvidence[code, default: []].append(Evidence(target: selection, memo: memo))
    }

    public mutating func removeAprioriEvidence(code: String, selection: String) {
        guard let (li, _, _) = locateSelection(selection), layers[li].aprioriEvidence[code] != nil else { return }
        layers[li].aprioriEvidence[code]!.removeAll { $0.target == selection }
        if layers[li].aprioriEvidence[code]!.isEmpty { layers[li].aprioriEvidence[code] = nil }
    }

    public mutating func setAprioriMemo(code: String, selection: String, memo: String) {
        guard let (li, _, _) = locateSelection(selection),
              let ei = layers[li].aprioriEvidence[code]?.firstIndex(where: { $0.target == selection }) else { return }
        layers[li].aprioriEvidence[code]![ei].memo = memo
    }

    // MARK: Links to a priori codes

    @discardableResult
    public mutating func addLink(from codeKey: String, to aprioriKey: String, type: LinkType, memo: String = "") throws -> String {
        guard var c = code(codeKey) else { throw RuleError("That code no longer exists.") }
        guard let apc = aprioriCodes[aprioriKey] else { throw RuleError("That a priori code no longer exists.") }
        if c.links.contains(where: { $0.aprioriCode == aprioriKey }) {
            throw RuleError("\(c.name) is already linked to \(apc.name).")
        }
        let key = newKey(Keys.link)
        c.links.append(CodeLink(key: key, aprioriCode: aprioriKey, type: type, memo: memo))
        updateCode(c)
        return key
    }

    /// Changes a link's type or memo (its key and a priori code stay).
    public mutating func updateLink(_ link: CodeLink, of codeKey: String) {
        guard var c = code(codeKey), let i = c.links.firstIndex(where: { $0.key == link.key }) else { return }
        c.links[i].type = link.type
        c.links[i].memo = link.memo
        updateCode(c)
    }

    public mutating func deleteLink(_ key: String, of codeKey: String) {
        guard var c = code(codeKey) else { return }
        c.links.removeAll { $0.key == key }
        updateCode(c)
    }

    // MARK: Framework Matrix

    /// Sets the summary in one cell of a deductive layer's Framework Matrix:
    /// `row` a file or interviewee, `column` an a priori code or protocol
    /// item. An empty summary clears the cell.
    public mutating func setFrameworkSummary(_ text: String, layer: String, row: String, column: String) throws {
        guard let li = layerIndex(layer) else { throw RuleError("That layer no longer exists.") }
        guard layers[li].isDeductive else {
            throw RuleError("\(layers[li].name) is an inductive layer: the Framework Matrix belongs to deductive layers.")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            layers[li].framework[row]?[column] = nil
            if layers[li].framework[row]?.isEmpty == true { layers[li].framework[row] = nil }
        } else {
            layers[li].framework[row, default: [:]][column] = text
        }
    }

    /// Clears Framework Matrix columns (a priori codes or protocol items that
    /// are gone) in every layer.
    mutating func dropFrameworkColumns(_ columns: Set<String>) {
        guard !columns.isEmpty else { return }
        for li in layers.indices {
            for row in layers[li].framework.keys {
                for c in columns { layers[li].framework[row]![c] = nil }
                if layers[li].framework[row]!.isEmpty { layers[li].framework[row] = nil }
            }
        }
    }
}

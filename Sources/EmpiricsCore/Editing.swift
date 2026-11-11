import Foundation

/// A change the rules don't allow, with a message for the researcher.
public struct RuleError: Error, LocalizedError, Equatable {
    public var message: String

    public init(_ message: String) { self.message = message }

    public var errorDescription: String? { message }
}

/// What moving an item to another layer takes with it.
public struct LayerComponent: Equatable {
    public var selections: Set<String>
    public var codes: Set<String>

    public init(selections: Set<String> = [], codes: Set<String> = []) {
        self.selections = selections
        self.codes = codes
    }

    public var isEmpty: Bool { selections.isEmpty && codes.isEmpty }
}

// Every change to a project goes through these functions, so the rules hold
// whatever the user interface does:
//
//  - selections and codes exist in exactly one layer;
//  - in a layer, no irrelevant selection overlaps any other selection that
//    is not irrelevant (so irrelevant text is never evidence);
//  - open codes have selections as evidence; axial codes have codes (open
//    or axial) of their own layer, with no cycles;
//  - moving anything to another layer moves everything linked to it.
extension Project {

    // MARK: Files

    @discardableResult
    public mutating func addFile(path: String, kind: FileKind, title: String = "", fingerprint: String = "") -> String {
        let key = newKey(Keys.file)
        files[key] = EmpiricalFile(key: key, path: path, kind: kind, title: title, fingerprint: fingerprint,
                                   added: Stamp.day())
        return key
    }

    /// Removes a file from the catalogue, with its selections in every layer
    /// (and their evidence links), its speaker map and its response sheets.
    /// The full-text itself is never touched.
    public mutating func removeFile(_ key: String) {
        files[key] = nil
        for i in layers.indices {
            let gone = (layers[i].selections[key] ?? []).map(\.key)
            layers[i].selections[key] = nil
            for k in gone { unlinkSelection(k, inLayerAt: i) }
        }
        speakerMaps[key] = nil
        for id in responses.keys where id.target == key { responses[id] = nil }
    }

    public func file(path: String) -> EmpiricalFile? { files.values.first { $0.path == path } }

    // MARK: Layers

    @discardableResult
    public mutating func addLayer(name: String, researcher: String = "") -> String {
        let key = newKey(Keys.layer)
        layers.append(CodingLayer(key: key, name: name, researcher: researcher))
        return key
    }

    /// Deletes a layer with everything in it. The last layer can't go.
    public mutating func deleteLayer(_ key: String) throws {
        guard layers.count > 1 else { throw RuleError("A project needs at least one layer.") }
        guard let i = layerIndex(key) else { return }
        let codes = Set(layers[i].codes.keys)
        layers.remove(at: i)
        for id in responses.keys where codes.contains(id.target) { responses[id] = nil }
    }

    public mutating func moveLayer(_ key: String, to index: Int) {
        guard let i = layerIndex(key) else { return }
        let layer = layers.remove(at: i)
        layers.insert(layer, at: max(0, min(index, layers.count)))
    }

    // MARK: Selections

    /// Selections in `layer` and `file` that a new selection over `spans`
    /// would break the rules with: for an irrelevant selection, every
    /// overlapping selection that is not irrelevant; otherwise, every
    /// overlapping irrelevant one.
    public func conflicts(layer: String, file: String, spans: [TextSpan], irrelevant: Bool,
                          excluding: String? = nil) -> [CodeSelection] {
        guard let l = self.layer(layer) else { return [] }
        return (l.selections[file] ?? []).filter { s in
            s.key != excluding && s.irrelevant != irrelevant && s.overlaps(spans)
        }
    }

    /// Adds a selection to a layer. Irrelevant selections merge with any
    /// irrelevant selections they overlap or touch (returning the merged
    /// selection's key); a selection exactly matching an existing one that
    /// is not irrelevant returns that one instead of making a duplicate.
    @discardableResult
    public mutating func addSelection(layer: String, file: String, spans: [TextSpan], quote: String = "",
                                      irrelevant: Bool = false, by: String = "") throws -> String {
        guard let li = layerIndex(layer) else { throw RuleError("That layer no longer exists.") }
        guard files[file] != nil else { throw RuleError("That file is no longer in the project.") }
        let spans = TextSpan.normalised(spans)
        guard !spans.isEmpty else { throw RuleError("Select some text first.") }

        let clashes = conflicts(layer: layer, file: file, spans: spans, irrelevant: irrelevant)
        if !clashes.isEmpty {
            throw RuleError(irrelevant
                ? "Part of this text is already selected (\(clashes.count == 1 ? "1 selection" : "\(clashes.count) selections")), so it can't be marked irrelevant. Remove or shrink those selections first."
                : "Part of this text is marked irrelevant in this layer, so it can't be selected as evidence. Unmark it first.")
        }

        var list = layers[li].selections[file] ?? []
        let quoteText = settings.storeQuotes ? quote : ""
        if !irrelevant, let same = list.first(where: { !$0.irrelevant && $0.spans == spans }) {
            return same.key
        }
        if irrelevant {
            let touching = list.filter { s in s.irrelevant && s.spans.contains { a in spans.contains { a.touches($0) } } }
            if let keep = touching.min(by: { $0.created < $1.created }) {
                let merged = TextSpan.normalised(touching.flatMap(\.spans) + spans)
                list.removeAll { s in touching.contains { $0.key == s.key } }
                var s = keep
                s.spans = merged
                s.quote = ""   // irrelevant text needs no quote
                list.append(s)
                layers[li].selections[file] = list.sorted(by: Self.selectionOrder)
                return s.key
            }
        }
        let key = newKey(Keys.selection)
        list.append(CodeSelection(key: key, fileKey: file, spans: spans, quote: irrelevant ? "" : quoteText,
                                  irrelevant: irrelevant, by: by, created: Stamp.now()))
        layers[li].selections[file] = list.sorted(by: Self.selectionOrder)
        if files[file]?.status == .notStarted { files[file]?.status = .inProgress }
        return key
    }

    static func selectionOrder(_ a: CodeSelection, _ b: CodeSelection) -> Bool {
        guard let x = a.first, let y = b.first else { return a.key < b.key }
        return x == y ? a.key < b.key : x < y
    }

    /// Changes what text a selection covers.
    public mutating func resizeSelection(_ key: String, spans: [TextSpan], quote: String = "") throws {
        guard let (li, file, si) = locateSelection(key) else { return }
        let spans = TextSpan.normalised(spans)
        guard !spans.isEmpty else { throw RuleError("Select some text first.") }
        let s = layers[li].selections[file]![si]
        if !conflicts(layer: layers[li].key, file: file, spans: spans, irrelevant: s.irrelevant, excluding: key).isEmpty {
            throw RuleError(s.irrelevant
                ? "The new range overlaps selected text, which can't be irrelevant."
                : "The new range overlaps text marked irrelevant in this layer.")
        }
        layers[li].selections[file]![si].spans = spans
        layers[li].selections[file]![si].quote = (settings.storeQuotes && !s.irrelevant) ? quote : ""
        layers[li].selections[file]!.sort(by: Self.selectionOrder)
    }

    /// Marks a selection irrelevant, or not. A selection that is evidence for
    /// a code can't be irrelevant, nor can one overlapping other selections.
    public mutating func setIrrelevant(_ key: String, _ irrelevant: Bool) throws {
        guard let (li, file, si) = locateSelection(key) else { return }
        let s = layers[li].selections[file]![si]
        guard s.irrelevant != irrelevant else { return }
        if irrelevant {
            let codes = layers[li].codes.values.filter { $0.hasEvidence(key) }
            if !codes.isEmpty {
                let names = codes.map(\.name).sorted().joined(separator: ", ")
                throw RuleError("This selection is evidence for \(names), so it can't be marked irrelevant. Remove it from \(codes.count == 1 ? "that code" : "those codes") first.")
            }
        }
        if !conflicts(layer: layers[li].key, file: file, spans: s.spans, irrelevant: irrelevant, excluding: key).isEmpty {
            throw RuleError(irrelevant
                ? "This selection overlaps other selections, so it can't be marked irrelevant."
                : "This selection overlaps text marked irrelevant.")
        }
        layers[li].selections[file]![si].irrelevant = irrelevant
        if irrelevant { layers[li].selections[file]![si].quote = "" }
    }

    /// Deletes a selection, and its evidence links and interrelation entries.
    public mutating func deleteSelection(_ key: String) {
        guard let (li, file, si) = locateSelection(key) else { return }
        layers[li].selections[file]!.remove(at: si)
        if layers[li].selections[file]!.isEmpty { layers[li].selections[file] = nil }
        unlinkSelection(key, inLayerAt: li)
    }

    private mutating func unlinkSelection(_ key: String, inLayerAt li: Int) {
        for (ck, c) in layers[li].codes where c.hasEvidence(key) || c.interrelations.contains(where: { $0.members.contains(key) }) {
            var c = c
            c.evidence.removeAll { $0.target == key }
            for j in c.interrelations.indices { c.interrelations[j].members.removeAll { $0 == key } }
            layers[li].codes[ck] = c
        }
    }

    /// (layer index, file key, index in the file's list).
    func locateSelection(_ key: String) -> (Int, String, Int)? {
        for (li, layer) in layers.enumerated() {
            for (file, list) in layer.selections {
                if let si = list.firstIndex(where: { $0.key == key }) { return (li, file, si) }
            }
        }
        return nil
    }

    // MARK: Codes

    @discardableResult
    public mutating func addCode(layer: String, kind: CodeKind, name: String, by: String = "") throws -> String {
        guard let li = layerIndex(layer) else { throw RuleError("That layer no longer exists.") }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw RuleError("A code needs a name.") }
        let key = newKey(Keys.code)
        let colour = CodePalette.next(used: layers[li].codes.values.map(\.colour))
        layers[li].codes[key] = QDACode(key: key, kind: kind, name: trimmed, colour: colour, by: by, created: Stamp.now())
        return key
    }

    /// A code in the same layer with this name (ignoring case), if any.
    public func code(named name: String, inLayer layer: String) -> QDACode? {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return self.layer(layer)?.codes.values.first { $0.name.compare(n, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    public mutating func updateCode(_ code: QDACode) {
        guard let li = layers.firstIndex(where: { $0.codes[code.key] != nil }) else { return }
        layers[li].codes[code.key] = code
    }

    /// Deletes a code, and its place in other codes' evidence and
    /// interrelations. Its evidence (selections, codes) stays.
    public mutating func deleteCode(_ key: String) {
        guard let li = layers.firstIndex(where: { $0.codes[key] != nil }) else { return }
        layers[li].codes[key] = nil
        for (ck, c) in layers[li].codes where c.hasEvidence(key) || c.interrelations.contains(where: { $0.members.contains(key) }) {
            var c = c
            c.evidence.removeAll { $0.target == key }
            for j in c.interrelations.indices { c.interrelations[j].members.removeAll { $0 == key } }
            layers[li].codes[ck] = c
        }
        for id in responses.keys where id.target == key { responses[id] = nil }
    }

    /// Why `target` can't be evidence for `code`, or nil if it can.
    public func evidenceProblem(code codeKey: String, target: String) -> String? {
        guard let li = layers.firstIndex(where: { $0.codes[codeKey] != nil }), let code = layers[li].codes[codeKey] else {
            return "That code no longer exists."
        }
        let layer = layers[li]
        if code.hasEvidence(target) { return "That is already evidence for \(code.name)." }
        switch code.kind {
        case .open:
            guard let s = layer.selection(target) else {
                return layer.codes[target] != nil
                    ? "Open codes are evidenced by selections; make \(code.name) an axial code to build it from codes."
                    : "Evidence must be in the same layer as the code."
            }
            if s.irrelevant { return "Irrelevant text can't be evidence." }
        case .axial:
            guard let child = layer.codes[target] else {
                return layer.selection(target) != nil
                    ? "Axial codes are evidenced by codes, not selections."
                    : "Evidence must be in the same layer as the code."
            }
            if child.key == code.key { return "A code can't be evidence for itself." }
            if reaches(from: child.key, to: code.key, in: layer) {
                return "\(child.name) already builds on \(code.name), so this would make a loop."
            }
        }
        return nil
    }

    /// True if `to` is reachable from `from` through axial evidence.
    func reaches(from: String, to: String, in layer: CodingLayer) -> Bool {
        var stack = [from]
        var seen = Set<String>()
        while let k = stack.popLast() {
            if k == to { return true }
            guard seen.insert(k).inserted, let c = layer.codes[k], c.kind == .axial else { continue }
            stack.append(contentsOf: c.evidence.map(\.target))
        }
        return false
    }

    public mutating func addEvidence(code codeKey: String, target: String, memo: String = "") throws {
        if let problem = evidenceProblem(code: codeKey, target: target) { throw RuleError(problem) }
        guard let li = layers.firstIndex(where: { $0.codes[codeKey] != nil }) else { return }
        layers[li].codes[codeKey]!.evidence.append(Evidence(target: target, memo: memo))
    }

    public mutating func removeEvidence(code codeKey: String, target: String) {
        guard let li = layers.firstIndex(where: { $0.codes[codeKey] != nil }) else { return }
        layers[li].codes[codeKey]!.evidence.removeAll { $0.target == target }
        for j in layers[li].codes[codeKey]!.interrelations.indices {
            layers[li].codes[codeKey]!.interrelations[j].members.removeAll { $0 == target }
        }
    }

    public mutating func setMemo(code codeKey: String, target: String, memo: String) {
        guard let li = layers.firstIndex(where: { $0.codes[codeKey] != nil }),
              let ei = layers[li].codes[codeKey]!.evidence.firstIndex(where: { $0.target == target }) else { return }
        layers[li].codes[codeKey]!.evidence[ei].memo = memo
    }

    /// Changes an open code to axial or back; only while it has no evidence.
    public mutating func setKind(code codeKey: String, _ kind: CodeKind) throws {
        guard let li = layers.firstIndex(where: { $0.codes[codeKey] != nil }) else { return }
        guard layers[li].codes[codeKey]!.kind != kind else { return }
        guard layers[li].codes[codeKey]!.evidence.isEmpty else {
            throw RuleError("Remove the code's evidence before changing its kind.")
        }
        layers[li].codes[codeKey]!.kind = kind
    }

    // MARK: Moving between layers

    /// Everything linked to `key` (a selection or code) in its layer:
    /// selections and the open codes they are evidence for, and codes and
    /// the axial codes they build, followed both ways.
    public func component(of key: String) -> LayerComponent {
        guard let lk = layerKey(holding: key), let layer = self.layer(lk) else { return LayerComponent() }
        var selections = Set<String>()
        var codes = Set<String>()
        var stack = [key]
        // Reverse links: target → codes that use it as evidence.
        var usedBy: [String: [String]] = [:]
        for c in layer.codes.values { for e in c.evidence { usedBy[e.target, default: []].append(c.key) } }
        while let k = stack.popLast() {
            if let c = layer.codes[k] {
                guard codes.insert(k).inserted else { continue }
                stack.append(contentsOf: c.evidence.map(\.target))
                stack.append(contentsOf: usedBy[k] ?? [])
            } else if layer.selection(k) != nil {
                guard selections.insert(k).inserted else { continue }
                stack.append(contentsOf: usedBy[k] ?? [])
            }
        }
        return LayerComponent(selections: selections, codes: codes)
    }

    /// Moves `key` and everything linked to it to another layer. Refused if
    /// a moved selection would overlap text of the other kind (irrelevant or
    /// not) in the target layer.
    @discardableResult
    public mutating func move(_ key: String, toLayer target: String) throws -> LayerComponent {
        guard let from = layerKey(holding: key), let fi = layerIndex(from) else { return LayerComponent() }
        guard let ti = layerIndex(target) else { throw RuleError("That layer no longer exists.") }
        guard from != target else { return LayerComponent() }
        let comp = component(of: key)

        var moving: [CodeSelection] = []
        for (_, list) in layers[fi].selections { moving.append(contentsOf: list.filter { comp.selections.contains($0.key) }) }
        for s in moving {
            let clashes = (layers[ti].selections[s.fileKey] ?? []).filter { $0.irrelevant != s.irrelevant && $0.overlaps(s) }
            if !clashes.isEmpty {
                let title = files[s.fileKey]?.displayTitle ?? "a file"
                throw RuleError("In \(title), a selection being moved overlaps \(s.irrelevant ? "selected" : "irrelevant") text in \(layers[ti].name). Resolve that first.")
            }
        }
        for s in moving {
            layers[fi].selections[s.fileKey]?.removeAll { $0.key == s.key }
            if layers[fi].selections[s.fileKey]?.isEmpty == true { layers[fi].selections[s.fileKey] = nil }
            var list = layers[ti].selections[s.fileKey] ?? []
            list.append(s)
            layers[ti].selections[s.fileKey] = list.sorted(by: Self.selectionOrder)
        }
        for ck in comp.codes {
            if let c = layers[fi].codes.removeValue(forKey: ck) { layers[ti].codes[ck] = c }
        }
        return comp
    }

    // MARK: Interrelations

    @discardableResult
    public mutating func addInterrelation(code codeKey: String, type: String, members: [String], description: String = "") -> String? {
        guard let li = layers.firstIndex(where: { $0.codes[codeKey] != nil }) else { return nil }
        let key = newKey(Keys.interrelation)
        layers[li].codes[codeKey]!.interrelations.append(
            Interrelation(key: key, type: type, members: members, description: description))
        return key
    }

    // MARK: Codebooks and responses

    /// Deletes a codebook, its associations and its response sheets.
    public mutating func deleteCodebook(_ key: String) {
        codebooks[key] = nil
        for k in files.keys { files[k]!.codebooks.removeAll { $0 == key } }
        for li in layers.indices {
            for ck in layers[li].codes.keys where layers[li].codes[ck]!.codebooks.contains(key) {
                layers[li].codes[ck]!.codebooks.removeAll { $0 == key }
            }
        }
        for id in responses.keys where id.codebook == key { responses[id] = nil }
    }

    /// Associates a codebook with a file or code (if the codebook applies).
    public mutating func associate(codebook: String, with target: String) throws {
        guard let cb = codebooks[codebook] else { return }
        if files[target] != nil {
            guard cb.appliesTo.contains(.files) else { throw RuleError("\(cb.title) isn't for empirical files.") }
            if !files[target]!.codebooks.contains(codebook) { files[target]!.codebooks.append(codebook) }
        } else if let code = code(target) {
            let needed: CodebookTarget = code.kind == .open ? .openCodes : .axialCodes
            guard cb.appliesTo.contains(needed) else { throw RuleError("\(cb.title) isn't for \(needed.label.lowercased()).") }
            var c = code
            if !c.codebooks.contains(codebook) { c.codebooks.append(codebook) }
            updateCode(c)
        }
    }

    /// Removes the association (response sheets are kept, in case it is
    /// associated again).
    public mutating func dissociate(codebook: String, from target: String) {
        if files[target] != nil {
            files[target]!.codebooks.removeAll { $0 == codebook }
        } else if var c = code(target) {
            c.codebooks.removeAll { $0 == codebook }
            updateCode(c)
        }
    }

    /// Saves a response sheet; refused while blocking questions are
    /// unanswered.
    public mutating func saveSheet(_ sheet: ResponseSheet) throws {
        guard let cb = codebooks[sheet.id.codebook] else { throw RuleError("That codebook no longer exists.") }
        let completeness = SheetCompleteness.of(sheet.answers, against: cb)
        guard completeness.canSave else {
            let labels = completeness.missingBlocking.map(\.label).joined(separator: ", ")
            throw RuleError("Answer the mandatory questions first: \(labels).")
        }
        var s = sheet
        // Drop answers to questions no longer in the codebook, and empty ones.
        s.answers = s.answers.filter { k, a in cb.question(k) != nil && !a.isEmpty }
        s.updated = Stamp.now()
        responses[s.id] = s
        // New options typed into lists that aren't strict join the codebook.
        var book = cb
        for i in book.questions.indices where book.questions[i].type.usesOptions && !book.questions[i].strict {
            for v in s.answers[book.questions[i].key]?.values ?? [] where !book.questions[i].options.contains(v) {
                book.questions[i].options.append(v)
            }
        }
        if book != cb { codebooks[cb.key] = book }
    }

    /// Deletes a question from a codebook, and its answers.
    public mutating func deleteQuestion(_ key: String, from codebook: String) {
        codebooks[codebook]?.questions.removeAll { $0.key == key }
        for id in responses.keys where id.codebook == codebook { responses[id]!.answers[key] = nil }
    }

    /// Codebooks associated with a file or code that apply to it.
    public func codebooks(for target: String) -> [Codebook] {
        let keys = files[target]?.codebooks ?? code(target)?.codebooks ?? []
        return keys.compactMap { codebooks[$0] }
    }

    // MARK: People

    public mutating func deleteResearcher(_ key: String) {
        researchers.removeAll { $0.key == key }
        for i in layers.indices where layers[i].researcher == key { layers[i].researcher = "" }
        for k in speakerMaps.keys { speakerMaps[k]!.assignments.removeAll { $0.person == key } }
    }

    public mutating func deleteInterviewee(_ key: String) {
        interviewees.removeAll { $0.key == key }
        for k in speakerMaps.keys { speakerMaps[k]!.assignments.removeAll { $0.person == key } }
    }
}

// MARK: - Index

/// Lookups derived from a project, rebuilt after every change: which codes
/// each selection is evidence for, which axial codes build on each code, and
/// where everything is.
public struct ProjectIndex {
    /// Selection key → open codes it is evidence for.
    public var codesForSelection: [String: [String]] = [:]
    /// Code key → axial codes it is evidence for.
    public var parents: [String: [String]] = [:]
    /// Selection or code key → layer key.
    public var layerOf: [String: String] = [:]
    /// Selection key → file key.
    public var fileOf: [String: String] = [:]
    /// Code key → files where it (or anything it builds on) has evidence.
    public var filesForCode: [String: Set<String>] = [:]
    /// File key → selection count, all layers.
    public var selectionCount: [String: Int] = [:]

    public init() {}

    public init(_ project: Project) {
        for layer in project.layers {
            for (file, list) in layer.selections {
                selectionCount[file, default: 0] += list.count
                for s in list {
                    layerOf[s.key] = layer.key
                    fileOf[s.key] = file
                }
            }
            for c in layer.codes.values {
                layerOf[c.key] = layer.key
                for e in c.evidence {
                    if c.kind == .open {
                        codesForSelection[e.target, default: []].append(c.key)
                    } else {
                        parents[e.target, default: []].append(c.key)
                    }
                }
            }
            // Files per code, following axial evidence down to selections.
            var memo: [String: Set<String>] = [:]
            func files(_ key: String, _ depth: Int) -> Set<String> {
                if let m = memo[key] { return m }
                guard depth < 64, let c = layer.codes[key] else { return [] }
                var result = Set<String>()
                for e in c.evidence {
                    if c.kind == .open {
                        if let f = fileOf[e.target] { result.insert(f) }
                    } else {
                        result.formUnion(files(e.target, depth + 1))
                    }
                }
                memo[key] = result
                return result
            }
            for k in layer.codes.keys { filesForCode[k] = files(k, 0) }
        }
        for k in codesForSelection.keys { codesForSelection[k]!.sort() }
        for k in parents.keys { parents[k]!.sort() }
    }
}

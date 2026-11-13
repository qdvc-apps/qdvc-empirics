import Foundation

// Changes that follow the full-text itself: correcting the text of a text
// file in place (a typo in a transcript), with every layer's selections
// adjusted to its new shape; turning PDF pages for reading; and joining two
// selections next to each other that are coded the same way.

// MARK: - Editing a full-text in place

/// What an edit to a file's text would do to its selections, in every layer.
public struct TextEditImpact: Equatable {
    /// Selections after the edit, which only move.
    public var moved: Int = 0
    /// Selections overlapping the edit, whose text changes with it.
    public var resized: Int = 0
    /// Selections whose text would be gone entirely: they are deleted.
    public var emptied: [String] = []

    public init() {}

    public var isEmpty: Bool { moved == 0 && resized == 0 && emptied.isEmpty }
}

extension TextSpan {
    /// Where the span goes when the text at `start ..< start + length` is
    /// replaced by `count` UTF-16 units. Text before the edit stays; text
    /// after it moves. A span overlapping the edit keeps what it had outside
    /// it and takes in the replacement (`inclusive`), or stops at its edge;
    /// an edit at the very start or end of a span stays outside it.
    func adjusted(start a: Int, length: Int, count n: Int, inclusive: Bool = true) -> TextSpan {
        let b = a + length
        let delta = n - length
        let s: Int
        let e: Int
        if start < a { s = start } else if start >= b { s = start + delta } else { s = inclusive ? a : a + n }
        if end <= a { e = end } else if end >= b { e = end + delta } else { e = inclusive ? a + n : a }
        return TextSpan(page: page, start: s, length: max(0, e - s))
    }

    /// True if the edit changes text inside the span (so its text changes
    /// even when its position and length don't).
    func isTouched(start a: Int, length: Int) -> Bool {
        length > 0 ? (start < a + length && a < end) : (start < a && a < end)
    }
}

extension Project {
    /// What replacing `start ..< start + length` of a text file with
    /// `replacement` would do to its selections (nothing is changed).
    public func textEditImpact(file: String, start: Int, length: Int, replacement: String) -> TextEditImpact {
        var impact = TextEditImpact()
        let n = (replacement as NSString).length
        for layer in layers {
            for s in layer.selections[file] ?? [] {
                let spans = s.spans.map { $0.adjusted(start: start, length: length, count: n, inclusive: !s.irrelevant) }
                let touched = s.spans.contains { $0.isTouched(start: start, length: length) }
                guard touched || spans != s.spans else { continue }
                if spans.allSatisfy({ $0.length == 0 }) {
                    impact.emptied.append(s.key)
                } else if touched {
                    impact.resized += 1
                } else {
                    impact.moved += 1
                }
            }
        }
        return impact
    }

    /// Replaces `start ..< start + length` (UTF-16 offsets) of a text file's
    /// text with `replacement`, and adjusts every layer's selections of the
    /// file to the new text: those after the edit move, those overlapping it
    /// take in the new text (irrelevant ones stop at its edges, so they never
    /// come to overlap evidence), and those left with no text are deleted.
    /// Stored quotes are taken again from the new text, and the file gets
    /// `fingerprint`, that of the text as written to disk. Returns the new
    /// text. The caller writes it to the full-text.
    @discardableResult
    public mutating func applyTextEdit(file: String, oldText: String, start: Int, length: Int,
                                       replacement: String, fingerprint: String) throws -> String {
        guard let f = files[file] else { throw RuleError("That file is no longer in the project.") }
        guard f.kind.isText else { throw RuleError("Only text and Markdown files can be edited.") }
        let old = oldText as NSString
        guard start >= 0, length >= 0, start + length <= old.length else {
            throw RuleError("That part of the text is no longer there. Select it again.")
        }
        let newText = old.replacingCharacters(in: NSRange(location: start, length: length), with: replacement)
        let n = (replacement as NSString).length
        var emptied: [String] = []
        for li in layers.indices {
            guard var list = layers[li].selections[file] else { continue }
            for si in list.indices {
                let s = list[si]
                let spans = s.spans.map { $0.adjusted(start: start, length: length, count: n, inclusive: !s.irrelevant) }
                guard spans != s.spans || s.spans.contains(where: { $0.isTouched(start: start, length: length) }) else { continue }
                let kept = spans.filter { $0.length > 0 }
                if kept.isEmpty {
                    emptied.append(s.key)
                    continue
                }
                list[si].spans = TextSpan.normalised(kept)
                if !s.quote.isEmpty { list[si].quote = TextNormaliser.quote(list[si].spans, pages: [newText]) }
            }
            // Irrelevant text never overlaps other selections: trim it where
            // a neighbour took in the new text.
            let relevant = list.filter { !$0.irrelevant && !emptied.contains($0.key) }.flatMap(\.spans)
            for si in list.indices where list[si].irrelevant && !emptied.contains(list[si].key) {
                let trimmed = list[si].spans.map { Self.trim($0, outside: relevant) }.filter { $0.length > 0 }
                if trimmed.isEmpty { emptied.append(list[si].key) } else { list[si].spans = trimmed }
            }
            layers[li].selections[file] = list.sorted(by: Self.selectionOrder)
        }
        for key in emptied { deleteSelection(key) }
        files[file]?.fingerprint = fingerprint
        return newText
    }

    /// `span` without the parts that overlap `others` (where it would be
    /// split, only its first part is kept).
    static func trim(_ span: TextSpan, outside others: [TextSpan]) -> TextSpan {
        var s = span
        for o in others.sorted() where o.overlaps(s) {
            if o.start <= s.start {
                s = TextSpan(page: s.page, start: o.end, length: max(0, s.end - o.end))
            } else {
                s = TextSpan(page: s.page, start: s.start, length: o.start - s.start)
            }
            if s.length == 0 { break }
        }
        return s
    }
}

extension TextNormaliser {
    /// How a text file's bytes were written, so an edited text can be
    /// written back the same way.
    enum Encoding: Equatable {
        case utf8(bom: Bool)
        case utf16LittleEndian
        case utf16BigEndian
        case windows1252
    }

    static func encoding(of data: Data) -> Encoding {
        if data.starts(with: [0xFF, 0xFE]) { return .utf16LittleEndian }
        if data.starts(with: [0xFE, 0xFF]) { return .utf16BigEndian }
        if isValidUTF8(data) { return .utf8(bom: data.starts(with: [0xEF, 0xBB, 0xBF])) }
        return .windows1252
    }

    /// The line ending the file uses: \r\n, \r or \n (the first kind found).
    static func lineEnding(of data: Data, encoding: Encoding) -> String {
        let raw: String
        switch encoding {
        case .utf8: raw = String(decoding: data, as: UTF8.self)
        case .utf16LittleEndian, .utf16BigEndian: raw = String(data: data, encoding: .utf16) ?? ""
        case .windows1252: raw = windows1252(data)
        }
        let units = Array(raw.utf16)
        for (i, u) in units.enumerated() {
            if u == 0x0A { return "\n" }
            if u == 0x0D { return i + 1 < units.count && units[i + 1] == 0x0A ? "\r\n" : "\r" }
        }
        return "\n"
    }

    /// The bytes for `text` (as the app shows it: \n line endings, no
    /// byte-order mark), written the way `original` was: the same encoding,
    /// byte-order mark and line endings, so `text(from:)` gives `text` back.
    /// A Windows-1252 file whose new text has characters Windows-1252 can't
    /// hold is written as UTF-8 (`changedEncoding`).
    public static func data(for text: String, like original: Data) -> (data: Data, changedEncoding: Bool) {
        let encoding = encoding(of: original)
        let ending = lineEnding(of: original, encoding: encoding)
        let body = ending == "\n" ? text : text.replacingOccurrences(of: "\n", with: ending)
        switch encoding {
        case .utf8(let bom):
            return ((bom ? Data([0xEF, 0xBB, 0xBF]) : Data()) + Data(body.utf8), false)
        case .utf16LittleEndian:
            var d = Data([0xFF, 0xFE])
            for u in body.utf16 { d.append(UInt8(u & 0xFF)); d.append(UInt8(u >> 8)) }
            return (d, false)
        case .utf16BigEndian:
            var d = Data([0xFE, 0xFF])
            for u in body.utf16 { d.append(UInt8(u >> 8)); d.append(UInt8(u & 0xFF)) }
            return (d, false)
        case .windows1252:
            if let d = windows1252Data(body) { return (d, false) }
            return (Data(body.utf8), true)
        }
    }

    /// Windows-1252 bytes, or nil if a character has no place in it.
    static func windows1252Data(_ s: String) -> Data? {
        var high: [UInt32: UInt8] = [:]
        for b in UInt8(0x80)...UInt8(0x9F) {
            let decoded = windows1252(Data([b])).unicodeScalars.first?.value ?? 0xFFFD
            if decoded != 0xFFFD { high[decoded] = b }
        }
        var out = Data()
        for scalar in s.unicodeScalars {
            let v = scalar.value
            if v < 0x80 || (0xA0...0xFF).contains(v) {
                out.append(UInt8(v))
            } else if let b = high[v] {
                out.append(b)
            } else {
                return nil
            }
        }
        return out
    }
}

// MARK: - Turning PDF pages

extension Project {
    /// Turns a PDF page by `degrees` (a multiple of 90; positive is
    /// clockwise) for reading. Only how it is shown: the PDF is never
    /// changed, and selections are unaffected.
    public mutating func rotatePage(file: String, page: Int, by degrees: Int) {
        guard let f = files[file], f.kind == .pdf, page >= 0, degrees % 90 == 0 else { return }
        let turned = (((f.rotations[page] ?? 0) + degrees) % 360 + 360) % 360
        files[file]!.rotations[page] = turned == 0 ? nil : turned
    }

    public mutating func resetPageRotation(file: String, page: Int) {
        files[file]?.rotations[page] = nil
    }
}

// MARK: - Merging selections next to each other

extension Project {
    /// The codes a selection is evidence for in its layer: open codes on an
    /// inductive layer, a priori codes on a deductive one.
    func codesOf(selection key: String, inLayerAt li: Int) -> Set<String> {
        let layer = layers[li]
        if layer.isDeductive { return Set(layer.aprioriCodes(for: key)) }
        return Set(layer.codes.values.filter { $0.hasEvidence(key) }.map(\.key))
    }

    /// The selections a selection could be merged with: in the same layer
    /// and file, right before or after it (touching, or with only white
    /// space between them, on the same page), and coded the same way (both
    /// irrelevant, the same protocol item and part, or evidence for exactly
    /// the same codes; two highlights without codes count too). In text
    /// order. `pages` is the file's text (one page for a text file).
    public func mergeCandidates(for key: String, pages: [String]) -> [String] {
        guard let (li, file, si) = locateSelection(key) else { return [] }
        let list = layers[li].selections[file] ?? []
        let s = list[si]
        let codes = codesOf(selection: key, inLayerAt: li)
        return list.filter { o in
            o.key != key && o.irrelevant == s.irrelevant && o.segment == s.segment
                && codesOf(selection: o.key, inLayerAt: li) == codes
                && (Self.adjacent(s, o, pages: pages) || Self.adjacent(o, s, pages: pages))
        }.map(\.key)
    }

    /// True if `b` starts right after `a` ends: on the same page, touching
    /// or with only white space between, without overlapping.
    static func adjacent(_ a: CodeSelection, _ b: CodeSelection, pages: [String]) -> Bool {
        guard let end = a.spans.last, let start = b.spans.first, end.page == start.page,
              start.start >= end.end, !a.overlaps(b) else { return false }
        let page = end.page ?? 0
        guard page < pages.count else { return start.start == end.end }
        let ns = pages[page] as NSString
        guard start.start <= ns.length else { return false }
        let gap = ns.substring(with: NSRange(location: end.end, length: start.start - end.end))
        return gap.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Merges two selections next to each other and coded the same way (see
    /// `mergeCandidates`) into one covering both and the white space between
    /// them. The earlier one stays; the later one's memos join its memos,
    /// and the later one's place in interrelations passes to it. Returns the
    /// merged selection's key.
    @discardableResult
    public mutating func mergeSelections(_ first: String, _ second: String, pages: [String]) throws -> String {
        guard let (li, file, ai) = locateSelection(first), let (lj, fileB, bi) = locateSelection(second) else {
            throw RuleError("That selection no longer exists.")
        }
        guard li == lj, file == fileB else { throw RuleError("Only selections in the same layer and file can be merged.") }
        guard mergeCandidates(for: first, pages: pages).contains(second) else {
            throw RuleError("Only selections next to each other (with nothing but white space between them) and coded the same way can be merged.")
        }
        var a = layers[li].selections[file]![ai]
        var b = layers[li].selections[file]![bi]
        if Self.selectionOrder(b, a) { swap(&a, &b) }
        let keep = a.key, gone = b.key
        guard let end = a.spans.last, let start = b.spans.first else { return keep }
        let bridge = TextSpan(page: end.page, start: end.end, length: start.start - end.end)
        let spans = TextSpan.normalised(a.spans + [bridge] + b.spans)
        if !conflicts(layer: layers[li].key, file: file, spans: spans, irrelevant: a.irrelevant, excluding: keep)
            .filter({ $0.key != gone }).isEmpty {
            throw RuleError(a.irrelevant
                ? "The text between them is selected, so they can't be merged into one irrelevant selection."
                : "The text between them is marked irrelevant, so they can't be merged.")
        }
        // Memos and interrelations of the later one pass to the earlier one.
        for (ck, c) in layers[li].codes where c.hasEvidence(gone) || c.interrelations.contains(where: { $0.members.contains(gone) }) {
            var c = c
            let memo = c.memo(for: gone)
            if let i = c.evidence.firstIndex(where: { $0.target == keep }) {
                c.evidence[i].memo = Self.joined(c.evidence[i].memo, memo)
            }
            c.evidence.removeAll { $0.target == gone }
            for j in c.interrelations.indices where c.interrelations[j].members.contains(gone) {
                var members: [String] = []
                for m in c.interrelations[j].members.map({ $0 == gone ? keep : $0 }) where !members.contains(m) { members.append(m) }
                c.interrelations[j].members = members
            }
            layers[li].codes[ck] = c
        }
        for apc in layers[li].aprioriCodes(for: gone) {
            let memo = layers[li].aprioriEvidence[apc]!.first { $0.target == gone }?.memo ?? ""
            if let i = layers[li].aprioriEvidence[apc]!.firstIndex(where: { $0.target == keep }) {
                layers[li].aprioriEvidence[apc]![i].memo = Self.joined(layers[li].aprioriEvidence[apc]![i].memo, memo)
            }
            layers[li].aprioriEvidence[apc]!.removeAll { $0.target == gone }
            if layers[li].aprioriEvidence[apc]!.isEmpty { layers[li].aprioriEvidence[apc] = nil }
        }
        var list = layers[li].selections[file]!.filter { $0.key != gone }
        if let i = list.firstIndex(where: { $0.key == keep }) {
            list[i].spans = spans
            if !a.irrelevant, !a.quote.isEmpty || !b.quote.isEmpty {
                let q = TextNormaliser.quote(spans, pages: pages)
                list[i].quote = q.isEmpty ? a.quote + b.quote : q
            }
        }
        layers[li].selections[file] = list.sorted(by: Self.selectionOrder)
        return keep
    }

    /// Two memos as one (blank ones left out).
    static func joined(_ a: String, _ b: String) -> String {
        let x = a.trimmingCharacters(in: .whitespacesAndNewlines), y = b.trimmingCharacters(in: .whitespacesAndNewlines)
        if x.isEmpty { return b }
        if y.isEmpty || x == y { return a }
        return a + "\n\n" + b
    }
}

// MARK: - Writing a full-text

extension FullTexts {
    /// Writes a full-text (an edited text file), replacing the file
    /// atomically. Used only when the researcher confirms an edit.
    public func write(_ data: Data, to relative: String) throws {
        try data.write(to: url(relative), options: .atomic)
    }
}

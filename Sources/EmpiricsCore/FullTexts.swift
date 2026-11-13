import Foundation

/// Access to the full-texts folder. Full-texts are read; the only write is
/// `write(_:to:)` (TextEdits.swift), for an edit to a text file the
/// researcher has confirmed (docs/DESIGN.md §Data security).
public struct FullTexts {
    public let root: URL

    public init(root: URL) { self.root = root }

    public func url(_ relative: String) -> URL {
        relative.split(separator: "/").reduce(root) { $0.appendingPathComponent(String($1)) }
    }

    public func exists(_ relative: String) -> Bool {
        FileManager.default.fileExists(atPath: url(relative).path)
    }

    public func data(_ relative: String) throws -> Data {
        try Data(contentsOf: url(relative), options: [.mappedIfSafe])
    }

    /// "sha256:<hex>" of a file's bytes.
    public func fingerprint(_ relative: String) throws -> String {
        "sha256:" + SHA256.hex(try data(relative))
    }

    /// A text or Markdown file as the app shows and codes it
    /// (`TextNormaliser.text(from:)`).
    public func text(_ relative: String) throws -> String {
        TextNormaliser.text(from: try data(relative))
    }

    /// The path of `url` relative to the root, if it is inside it.
    public func relativePath(of url: URL) -> String? {
        let base = root.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let full = url.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        guard full.count > base.count, Array(full.prefix(base.count)) == base else { return nil }
        return full.dropFirst(base.count).joined(separator: "/")
    }

    /// Supported files in the folder (recursively) that aren't catalogued
    /// yet, sorted by path. Hidden files and folders are skipped.
    public func uncatalogued(known: Set<String>, excluding: Set<String> = []) -> [String] {
        guard let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey],
                                                     options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        var found: [String] = []
        for case let u as URL in e {
            guard (try? u.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true,
                  FileKind.forPath(u.path) != nil, let rel = relativePath(of: u),
                  !known.contains(rel), !excluding.contains(rel) else { continue }
            found.append(rel)
        }
        return found.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
}

/// Turns a text file's bytes into the text that selections point into:
/// UTF-8 (or UTF-16 with a byte-order mark, or else Windows-1252), without
/// a byte-order mark, with line endings as \n.
public enum TextNormaliser {
    public static func text(from data: Data) -> String {
        var s: String
        if data.starts(with: [0xFF, 0xFE]) || data.starts(with: [0xFE, 0xFF]) {
            s = String(data: data, encoding: .utf16) ?? ""
        } else if isValidUTF8(data) {
            s = String(decoding: data, as: UTF8.self)
        } else {
            s = windows1252(data)
        }
        if s.hasPrefix("\u{FEFF}") { s.removeFirst() }
        return s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    /// Strict UTF-8 validation (Foundation's decoder repairs bad bytes on
    /// some platforms, which would hide a Windows-1252 file).
    static func isValidUTF8(_ data: Data) -> Bool {
        var codec = UTF8()
        var it = data.makeIterator()
        while true {
            switch codec.decode(&it) {
            case .scalarValue: continue
            case .emptyInput: return true
            case .error: return false
            }
        }
    }

    /// Windows-1252, decoded here so every platform reads it the same way.
    static func windows1252(_ data: Data) -> String {
        let high: [UInt32] = [
            0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0x017D, 0xFFFD,
            0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0x017E, 0x0178,
        ]
        var scalars = String.UnicodeScalarView()
        for b in data {
            let v: UInt32 = (0x80...0x9F).contains(b) ? high[Int(b) - 0x80] : UInt32(b)
            scalars.append(UnicodeScalar(v) ?? "\u{FFFD}")
        }
        return String(scalars)
    }

    /// The text a set of spans covers (pages joined with a blank line).
    /// `pages` is the text of each PDF page; for text files pass the text
    /// as the only page.
    public static func quote(_ spans: [TextSpan], pages: [String]) -> String {
        spans.compactMap { span -> String? in
            let page = span.page ?? 0
            guard page < pages.count else { return nil }
            let ns = pages[page] as NSString
            guard span.start >= 0, span.end <= ns.length else { return nil }
            return ns.substring(with: NSRange(location: span.start, length: span.length))
        }.joined(separator: "\n\n")
    }
}

/// Finding selections again after a full-text has changed (a typo fixed in
/// a transcript, a PDF replaced by a corrected version).
public enum Anchoring {
    public enum Outcome: Equatable {
        /// The text at the stored position still matches.
        case unchanged
        /// Found elsewhere; the new spans.
        case moved([TextSpan])
        /// Not found (or no quote was stored to look for).
        case lost
    }

    /// Where `selection` is now in `pages` (one string for text files).
    public static func locate(_ selection: CodeSelection, in pages: [String]) -> Outcome {
        locate(selection, in: pages, squeezed: SqueezedPages(pages))
    }

    static func locate(_ selection: CodeSelection, in pages: [String], squeezed: SqueezedPages) -> Outcome {
        let current = TextAnchorQuote(spans: selection.spans, pages: pages)
        let quote = selection.quote
        if quote.isEmpty {
            // Without a quote, a selection is kept if it still fits.
            return current.fits ? .unchanged : .lost
        }
        if current.fits, current.text == quote { return .unchanged }
        if let span = find(quote, in: pages, near: selection.first, squeezed: squeezed) { return .moved([span]) }
        return .lost
    }

    /// Checks every selection of `file` in every layer against the file's
    /// current text, moving those that moved. Returns how many moved and the
    /// keys of those that could not be found.
    @discardableResult
    public static func reanchor(_ project: inout Project, file: String, pages: [String]) -> (moved: Int, lost: [String]) {
        var moved = 0
        var lost: [String] = []
        let squeezed = SqueezedPages(pages)
        for li in project.layers.indices {
            guard var list = project.layers[li].selections[file] else { continue }
            for i in list.indices {
                switch locate(list[i], in: pages, squeezed: squeezed) {
                case .unchanged: break
                case .moved(let spans):
                    list[i].spans = spans
                    // Found ignoring white space: keep the quote in step.
                    if !list[i].quote.isEmpty { list[i].quote = TextNormaliser.quote(spans, pages: pages) }
                    moved += 1
                case .lost:
                    lost.append(list[i].key)
                }
            }
            project.layers[li].selections[file] = list.sorted(by: Project.selectionOrder)
        }
        return (moved, lost)
    }

    // MARK: Checking a new version before using it

    /// What would become of a selection if its file's full-text were
    /// replaced by a new version.
    public enum Fate: Equatable {
        /// The same text is at the same place.
        case unchanged
        /// The same text is elsewhere: its new spans, and the text there
        /// (which may differ in white space).
        case moved([TextSpan], quote: String)
        /// There is no text to look for (no stored quote, and the version it
        /// was made on isn't available), but its position fits the new text,
        /// so it stays where it is, unchecked.
        case unverified
        /// Not found in the new version (or it no longer fits).
        case lost
    }

    /// One selection, checked against a new version of its file.
    public struct Check: Equatable, Identifiable {
        public var selection: String
        public var layer: String
        public var file: String
        /// The text looked for: the stored quote, or the text at the
        /// selection's position in the version it was made on.
        public var quote: String
        public var irrelevant: Bool
        public var fate: Fate

        public var id: String { selection }

        public init(selection: String, layer: String, file: String, quote: String, irrelevant: Bool, fate: Fate) {
            self.selection = selection
            self.layer = layer
            self.file = file
            self.quote = quote
            self.irrelevant = irrelevant
            self.fate = fate
        }
    }

    /// What would become of every selection of `file`, in every layer, if
    /// its full-text became `newPages`. `oldPages`, the text the selections
    /// were made on (if it is still available), gives the text to look for
    /// when no quote is stored, which is always the case for irrelevant
    /// selections. Nothing is changed.
    public static func check(_ project: Project, file: String, newPages: [String], oldPages: [String]?) -> [Check] {
        var result: [Check] = []
        let squeezed = SqueezedPages(newPages)
        for layer in project.layers {
            for s in layer.selections[file] ?? [] {
                var quote = s.quote
                if quote.isEmpty, let oldPages {
                    let old = TextAnchorQuote(spans: s.spans, pages: oldPages)
                    if old.fits { quote = old.text }
                }
                result.append(Check(selection: s.key, layer: layer.key, file: file, quote: quote, irrelevant: s.irrelevant,
                                    fate: fate(spans: s.spans, quote: quote, in: newPages, squeezed: squeezed)))
            }
        }
        return result
    }

    /// Where text that was at `spans` is in `pages`.
    public static func fate(spans: [TextSpan], quote: String, in pages: [String]) -> Fate {
        fate(spans: spans, quote: quote, in: pages, squeezed: SqueezedPages(pages))
    }

    static func fate(spans: [TextSpan], quote: String, in pages: [String], squeezed: SqueezedPages) -> Fate {
        let current = TextAnchorQuote(spans: spans, pages: pages)
        if quote.isEmpty { return current.fits ? .unverified : .lost }
        if current.fits, current.text == quote { return .unchanged }
        if let span = find(quote, in: pages, near: spans.first, squeezed: squeezed) {
            return .moved([span], quote: TextNormaliser.quote([span], pages: pages))
        }
        return .lost
    }

    /// Applies checks made by `check`: moved selections take their new
    /// spans (and, when the project stores quotes, the text there); lost
    /// ones are deleted if `deleteLost`, otherwise kept where they were.
    public static func apply(_ checks: [Check], to project: inout Project, deleteLost: Bool) {
        var files = Set<String>()
        for c in checks {
            files.insert(c.file)
            switch c.fate {
            case .unchanged, .unverified:
                break
            case .moved(let spans, let quote):
                guard let (li, file, si) = project.locateSelection(c.selection) else { continue }
                project.layers[li].selections[file]![si].spans = spans
                let irrelevant = project.layers[li].selections[file]![si].irrelevant
                if project.settings.storeQuotes && !irrelevant {
                    project.layers[li].selections[file]![si].quote = quote
                }
            case .lost:
                if deleteLost { project.deleteSelection(c.selection) }
            }
        }
        for li in project.layers.indices {
            for file in files where project.layers[li].selections[file] != nil {
                project.layers[li].selections[file]!.sort(by: Project.selectionOrder)
            }
        }
    }

    // MARK: Finding text

    /// Where `quote` is in `pages` (in a single page), nearest the old
    /// position `near`: exactly if it can be, otherwise ignoring differences
    /// in white space (lines wrapped differently, doubled spaces), which a
    /// corrected transcript or a re-exported PDF often has.
    static func find(_ quote: String, in pages: [String], near: TextSpan?, squeezed: SqueezedPages) -> TextSpan? {
        let exact = nearest(pageCount: pages.count, near: near) { p in occurrences(of: quote, in: pages[p] as NSString) }
        if let exact { return exact }
        let needle = squeeze(quote).text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return nil }
        let hays = squeezed.value
        return nearest(pageCount: pages.count, near: near) { p in
            let hay = hays[p]
            return occurrences(of: needle, in: hay.text as NSString).map { (r: NSRange) -> NSRange in
                let start = hay.origin[r.location]
                let end = hay.origin[r.location + r.length - 1] + 1
                return NSRange(location: start, length: end - start)
            }
        }
    }

    /// The match nearest `near` among the matches in each page (by index).
    static func nearest(pageCount: Int, near: TextSpan?, matches: (Int) -> [NSRange]) -> TextSpan? {
        var best: (span: TextSpan, distance: Int)?
        for p in 0..<pageCount {
            for found in matches(p) {
                let pageValue: Int? = pageCount == 1 && near?.page == nil ? nil : p
                let span = TextSpan(page: pageValue, start: found.location, length: found.length)
                let d = abs((p - (near?.page ?? 0)) * 1_000_000) + abs(found.location - (near?.start ?? 0))
                if best == nil || d < best!.distance { best = (span, d) }
            }
        }
        return best?.span
    }

    /// Every occurrence of `needle` in `ns`.
    static func occurrences(of needle: String, in ns: NSString) -> [NSRange] {
        var result: [NSRange] = []
        var range = NSRange(location: 0, length: ns.length)
        while range.length > 0 {
            let found = ns.range(of: needle, options: [], range: range)
            if found.location == NSNotFound { break }
            result.append(found)
            let next = found.location + max(1, found.length)
            if next >= ns.length { break }
            range = NSRange(location: next, length: ns.length - next)
        }
        return result
    }

    /// `text` with each run of white space as one space, and for each UTF-16
    /// unit of the result, its offset in `text`.
    static func squeeze(_ text: String) -> (text: String, origin: [Int]) {
        let units = Array(text.utf16)
        var out: [UInt16] = []
        var origin: [Int] = []
        out.reserveCapacity(units.count)
        origin.reserveCapacity(units.count)
        var inSpace = false
        for (i, u) in units.enumerated() {
            if isSpace(u) {
                if !inSpace {
                    out.append(0x20)
                    origin.append(i)
                }
                inSpace = true
            } else {
                out.append(u)
                origin.append(i)
                inSpace = false
            }
        }
        return (String(decoding: out, as: UTF16.self), origin)
    }

    static func isSpace(_ u: UInt16) -> Bool {
        guard let scalar = Unicode.Scalar(u) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}

/// The pages with white space squeezed (`Anchoring.squeeze`), worked out
/// once, when first needed, for all the selections checked against them.
final class SqueezedPages {
    let pages: [String]
    private var cache: [(text: String, origin: [Int])]?

    init(_ pages: [String]) { self.pages = pages }

    var value: [(text: String, origin: [Int])] {
        if let cache { return cache }
        let made = pages.map { Anchoring.squeeze($0) }
        cache = made
        return made
    }
}

/// The text currently at a selection's spans.
struct TextAnchorQuote {
    var fits: Bool
    var text: String

    init(spans: [TextSpan], pages: [String]) {
        var ok = true
        for s in spans {
            let p = s.page ?? 0
            if p >= pages.count || s.end > (pages[p] as NSString).length { ok = false }
        }
        fits = ok
        text = ok ? TextNormaliser.quote(spans, pages: pages) : ""
    }
}

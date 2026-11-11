import Foundation

/// Read-only access to the full-texts folder. There is deliberately no
/// way to write through this type: full-texts and consent forms are only
/// ever read (docs/DESIGN.md §Data security).
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
        let current = TextAnchorQuote(spans: selection.spans, pages: pages)
        let quote = selection.quote
        if quote.isEmpty {
            // Without a quote, a selection is kept if it still fits.
            return current.fits ? .unchanged : .lost
        }
        if current.fits, current.text == quote { return .unchanged }
        // Look for the quote: in a single page (or the text), nearest the
        // old position.
        let near = selection.first
        var best: (span: TextSpan, distance: Int)?
        for (p, page) in pages.enumerated() {
            let ns = page as NSString
            var range = NSRange(location: 0, length: ns.length)
            while true {
                let found = ns.range(of: quote, options: [], range: range)
                if found.location == NSNotFound { break }
                let pageValue: Int? = pages.count == 1 && near?.page == nil ? nil : p
                let span = TextSpan(page: pageValue, start: found.location, length: found.length)
                let d = abs((p - (near?.page ?? 0)) * 1_000_000) + abs(found.location - (near?.start ?? 0))
                if best == nil || d < best!.distance { best = (span, d) }
                let next = found.location + max(1, found.length)
                if next >= ns.length { break }
                range = NSRange(location: next, length: ns.length - next)
            }
        }
        if let best { return .moved([best.span]) }
        return .lost
    }

    /// Checks every selection of `file` in every layer against the file's
    /// current text, moving those that moved. Returns how many moved and the
    /// keys of those that could not be found.
    @discardableResult
    public static func reanchor(_ project: inout Project, file: String, pages: [String]) -> (moved: Int, lost: [String]) {
        var moved = 0
        var lost: [String] = []
        for li in project.layers.indices {
            guard var list = project.layers[li].selections[file] else { continue }
            for i in list.indices {
                switch locate(list[i], in: pages) {
                case .unchanged: break
                case .moved(let spans):
                    list[i].spans = spans
                    moved += 1
                case .lost:
                    lost.append(list[i].key)
                }
            }
            project.layers[li].selections[file] = list.sorted(by: Project.selectionOrder)
        }
        return (moved, lost)
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

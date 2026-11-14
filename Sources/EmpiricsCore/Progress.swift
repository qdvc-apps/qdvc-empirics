import Foundation

// Time indicators in transcripts ("[~5 min]") and how far a file's coding
// has come in a layer.

// MARK: - Time indicators

/// Rough time marks a transcriber leaves in the text, such as "[~5 min]",
/// "[~20 min]", "[5 mins]", "[~1.5 h]" or "[~2–3 min]". They aren't what
/// anyone said, so they are ignored for coding: trimmed from the ends of a
/// new selection, left out of a file's coding progress, and shown faint.
public enum TimeIndicators {
    static let expression: NSRegularExpression = {
        let number = #"\d+(?:[.,]\d+)?"#
        let unit = #"(?:s|secs?|seconds?|m|mins?|minutes?|h|hrs?|hours?)\.?"#
        let pattern = #"\[\s*~?\s*"# + number + #"(?:\s*[-–]\s*~?\s*"# + number + #")?\s*"# + unit + #"\s*\]"#
        return try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    /// Where the time indicators are in a text (UTF-16 ranges).
    public static func ranges(in text: String) -> [NSRange] {
        let ns = text as NSString
        return expression.matches(in: text, range: NSRange(location: 0, length: ns.length)).map(\.range)
    }

    /// The time indicators of a file: one span per indicator, on its page
    /// (`pages` is a text file's text as its only page, with `pdf` false).
    public static func spans(in pages: [String], pdf: Bool) -> [TextSpan] {
        pages.enumerated().flatMap { i, text in
            ranges(in: text).map { TextSpan(page: pdf ? i : nil, start: $0.location, length: $0.length) }
        }
    }

    /// `spans` without time indicators (or white space) at their starts and
    /// ends; spans left with nothing are dropped.
    public static func trim(_ spans: [TextSpan], pages: [String]) -> [TextSpan] {
        spans.compactMap { span in
            let page = span.page ?? 0
            guard page < pages.count else { return span }
            let ns = pages[page] as NSString
            guard span.start >= 0, span.end <= ns.length else { return span }
            let marks = ranges(in: pages[page])
            var a = span.start, b = span.end
            var changed = true
            while changed && a < b {
                changed = false
                while a < b, isSpace(ns.character(at: a)) { a += 1; changed = true }
                while b > a, isSpace(ns.character(at: b - 1)) { b -= 1; changed = true }
                if let m = marks.first(where: { $0.location <= a && NSMaxRange($0) > a }) {
                    a = min(b, NSMaxRange(m))
                    changed = true
                }
                if let m = marks.first(where: { $0.location < b && NSMaxRange($0) >= b }) {
                    b = max(a, m.location)
                    changed = true
                }
            }
            return b > a ? TextSpan(page: span.page, start: a, length: b - a) : nil
        }
    }

    static func isSpace(_ u: UInt16) -> Bool {
        guard let scalar = UnicodeScalar(u) else { return false }
        return CharacterSet.whitespacesAndNewlines.contains(scalar)
    }
}

// MARK: - Coding progress

/// How much of a file's text is coded, irrelevant or still to do, in one
/// layer, counted in characters that aren't white space, leaving out time
/// indicators (and anything else the caller ignores, such as speaker header
/// lines). Coded text is covered by a selection that is evidence for a code
/// (open codes on an inductive layer, a priori codes on a deductive one) or
/// is a protocol segment; a highlight without a code is still to do.
public struct CodingProgress: Equatable {
    public var coded: Int
    public var irrelevant: Int
    public var pending: Int

    public init(coded: Int = 0, irrelevant: Int = 0, pending: Int = 0) {
        self.coded = coded
        self.irrelevant = irrelevant
        self.pending = pending
    }

    public var total: Int { coded + irrelevant + pending }

    /// A part as a fraction of the total (0 for an empty file).
    public func fraction(_ part: Int) -> Double { total == 0 ? 0 : Double(part) / Double(total) }

    /// `pages` is the file's text (one page for a text file); `ignoring`,
    /// further spans to leave out (speaker headers).
    public static func of(_ project: Project, layer layerKey: String, file: String, pages: [String],
                          ignoring: [TextSpan] = []) -> CodingProgress {
        guard let layer = project.layer(layerKey), let f = project.files[file] else { return CodingProgress() }
        let pdf = f.kind == .pdf
        // Per page, each UTF-16 unit: 0 not counted, 1 pending, 2 irrelevant, 3 coded.
        var state: [[UInt8]] = pages.map { text in
            let ns = text as NSString
            return (0..<ns.length).map { TimeIndicators.isSpace(ns.character(at: $0)) ? 0 : 1 }
        }
        func clear(_ span: TextSpan) {
            let p = pdf ? (span.page ?? -1) : 0
            guard p >= 0, p < state.count else { return }
            let lo = max(0, span.start), hi = min(state[p].count, span.end)
            if lo < hi { for i in lo..<hi { state[p][i] = 0 } }
        }
        func mark(_ span: TextSpan, _ value: UInt8) {
            let p = pdf ? (span.page ?? -1) : 0
            guard p >= 0, p < state.count else { return }
            let lo = max(0, span.start), hi = min(state[p].count, span.end)
            guard lo < hi else { return }
            for i in lo..<hi where state[p][i] != 0 { state[p][i] = max(state[p][i], value) }
        }
        for span in TimeIndicators.spans(in: pages, pdf: pdf) + ignoring { clear(span) }
        let evidence: Set<String> = layer.isDeductive
            ? Set(layer.aprioriEvidence.values.flatMap { $0.map(\.target) })
            : Set(layer.codes.values.filter { $0.kind == .open }.flatMap { $0.evidence.map(\.target) })
        for s in layer.selections[file] ?? [] {
            if s.irrelevant {
                for span in s.spans { mark(span, 2) }
            } else if s.segment != nil || evidence.contains(s.key) {
                for span in s.spans { mark(span, 3) }
            }
        }
        var result = CodingProgress()
        for page in state {
            for v in page {
                switch v {
                case 1: result.pending += 1
                case 2: result.irrelevant += 1
                case 3: result.coded += 1
                default: break
                }
            }
        }
        return result
    }
}

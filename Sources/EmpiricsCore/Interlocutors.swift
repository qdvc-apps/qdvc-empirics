import Foundation

/// A conversational turn in a transcript: who (the label as written in its
/// header line) and the text they said.
public struct Turn: Equatable {
    /// The label as written ("ALICE BOB:" gives "ALICE BOB").
    public var label: String
    /// `TurnDetector.normalise(label)`.
    public var speaker: String
    /// The header line (or, for "Name: text" on one line, the name and colon).
    public var header: TextSpan
    /// What was said, trimmed of surrounding blank lines and spaces.
    public var body: TextSpan

    public init(label: String, speaker: String, header: TextSpan, body: TextSpan) {
        self.label = label
        self.speaker = speaker
        self.header = header
        self.body = body
    }
}

/// A label that looks like a speaker header, and how often it appears.
public struct SpeakerCandidate: Equatable {
    /// As first written, without the colon.
    public var label: String
    public var speaker: String
    public var count: Int
    /// Written at least once as "Name:", which makes a header likely.
    public var withColon: Bool

    public init(label: String, speaker: String, count: Int, withColon: Bool) {
        self.label = label
        self.speaker = speaker
        self.count = count
        self.withColon = withColon
    }
}

/// Finds conversational turns from simple header lines, forgiving the
/// inconsistencies of real transcripts:
///
///     Alice Bob                 a name alone on a line
///     John Smith:               …with a colon
///     ALICE BOB:                …in another case
///     John Smith                …followed by a blank line
///     JS: Well, I think…        a name and colon starting the line
///     [00:01:23] Alice Bob:     a timestamp first
///     **John Smith:**           Markdown emphasis
///
/// A header is a line of one to five words that starts with a letter, has
/// no sentence punctuation at the end, and is at most 48 characters. Labels
/// compare without case, extra spaces or the colon.
public enum TurnDetector {
    static let maxWords = 5
    static let maxLength = 48

    /// The label in comparable form: lowercased, spaces collapsed, no colon
    /// or emphasis marks.
    public static func normalise(_ label: String) -> String {
        var s = label.trimmingCharacters(in: .whitespaces)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: "*_:"))
        return s.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// A line read as a possible header: the label, whether it had a colon,
    /// and where any text after the colon starts (offset within the line).
    struct HeaderLine {
        var label: String
        var colon: Bool
        /// Offset (UTF-16, within the line) of text following "Name:", if any.
        var inlineStart: Int?
    }

    /// Reads one line (without its newline) as a header, if it can be one.
    static func header(_ line: String) -> HeaderLine? {
        let ns = line as NSString
        var i = 0
        let n = ns.length
        func skipSpaces() { while i < n, CharacterSet.whitespaces.contains(UnicodeScalar(ns.character(at: i)) ?? " ") { i += 1 } }
        skipSpaces()
        // A leading timestamp: [00:01:23], (1:02), 00:01:23 -
        if i < n, let m = timestamp.firstMatch(in: line, range: NSRange(location: i, length: n - i)), m.range.location == i {
            i = m.range.location + m.range.length
            skipSpaces()
        }
        // Markdown emphasis before the name.
        while i < n, ns.character(at: i) == 42 || ns.character(at: i) == 95 { i += 1 }   // * _
        let nameStart = i
        // The name runs to a colon or the end of the line.
        var colonAt: Int?
        var j = i
        while j < n {
            let c = ns.character(at: j)
            if c == 58 { colonAt = j; break }   // :
            j += 1
        }
        let nameEnd = colonAt ?? n
        var name = ns.substring(with: NSRange(location: nameStart, length: nameEnd - nameStart))
        name = name.trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "*_")))
        guard isName(name) else { return nil }
        var inline: Int?
        if let colonAt {
            var k = colonAt + 1
            while k < n, ns.character(at: k) == 42 || ns.character(at: k) == 95 { k += 1 }   // "**Name:**"
            while k < n, CharacterSet.whitespaces.contains(UnicodeScalar(ns.character(at: k)) ?? " ") { k += 1 }
            if k < n {
                // "Name: text". A timestamp-like "10:30" is not a header.
                if let first = UnicodeScalar(ns.character(at: k)), CharacterSet.decimalDigits.contains(first),
                   name.last.map({ $0.isNumber }) == true { return nil }
                inline = k
            }
        }
        return HeaderLine(label: name, colon: colonAt != nil, inlineStart: inline)
    }

    static let timestamp: NSRegularExpression = {
        // swiftlint:disable:next force_try
        try! NSRegularExpression(pattern: #"[\[\(]?\d{1,2}:\d{2}(:\d{2})?(\.\d+)?[\]\)]?\s*[-–]?"#)
    }()

    static func isName(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= maxLength, let first = name.first, first.isLetter else { return false }
        if let last = name.last, ".?!,;…\"”'’)".contains(last) {
            // "Dr." or "J." as the only word is not a name either.
            return false
        }
        let words = name.split(whereSeparator: { $0.isWhitespace })
        guard (1...maxWords).contains(words.count) else { return false }
        for w in words {
            guard w.allSatisfy({ $0.isLetter || $0.isNumber || "'’-.()#".contains($0) }) else { return false }
        }
        return true
    }

    /// Lines with their UTF-16 ranges, without the newline.
    static func lines(_ text: String) -> [(String, NSRange)] {
        let ns = text as NSString
        var result: [(String, NSRange)] = []
        var start = 0
        let n = ns.length
        while start <= n {
            var end = start
            while end < n, ns.character(at: end) != 10 { end += 1 }
            let r = NSRange(location: start, length: end - start)
            result.append((ns.substring(with: r), r))
            if end >= n { break }
            start = end + 1
        }
        return result
    }

    /// Labels that look like speaker headers. A label counts if it appears
    /// as a header at least twice, or at least once alone on its line with a
    /// colon ("John Smith:").
    public static func candidates(in text: String) -> [SpeakerCandidate] {
        var order: [String] = []
        var found: [String: SpeakerCandidate] = [:]
        var standaloneColon: Set<String> = []
        for (line, _) in lines(text) {
            guard let h = header(line) else { continue }
            // Plain sentences without a colon ("Okay") must stand alone.
            if !h.colon && h.inlineStart != nil { continue }
            let key = normalise(h.label)
            guard !key.isEmpty else { continue }
            if found[key] == nil {
                order.append(key)
                found[key] = SpeakerCandidate(label: h.label, speaker: key, count: 0, withColon: false)
            }
            found[key]!.count += 1
            if h.colon { found[key]!.withColon = true }
            if h.colon && h.inlineStart == nil { standaloneColon.insert(key) }
        }
        return order.compactMap { k in
            guard let c = found[k], c.count >= 2 || standaloneColon.contains(k) else { return nil }
            return c
        }
    }

    /// The turns in `text`, for the given speakers (normalised labels). A
    /// turn runs from its header to the next header; text before the first
    /// header belongs to no one.
    public static func turns(in text: String, speakers: Set<String>) -> [Turn] {
        guard !speakers.isEmpty else { return [] }
        let ns = text as NSString
        var heads: [(label: String, speaker: String, header: NSRange, bodyStart: Int)] = []
        for (line, range) in lines(text) {
            guard let h = header(line) else { continue }
            let key = normalise(h.label)
            guard speakers.contains(key) else { continue }
            if let inline = h.inlineStart {
                heads.append((h.label, key, NSRange(location: range.location, length: inline), range.location + inline))
            } else {
                heads.append((h.label, key, range, min(ns.length, range.location + range.length + 1)))
            }
        }
        var turns: [Turn] = []
        for (i, h) in heads.enumerated() {
            let end = i + 1 < heads.count ? heads[i + 1].header.location : ns.length
            var a = h.bodyStart, b = end
            while a < b, let u = UnicodeScalar(ns.character(at: a)), CharacterSet.whitespacesAndNewlines.contains(u) { a += 1 }
            while b > a, let u = UnicodeScalar(ns.character(at: b - 1)), CharacterSet.whitespacesAndNewlines.contains(u) { b -= 1 }
            turns.append(Turn(label: h.label, speaker: h.speaker,
                              header: TextSpan(start: h.header.location, length: h.header.length),
                              body: TextSpan(start: a, length: b - a)))
        }
        return turns
    }

    /// The person a label most likely stands for: a researcher or
    /// interviewee whose full name (either order) or unique first name
    /// matches it.
    public static func suggest(_ label: String, researchers: [Researcher], interviewees: [Interviewee]) -> String? {
        let n = normalise(label)
        var people: [(key: String, first: String, last: String)] = researchers.map { ($0.key, $0.firstName, $0.lastName) }
        people += interviewees.map { ($0.key, $0.firstName, $0.lastName) }
        for p in people {
            let full = normalise("\(p.first) \(p.last)"), reversed = normalise("\(p.last) \(p.first)")
            if n == full || n == reversed || n == normalise("\(p.last), \(p.first)") { return p.key }
        }
        let byFirst = people.filter { !$0.first.isEmpty && normalise($0.first) == n }
        if byFirst.count == 1 { return byFirst[0].key }
        return nil
    }

    /// The turn containing `offset`, if any.
    public static func turn(at offset: Int, in turns: [Turn]) -> Turn? {
        // Turns are in order; binary search on header start.
        var lo = 0, hi = turns.count - 1, found: Int?
        while lo <= hi {
            let mid = (lo + hi) / 2
            if turns[mid].header.start <= offset { found = mid; lo = mid + 1 } else { hi = mid - 1 }
        }
        return found.map { turns[$0] }
    }
}

extension SpeakerMap {
    /// Normalised labels that are speakers: assigned to a person, or found
    /// as candidates and not marked as no speaker.
    public func speakers(candidates: [SpeakerCandidate]) -> Set<String> {
        var result = Set(assignments.map { TurnDetector.normalise($0.label) })
        let ignore = Set(ignored.map(TurnDetector.normalise))
        for c in candidates where !ignore.contains(c.speaker) { result.insert(c.speaker) }
        return result
    }
}

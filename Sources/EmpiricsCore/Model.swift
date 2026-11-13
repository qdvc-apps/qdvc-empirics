import Foundation

// The project model. Every entity has a stable key (a prefix, a hyphen and
// eight hex digits) that never changes, so renaming anything touches one
// file, and cross-links (evidence, interrelations, attribute sheets) survive.
// See docs/FILE_FORMAT.md for how each type is written.
//
// A project's layers are each deductive or inductive. Protocols and a priori
// codes are defined once for the project and applied on deductive layers
// (protocol segments; a priori code evidence; Framework Matrix summaries);
// open and theorising codes live in an inductive layer. Interviewees and
// attribute sheets belong to the project.
//
// Names are chosen not to clash with SwiftUI, AppKit or Foundation (the app
// imports all of them): `EmpiricalFile`, `CodingLayer`, `TextSpan`,
// `CodeSelection`, `QDACode`, `AttributeSheet`, `AttributeSheetQuestion`,
// `StudyProtocol` (Objective-C has a `Protocol` class), `AprioriCode`.

public enum Keys {
    /// A new key such as "s-1a2b3c4d", not in `existing`.
    public static func make(_ prefix: String, avoiding existing: Set<String> = []) -> String {
        while true {
            let n = next()
            let key = "\(prefix)-" + String(format: "%08x", n)
            if !existing.contains(key) { return key }
        }
    }

    /// Where key digits come from; tests (the sample generator) replace it
    /// with a repeatable sequence.
    nonisolated(unsafe) static var source: () -> UInt32 = {
        var rng = SystemRandomNumberGenerator()
        return UInt32.random(in: 0...UInt32.max, using: &rng)
    }

    static func next() -> UInt32 { source() }

    public static let project = "p"
    public static let file = "f"
    public static let layer = "l"
    public static let selection = "s"
    public static let code = "c"
    public static let attributeSheet = "ast"
    public static let question = "q"
    public static let studyProtocol = "pr"
    public static let protocolItem = "pi"
    public static let aprioriCode = "apc"
    public static let link = "ln"
    public static let interrelation = "x"
    public static let researcher = "r"
    public static let interviewee = "i"

    /// True if `key` looks like a key with this prefix ("s-1a2b3c4d").
    public static func has(_ key: String, prefix: String) -> Bool {
        key.hasPrefix(prefix + "-") && key.count == prefix.count + 9
    }
}

/// Today's date as YYYY-MM-DD, and timestamps as ISO 8601 (UTC), as written
/// in the workspace.
public enum Stamp {
    public static func now(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.string(from: date)
    }

    public static func day(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    /// Parses YYYY-MM-DD (local midnight); nil for anything else.
    public static func parseDay(_ s: String) -> Date? {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s.trimmingCharacters(in: .whitespaces))
    }
}

// MARK: - Empirical files

public enum FileKind: String, CaseIterable, Codable {
    case text
    case markdown
    case pdf

    /// The kind for a file name's extension, or nil if not supported.
    public static func forPath(_ path: String) -> FileKind? {
        switch (path as NSString).pathExtension.lowercased() {
        case "txt", "text": return .text
        case "md", "markdown", "mdown", "mkd": return .markdown
        case "pdf": return .pdf
        default: return nil
        }
    }

    public var label: String {
        switch self {
        case .text: return "Plain text"
        case .markdown: return "Markdown"
        case .pdf: return "PDF"
        }
    }

    /// Text and Markdown are coded as text; PDFs on their pages.
    public var isText: Bool { self != .pdf }
}

public enum CodingStatus: String, CaseIterable, Codable {
    case notStarted = "not-started"
    case inProgress = "in-progress"
    case coded

    public var label: String {
        switch self {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .coded: return "Coded"
        }
    }
}

/// A catalogue entry for a full-text: where it is in the full-texts folder,
/// and the researcher's own title, date and ID for it. The text itself is
/// never in the workspace.
public struct EmpiricalFile: Identifiable, Equatable {
    public var key: String
    /// Relative to the full-texts folder, with "/" separators.
    public var path: String
    public var kind: FileKind
    public var title: String
    /// YYYY-MM-DD (date of interview, of publication…), or empty.
    public var date: String
    /// The researcher's own identifier, such as SF-2026-KXV-01.
    public var customID: String
    public var status: CodingStatus
    /// "sha256:<hex>" of the file's bytes when it was last checked.
    public var fingerprint: String
    /// Attribute sheets associated with this file.
    public var attributeSheets: [String]
    public var added: String
    /// PDFs: pages shown rotated (zero-based page → 90, 180 or 270 degrees
    /// clockwise, on top of the page's own rotation). Only how the page is
    /// shown: the PDF itself is never changed.
    public var rotations: [Int: Int]

    public var id: String { key }

    public init(key: String, path: String, kind: FileKind, title: String = "", date: String = "",
                customID: String = "", status: CodingStatus = .notStarted, fingerprint: String = "",
                attributeSheets: [String] = [], added: String = "", rotations: [Int: Int] = [:]) {
        self.key = key
        self.path = path
        self.kind = kind
        self.title = title
        self.date = date
        self.customID = customID
        self.status = status
        self.fingerprint = fingerprint
        self.attributeSheets = attributeSheets
        self.added = added
        self.rotations = rotations
    }

    /// The title, or the file name without its extension.
    public var displayTitle: String {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !t.isEmpty { return t }
        return ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    public var fileName: String { (path as NSString).lastPathComponent }
}

// MARK: - Selections

/// A run of text: UTF-16 offsets (the units of NSString) into a text file's
/// normalised text (line endings as \n, no byte-order mark), or into one
/// PDF page's text (`page`, zero-based in the model, one-based in YAML).
public struct TextSpan: Equatable, Hashable, Comparable {
    public var page: Int?
    public var start: Int
    public var length: Int

    public init(page: Int? = nil, start: Int, length: Int) {
        self.page = page
        self.start = start
        self.length = length
    }

    public var end: Int { start + length }

    public func overlaps(_ other: TextSpan) -> Bool {
        page == other.page && start < other.end && other.start < end
    }

    /// Overlapping or touching (for merging).
    public func touches(_ other: TextSpan) -> Bool {
        page == other.page && start <= other.end && other.start <= end
    }

    public func contains(page p: Int?, offset: Int) -> Bool {
        page == p && offset >= start && offset < end
    }

    public static func < (a: TextSpan, b: TextSpan) -> Bool {
        let pa = a.page ?? -1, pb = b.page ?? -1
        if pa != pb { return pa < pb }
        if a.start != b.start { return a.start < b.start }
        return a.length < b.length
    }

    /// Sorted, with overlapping and touching spans joined.
    public static func normalised(_ spans: [TextSpan]) -> [TextSpan] {
        var result: [TextSpan] = []
        for s in spans.filter({ $0.length > 0 }).sorted() {
            if let last = result.last, last.touches(s) {
                let end = max(last.end, s.end)
                result[result.count - 1] = TextSpan(page: last.page, start: last.start, length: end - last.start)
            } else {
                result.append(s)
            }
        }
        return result
    }
}

/// Which part of a protocol item a protocol segment is: where the item's
/// prompt (the question asked, the heading) is in the text, or where its
/// response is.
public enum ProtocolPart: String, CaseIterable, Codable {
    case prompt
    case response

    public var label: String { self == .prompt ? "Prompt" : "Response" }
}

/// Marks a selection on a deductive layer as a protocol segment: the prompt
/// or the response of one item of the file's protocol in that layer.
public struct ProtocolSegment: Equatable, Hashable {
    /// A protocol item key.
    public var item: String
    public var part: ProtocolPart

    public init(item: String, part: ProtocolPart) {
        self.item = item
        self.part = part
    }
}

/// A highlighted portion of a file, in one layer. On an inductive layer it
/// may be evidence for open codes; on a deductive layer, evidence for a
/// priori codes, or a protocol segment (never both); on either, it may be
/// marked irrelevant instead.
public struct CodeSelection: Identifiable, Equatable {
    public var key: String
    public var fileKey: String
    /// One span for text files; one per page for a selection across PDF
    /// pages. Always sorted.
    public var spans: [TextSpan]
    /// The selected text, when the project stores quotes; used to find the
    /// selection again if the full-text changes.
    public var quote: String
    public var irrelevant: Bool
    /// Set for a protocol segment (deductive layers only).
    public var segment: ProtocolSegment?
    /// The researcher who made it (a researcher key), if known.
    public var by: String
    public var created: String

    public var id: String { key }

    public init(key: String, fileKey: String, spans: [TextSpan], quote: String = "", irrelevant: Bool = false,
                segment: ProtocolSegment? = nil, by: String = "", created: String = "") {
        self.key = key
        self.fileKey = fileKey
        self.spans = spans.sorted()
        self.quote = quote
        self.irrelevant = irrelevant
        self.segment = segment
        self.by = by
        self.created = created
    }

    public var first: TextSpan? { spans.first }

    public func overlaps(_ other: CodeSelection) -> Bool {
        spans.contains { a in other.spans.contains { a.overlaps($0) } }
    }

    public func overlaps(_ others: [TextSpan]) -> Bool {
        spans.contains { a in others.contains { a.overlaps($0) } }
    }

    public func contains(page: Int?, offset: Int) -> Bool {
        spans.contains { $0.contains(page: page, offset: offset) }
    }

    /// Total length, for choosing the innermost of overlapping selections.
    public var totalLength: Int { spans.reduce(0) { $0 + $1.length } }
}

// MARK: - Codes

public enum CodeKind: String, CaseIterable, Codable {
    /// Evidenced directly by selections.
    case open
    /// Evidenced by open codes and other theorising codes.
    case theorising

    public var label: String { self == .open ? "Open Code" : "Theorising Code" }
}

/// One piece of evidence for a code, with the researcher's interpretation
/// memo: why this selection (or code) is evidence for the code.
public struct Evidence: Equatable, Hashable {
    /// A selection key (open codes) or a code key (theorising codes).
    public var target: String
    public var memo: String

    public init(target: String, memo: String = "") {
        self.target = target
        self.memo = memo
    }
}

/// The researcher's commentary on how two or more of a code's evidence
/// items relate (compare, contrast…).
public struct Interrelation: Identifiable, Equatable {
    public var key: String
    public var type: String
    /// Evidence targets of the code (selections or codes).
    public var members: [String]
    public var description: String

    public var id: String { key }

    public init(key: String, type: String, members: [String], description: String = "") {
        self.key = key
        self.type = type
        self.members = members
        self.description = description
    }
}

public struct QDACode: Identifiable, Equatable {
    public var key: String
    public var kind: CodeKind
    public var name: String
    public var description: String
    /// "#RRGGBB".
    public var colour: String
    public var evidence: [Evidence]
    public var comments: [String]
    /// Unresolved matters, from an interpretive point of view.
    public var questions: [String]
    public var interrelations: [Interrelation]
    /// Links to a priori codes.
    public var links: [CodeLink]
    public var attributeSheets: [String]
    public var by: String
    public var created: String

    public var id: String { key }

    public init(key: String, kind: CodeKind, name: String, description: String = "", colour: String = "",
                evidence: [Evidence] = [], comments: [String] = [], questions: [String] = [],
                interrelations: [Interrelation] = [], links: [CodeLink] = [], attributeSheets: [String] = [],
                by: String = "", created: String = "") {
        self.key = key
        self.kind = kind
        self.name = name
        self.description = description
        self.colour = colour
        self.evidence = evidence
        self.comments = comments
        self.questions = questions
        self.interrelations = interrelations
        self.links = links
        self.attributeSheets = attributeSheets
        self.by = by
        self.created = created
    }

    public func hasEvidence(_ target: String) -> Bool { evidence.contains { $0.target == target } }

    public func memo(for target: String) -> String { evidence.first { $0.target == target }?.memo ?? "" }
}

/// How an open or theorising code bears on an a priori code: where what emerged
/// from the data meets what was defined beforehand.
public enum LinkType: String, CaseIterable, Codable {
    case confirms
    case refines
    case extends
    case contradicts
    case notCovered = "not-covered"

    public var label: String {
        switch self {
        case .confirms: return "Confirms"
        case .refines: return "Refines"
        case .extends: return "Extends"
        case .contradicts: return "Contradicts"
        case .notCovered: return "Not Covered"
        }
    }
}

/// A link from an open or theorising code to an a priori code, with the
/// researcher's memo on it.
public struct CodeLink: Identifiable, Equatable {
    public var key: String
    /// An a priori code key.
    public var aprioriCode: String
    public var type: LinkType
    public var memo: String

    public var id: String { key }

    public init(key: String, aprioriCode: String, type: LinkType, memo: String = "") {
        self.key = key
        self.aprioriCode = aprioriCode
        self.type = type
        self.memo = memo
    }
}

/// Highlight colours offered for codes, in the order new codes take them.
public enum CodePalette {
    public static let colours = [
        "#F2C14E", "#5BC0EB", "#9BC53D", "#E55934", "#B07CC6", "#FA7921",
        "#4ECDC4", "#F78FB3", "#7E9CD8", "#C3A46C", "#58B368", "#D96C6C",
    ]

    /// The next colour for a new code: the least used, in palette order.
    public static func next(used: [String]) -> String {
        var counts: [String: Int] = [:]
        for c in used { counts[c.uppercased(), default: 0] += 1 }
        return colours.min { (counts[$0] ?? 0) < (counts[$1] ?? 0) } ?? colours[0]
    }
}

// MARK: - Layers

/// Deductive layers apply what was defined beforehand (protocols, a priori
/// codes); inductive layers hold what emerges from the data (open and theorising
/// codes).
public enum LayerKind: String, CaseIterable, Codable {
    case deductive
    case inductive

    public var label: String { self == .deductive ? "Deductive" : "Inductive" }
}

/// A layer of interpretation (a theoretical lens, one researcher's reading):
/// its selections, and what they are evidence for, exist in it alone.
public struct CodingLayer: Identifiable, Equatable {
    public var key: String
    public var kind: LayerKind
    public var name: String
    public var description: String
    /// The researcher whose interpretation this is, if any.
    public var researcher: String
    /// Selections by file key, each list sorted by position.
    public var selections: [String: [CodeSelection]]
    /// Inductive layers: open and theorising codes.
    public var codes: [String: QDACode]
    /// Deductive layers: evidence (selections of this layer) for each a
    /// priori code, by a priori code key.
    public var aprioriEvidence: [String: [Evidence]]
    /// Deductive layers: the protocol each file follows here, by file key.
    public var protocols: [String: String]
    /// Deductive layers: Framework Matrix summaries, by row (a file or
    /// interviewee key), then column (an a priori code or protocol item key).
    public var framework: [String: [String: String]]

    public var id: String { key }

    public init(key: String, kind: LayerKind, name: String, description: String = "", researcher: String = "",
                selections: [String: [CodeSelection]] = [:], codes: [String: QDACode] = [:],
                aprioriEvidence: [String: [Evidence]] = [:], protocols: [String: String] = [:],
                framework: [String: [String: String]] = [:]) {
        self.key = key
        self.kind = kind
        self.name = name
        self.description = description
        self.researcher = researcher
        self.selections = selections
        self.codes = codes
        self.aprioriEvidence = aprioriEvidence
        self.protocols = protocols
        self.framework = framework
    }

    public var isDeductive: Bool { kind == .deductive }
    public var isInductive: Bool { kind == .inductive }

    /// The layer's own fields, without its contents (layer.yml).
    public var meta: CodingLayer {
        CodingLayer(key: key, kind: kind, name: name, description: description, researcher: researcher)
    }

    /// True if nothing has been coded in it (so its kind can still change).
    public var isEmpty: Bool {
        selections.isEmpty && codes.isEmpty && aprioriEvidence.isEmpty && protocols.isEmpty && framework.isEmpty
    }

    public var allSelections: [CodeSelection] {
        selections.keys.sorted().flatMap { selections[$0] ?? [] }
    }

    public func selection(_ key: String) -> CodeSelection? {
        for list in selections.values {
            if let s = list.first(where: { $0.key == key }) { return s }
        }
        return nil
    }

    public var selectionCount: Int { selections.values.reduce(0) { $0 + $1.count } }

    /// A priori codes a selection is evidence for, in this layer (by key).
    public func aprioriCodes(for selection: String) -> [String] {
        aprioriEvidence.filter { entry in entry.value.contains { $0.target == selection } }.map(\.key).sorted()
    }
}

// MARK: - Protocols

/// One item of a protocol: a question of an interview protocol, a section of
/// an article's structure. In a file it may have a prompt segment and a
/// response segment.
public struct ProtocolItem: Identifiable, Equatable {
    public var key: String
    /// Short, as shown in margins and column headings ("Q3", "Findings").
    public var label: String
    /// The full wording, if any.
    public var text: String

    public var id: String { key }

    public init(key: String, label: String, text: String = "") {
        self.key = key
        self.label = label
        self.text = text
    }
}

/// A predefined set of items (questions and answers, or more generally keys
/// and values) expected to occur, in part or in whole, in each empirical
/// file that follows it: an interview protocol, the structure of a research
/// article. On each deductive layer a file follows at most one protocol.
public struct StudyProtocol: Identifiable, Equatable {
    public var key: String
    public var title: String
    public var description: String
    /// A flat list, in order.
    public var items: [ProtocolItem]

    public var id: String { key }

    public init(key: String, title: String, description: String = "", items: [ProtocolItem] = []) {
        self.key = key
        self.title = title
        self.description = description
        self.items = items
    }

    public func item(_ key: String) -> ProtocolItem? { items.first { $0.key == key } }
}

// MARK: - A priori codes

/// A code defined before coding (from theory, literature or the research
/// questions), with its codebook entry, and applied on deductive layers.
public struct AprioriCode: Identifiable, Equatable {
    public var key: String
    public var name: String
    /// "#RRGGBB".
    public var colour: String
    public var definition: String
    /// What is included: when to use it.
    public var included: String
    /// What is excluded: when not to use it.
    public var excluded: String
    /// An ideal example.
    public var example: String
    /// A near miss: text that looks as if it fits but doesn't.
    public var counterExample: String
    /// Where the code comes from (theory, literature).
    public var source: String
    public var by: String
    public var created: String

    public var id: String { key }

    public init(key: String, name: String, colour: String = "", definition: String = "", included: String = "",
                excluded: String = "", example: String = "", counterExample: String = "", source: String = "",
                by: String = "", created: String = "") {
        self.key = key
        self.name = name
        self.colour = colour
        self.definition = definition
        self.included = included
        self.excluded = excluded
        self.example = example
        self.counterExample = counterExample
        self.source = source
        self.by = by
        self.created = created
    }
}

// MARK: - Attribute Sheets

public enum QuestionType: String, CaseIterable, Codable {
    case text
    case chooseOne = "choose-one"
    case chooseMany = "choose-many"

    public var label: String {
        switch self {
        case .text: return "Free Text"
        case .chooseOne: return "Choose One"
        case .chooseMany: return "Choose Any"
        }
    }

    public var usesOptions: Bool { self != .text }
}

public enum Requirement: String, CaseIterable, Codable {
    /// The response sheet cannot be saved without an answer.
    case blocking = "mandatory-blocking"
    /// Flagged until answered, but the sheet can be saved.
    case flagged = "mandatory-non-blocking"
    case optional

    public var label: String {
        switch self {
        case .blocking: return "Mandatory, Blocking"
        case .flagged: return "Mandatory, Non-blocking"
        case .optional: return "Optional"
        }
    }
}

public struct AttributeSheetQuestion: Identifiable, Equatable {
    public static let maxLabelLength = 16

    public var key: String
    /// At most 16 characters.
    public var label: String
    public var text: String
    public var type: QuestionType
    public var options: [String]
    /// If false, researchers may add options while coding.
    public var strict: Bool
    public var requirement: Requirement

    public var id: String { key }

    public init(key: String, label: String, text: String = "", type: QuestionType = .text, options: [String] = [],
                strict: Bool = false, requirement: Requirement = .optional) {
        self.key = key
        self.label = String(label.prefix(Self.maxLabelLength))
        self.text = text
        self.type = type
        self.options = options
        self.strict = strict
        self.requirement = requirement
    }
}

/// What an attribute sheet can be associated with.
public enum AttributeSheetTarget: String, CaseIterable, Codable, Hashable {
    case files
    case interviewees
    case openCodes = "open-codes"
    case theorisingCodes = "theorising-codes"

    public var label: String {
        switch self {
        case .files: return "Empirical Files"
        case .interviewees: return "Interviewees"
        case .openCodes: return "Open Codes"
        case .theorisingCodes: return "Theorising Codes"
        }
    }
}

public struct AttributeSheet: Identifiable, Equatable {
    public var key: String
    public var title: String
    public var description: String
    public var appliesTo: Set<AttributeSheetTarget>
    public var questions: [AttributeSheetQuestion]

    public var id: String { key }

    public init(key: String, title: String, description: String = "", appliesTo: Set<AttributeSheetTarget> = [.files],
                questions: [AttributeSheetQuestion] = []) {
        self.key = key
        self.title = title
        self.description = description
        self.appliesTo = appliesTo
        self.questions = questions
    }

    public func question(_ key: String) -> AttributeSheetQuestion? { questions.first { $0.key == key } }
}

public enum Answer: Equatable {
    case text(String)
    case one(String)
    case many([String])

    public var isEmpty: Bool {
        switch self {
        case .text(let s), .one(let s): return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .many(let list): return list.isEmpty
        }
    }

    public var values: [String] {
        switch self {
        case .text(let s), .one(let s): return s.isEmpty ? [] : [s]
        case .many(let list): return list
        }
    }

    public var summary: String { values.joined(separator: ", ") }
}

/// Identifies an attribute sheet response sheet: an attribute sheet, what it is about (a
/// file, code or interviewee key) and, when the project lists researchers, whose answers
/// these are.
public struct ResponseID: Hashable, Comparable {
    public var attributeSheet: String
    public var target: String
    public var researcher: String

    public init(attributeSheet: String, target: String, researcher: String = "") {
        self.attributeSheet = attributeSheet
        self.target = target
        self.researcher = researcher
    }

    /// responses/<attribute sheet>/<target>[--<researcher>].yml
    public var path: String {
        "\(Workspace.responsesFolder)/\(attributeSheet)/\(target)" + (researcher.isEmpty ? "" : "--\(researcher)") + ".yml"
    }

    public static func < (a: ResponseID, b: ResponseID) -> Bool {
        (a.attributeSheet, a.target, a.researcher) < (b.attributeSheet, b.target, b.researcher)
    }
}

public struct ResponseSheet: Equatable {
    public var id: ResponseID
    /// By question key.
    public var answers: [String: Answer]
    public var updated: String

    public init(id: ResponseID, answers: [String: Answer] = [:], updated: String = "") {
        self.id = id
        self.answers = answers
        self.updated = updated
    }
}

/// How complete a response sheet is against its attribute sheet.
public struct SheetCompleteness: Equatable {
    /// Mandatory, blocking questions without an answer: the sheet can't be
    /// saved.
    public var missingBlocking: [AttributeSheetQuestion]
    /// Mandatory, non-blocking questions without an answer: flagged.
    public var missingFlagged: [AttributeSheetQuestion]
    public var answered: Int
    public var total: Int

    public var canSave: Bool { missingBlocking.isEmpty }
    public var isComplete: Bool { missingBlocking.isEmpty && missingFlagged.isEmpty }

    public static func of(_ answers: [String: Answer], against attributeSheet: AttributeSheet) -> SheetCompleteness {
        var blocking: [AttributeSheetQuestion] = []
        var flagged: [AttributeSheetQuestion] = []
        var answered = 0
        for q in attributeSheet.questions {
            let empty = answers[q.key]?.isEmpty ?? true
            if !empty { answered += 1 }
            guard empty else { continue }
            switch q.requirement {
            case .blocking: blocking.append(q)
            case .flagged: flagged.append(q)
            case .optional: break
            }
        }
        return SheetCompleteness(missingBlocking: blocking, missingFlagged: flagged, answered: answered,
                                 total: attributeSheet.questions.count)
    }
}

// MARK: - People

/// A researcher. Names are pseudonyms (a real-name mapping file in the
/// full-texts folder can map keys to real names).
public struct Researcher: Identifiable, Equatable {
    public var key: String
    public var firstName: String
    public var lastName: String

    public var id: String { key }

    public init(key: String, firstName: String, lastName: String) {
        self.key = key
        self.firstName = firstName
        self.lastName = lastName
    }

    public var fullName: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

/// An interviewee. Names are pseudonyms (a real-name mapping file in the
/// full-texts folder can map keys to real names); the consent form is a PDF
/// in the full-texts folder (never in the workspace).
public struct Interviewee: Identifiable, Equatable {
    public var key: String
    public var firstName: String
    public var lastName: String
    /// Relative to the full-texts folder, or empty.
    public var consentForm: String
    /// Attribute sheets associated with this interviewee.
    public var attributeSheets: [String]

    public var id: String { key }

    public init(key: String, firstName: String, lastName: String, consentForm: String = "", attributeSheets: [String] = []) {
        self.key = key
        self.firstName = firstName
        self.lastName = lastName
        self.consentForm = consentForm
        self.attributeSheets = attributeSheets
    }

    public var fullName: String { [firstName, lastName].filter { !$0.isEmpty }.joined(separator: " ") }
}

// MARK: - Interlocutors

/// For one transcript: which person each speaker label stands for, and
/// which header-like labels are not speakers at all.
public struct SpeakerMap: Equatable {
    public var fileKey: String
    /// Normalised label → (label as first written, person key).
    public var assignments: [SpeakerAssignment]
    /// Normalised labels the researcher said are not speakers.
    public var ignored: [String]

    public init(fileKey: String, assignments: [SpeakerAssignment] = [], ignored: [String] = []) {
        self.fileKey = fileKey
        self.assignments = assignments
        self.ignored = ignored
    }

    public func person(for label: String) -> String? {
        let n = TurnDetector.normalise(label)
        return assignments.first { TurnDetector.normalise($0.label) == n }?.person
    }

    public var isEmpty: Bool { assignments.isEmpty && ignored.isEmpty }
}

public struct SpeakerAssignment: Equatable {
    public var label: String
    public var person: String

    public init(label: String, person: String) {
        self.label = label
        self.person = person
    }
}

// MARK: - Project

public struct ProjectSettings: Equatable {
    public var key: String
    public var title: String
    public var description: String
    /// Write each selection's text into the workspace (so the YAML is
    /// readable and selections can be found again if a file changes).
    public var storeQuotes: Bool
    public var interlocutorLayer: Bool
    public var interrelationTypes: [String]
    /// Real-name mapping files (CSV) for researchers and interviewees,
    /// relative to the full-texts folder; empty if not set up. The workspace
    /// holds only pseudonyms; real names never leave the full-texts folder.
    public var researcherNamesFile: String
    public var intervieweeNamesFile: String
    /// Attribute Sheet questions shown as columns in the tables of empirical files,
    /// interviewees, open codes and theorising codes: question keys, per table.
    public var tableColumns: [AttributeSheetTarget: [String]]
    /// How those tables' question columns are arranged (their order, and
    /// widths), per table: SwiftUI's column customization as JSON, which the
    /// app reads back as it wrote it. Which questions show is in
    /// `tableColumns`.
    public var tableLayouts: [AttributeSheetTarget: String]

    public static let defaultInterrelationTypes = ["Compare", "Contrast"]

    public init(key: String, title: String, description: String = "", storeQuotes: Bool = true,
                interlocutorLayer: Bool = false, interrelationTypes: [String] = ProjectSettings.defaultInterrelationTypes,
                researcherNamesFile: String = "", intervieweeNamesFile: String = "",
                tableColumns: [AttributeSheetTarget: [String]] = [:], tableLayouts: [AttributeSheetTarget: String] = [:]) {
        self.key = key
        self.title = title
        self.description = description
        self.storeQuotes = storeQuotes
        self.interlocutorLayer = interlocutorLayer
        self.interrelationTypes = interrelationTypes
        self.researcherNamesFile = researcherNamesFile
        self.intervieweeNamesFile = intervieweeNamesFile
        self.tableColumns = tableColumns
        self.tableLayouts = tableLayouts
    }
}

/// A whole project, as loaded from its workspace.
public struct Project: Equatable {
    public var settings: ProjectSettings
    public var files: [String: EmpiricalFile]
    /// In display order (project.yml lists the order).
    public var layers: [CodingLayer]
    public var protocols: [String: StudyProtocol]
    public var aprioriCodes: [String: AprioriCode]
    public var attributeSheets: [String: AttributeSheet]
    public var responses: [ResponseID: ResponseSheet]
    public var researchers: [Researcher]
    public var interviewees: [Interviewee]
    public var speakerMaps: [String: SpeakerMap]

    public init(settings: ProjectSettings, files: [String: EmpiricalFile] = [:], layers: [CodingLayer] = [],
                protocols: [String: StudyProtocol] = [:], aprioriCodes: [String: AprioriCode] = [:],
                attributeSheets: [String: AttributeSheet] = [:], responses: [ResponseID: ResponseSheet] = [:],
                researchers: [Researcher] = [], interviewees: [Interviewee] = [],
                speakerMaps: [String: SpeakerMap] = [:]) {
        self.settings = settings
        self.files = files
        self.layers = layers
        self.protocols = protocols
        self.aprioriCodes = aprioriCodes
        self.attributeSheets = attributeSheets
        self.responses = responses
        self.researchers = researchers
        self.interviewees = interviewees
        self.speakerMaps = speakerMaps
    }

    public static let mainDeductiveName = "Main Deductive"
    public static let mainInductiveName = "Main Inductive"

    /// A new project, with a deductive and an inductive layer.
    public static func new(title: String) -> Project {
        let settings = ProjectSettings(key: Keys.make(Keys.project), title: title)
        let d = Keys.make(Keys.layer)
        let i = Keys.make(Keys.layer, avoiding: [d])
        return Project(settings: settings, layers: [CodingLayer(key: d, kind: .deductive, name: mainDeductiveName),
                                                    CodingLayer(key: i, kind: .inductive, name: mainInductiveName)])
    }

    // MARK: Lookups

    public func layerIndex(_ key: String) -> Int? { layers.firstIndex { $0.key == key } }

    public func layer(_ key: String) -> CodingLayer? { layers.first { $0.key == key } }

    public var deductiveLayers: [CodingLayer] { layers.filter(\.isDeductive) }
    public var inductiveLayers: [CodingLayer] { layers.filter(\.isInductive) }

    /// The protocol item with this key, and its protocol's key.
    public func protocolItem(_ key: String) -> (protocolKey: String, item: ProtocolItem)? {
        for pr in protocols.values {
            if let item = pr.item(key) { return (pr.key, item) }
        }
        return nil
    }

    public var sortedProtocols: [StudyProtocol] {
        protocols.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public var sortedAprioriCodes: [AprioriCode] {
        aprioriCodes.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The layer holding a selection or code.
    public func layerKey(holding key: String) -> String? {
        for layer in layers {
            if layer.codes[key] != nil { return layer.key }
            if layer.selection(key) != nil { return layer.key }
        }
        return nil
    }

    public func code(_ key: String) -> QDACode? {
        for layer in layers { if let c = layer.codes[key] { return c } }
        return nil
    }

    public func selection(_ key: String) -> CodeSelection? {
        for layer in layers { if let s = layer.selection(key) { return s } }
        return nil
    }

    public var sortedFiles: [EmpiricalFile] {
        files.values.sorted { a, b in
            let x = a.customID.isEmpty ? a.displayTitle : a.customID
            let y = b.customID.isEmpty ? b.displayTitle : b.customID
            return x.localizedStandardCompare(y) == .orderedAscending
        }
    }

    public var sortedAttributeSheets: [AttributeSheet] {
        attributeSheets.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    public func researcher(_ key: String) -> Researcher? { researchers.first { $0.key == key } }

    public func interviewee(_ key: String) -> Interviewee? { interviewees.first { $0.key == key } }

    /// A person's display name (researcher or interviewee), or nil.
    public func personName(_ key: String) -> String? {
        researcher(key)?.fullName ?? interviewee(key)?.fullName
    }

    /// Every key in use, so new keys never collide.
    public var allKeys: Set<String> {
        var keys = Set<String>()
        keys.insert(settings.key)
        keys.formUnion(files.keys)
        for layer in layers {
            keys.insert(layer.key)
            keys.formUnion(layer.codes.keys)
            for c in layer.codes.values {
                keys.formUnion(c.interrelations.map(\.key))
                keys.formUnion(c.links.map(\.key))
            }
            for list in layer.selections.values { keys.formUnion(list.map(\.key)) }
        }
        keys.formUnion(protocols.keys)
        for pr in protocols.values { keys.formUnion(pr.items.map(\.key)) }
        keys.formUnion(aprioriCodes.keys)
        keys.formUnion(attributeSheets.keys)
        for cb in attributeSheets.values { keys.formUnion(cb.questions.map(\.key)) }
        keys.formUnion(researchers.map(\.key))
        keys.formUnion(interviewees.map(\.key))
        return keys
    }

    public func newKey(_ prefix: String) -> String { Keys.make(prefix, avoiding: allKeys) }
}

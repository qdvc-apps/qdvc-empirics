import Foundation

// The project model. Every entity has a stable key (a prefix, a hyphen and
// eight hex digits) that never changes, so renaming anything touches one
// file, and cross-links (evidence, interrelations, codebooks) survive.
// See docs/FILE_FORMAT.md for how each type is written.
//
// Names are chosen not to clash with SwiftUI, AppKit or Foundation (the app
// imports all of them): `EmpiricalFile`, `CodingLayer`, `TextSpan`,
// `CodeSelection`, `QDACode`, `Codebook`, `CodebookQuestion`.

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
    public static let codebook = "cb"
    public static let question = "q"
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
    /// Codebooks associated with this file.
    public var codebooks: [String]
    public var added: String

    public var id: String { key }

    public init(key: String, path: String, kind: FileKind, title: String = "", date: String = "",
                customID: String = "", status: CodingStatus = .notStarted, fingerprint: String = "",
                codebooks: [String] = [], added: String = "") {
        self.key = key
        self.path = path
        self.kind = kind
        self.title = title
        self.date = date
        self.customID = customID
        self.status = status
        self.fingerprint = fingerprint
        self.codebooks = codebooks
        self.added = added
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

/// A highlighted portion of a file, in one layer. It may be evidence for
/// open codes, or marked irrelevant (never both).
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
    /// The researcher who made it (a researcher key), if known.
    public var by: String
    public var created: String

    public var id: String { key }

    public init(key: String, fileKey: String, spans: [TextSpan], quote: String = "", irrelevant: Bool = false,
                by: String = "", created: String = "") {
        self.key = key
        self.fileKey = fileKey
        self.spans = spans.sorted()
        self.quote = quote
        self.irrelevant = irrelevant
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
    /// Evidenced by open codes and other axial codes.
    case axial

    public var label: String { self == .open ? "Open Code" : "Axial Code" }
}

/// One piece of evidence for a code, with the researcher's interpretation
/// memo: why this selection (or code) is evidence for the code.
public struct Evidence: Equatable, Hashable {
    /// A selection key (open codes) or a code key (axial codes).
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
    public var codebooks: [String]
    public var by: String
    public var created: String

    public var id: String { key }

    public init(key: String, kind: CodeKind, name: String, description: String = "", colour: String = "",
                evidence: [Evidence] = [], comments: [String] = [], questions: [String] = [],
                interrelations: [Interrelation] = [], codebooks: [String] = [], by: String = "", created: String = "") {
        self.key = key
        self.kind = kind
        self.name = name
        self.description = description
        self.colour = colour
        self.evidence = evidence
        self.comments = comments
        self.questions = questions
        self.interrelations = interrelations
        self.codebooks = codebooks
        self.by = by
        self.created = created
    }

    public func hasEvidence(_ target: String) -> Bool { evidence.contains { $0.target == target } }

    public func memo(for target: String) -> String { evidence.first { $0.target == target }?.memo ?? "" }
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

/// A layer of interpretation (a theoretical lens, one researcher's reading):
/// its selections and codes exist in it alone.
public struct CodingLayer: Identifiable, Equatable {
    public var key: String
    public var name: String
    public var description: String
    /// The researcher whose interpretation this is, if any.
    public var researcher: String
    /// Selections by file key, each list sorted by position.
    public var selections: [String: [CodeSelection]]
    public var codes: [String: QDACode]

    public var id: String { key }

    public init(key: String, name: String, description: String = "", researcher: String = "",
                selections: [String: [CodeSelection]] = [:], codes: [String: QDACode] = [:]) {
        self.key = key
        self.name = name
        self.description = description
        self.researcher = researcher
        self.selections = selections
        self.codes = codes
    }

    /// The layer's own fields, without its contents (layer.yml).
    public var meta: CodingLayer {
        CodingLayer(key: key, name: name, description: description, researcher: researcher)
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
}

// MARK: - Codebooks

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

public struct CodebookQuestion: Identifiable, Equatable {
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

/// What a codebook can be associated with.
public enum CodebookTarget: String, CaseIterable, Codable, Hashable {
    case files
    case interviewees
    case openCodes = "open-codes"
    case axialCodes = "axial-codes"

    public var label: String {
        switch self {
        case .files: return "Empirical Files"
        case .interviewees: return "Interviewees"
        case .openCodes: return "Open Codes"
        case .axialCodes: return "Axial Codes"
        }
    }
}

public struct Codebook: Identifiable, Equatable {
    public var key: String
    public var title: String
    public var description: String
    public var appliesTo: Set<CodebookTarget>
    public var questions: [CodebookQuestion]

    public var id: String { key }

    public init(key: String, title: String, description: String = "", appliesTo: Set<CodebookTarget> = [.files],
                questions: [CodebookQuestion] = []) {
        self.key = key
        self.title = title
        self.description = description
        self.appliesTo = appliesTo
        self.questions = questions
    }

    public func question(_ key: String) -> CodebookQuestion? { questions.first { $0.key == key } }
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

/// Identifies a codebook response sheet: a codebook, what it is about (a
/// file, code or interviewee key) and, when the project lists researchers, whose answers
/// these are.
public struct ResponseID: Hashable, Comparable {
    public var codebook: String
    public var target: String
    public var researcher: String

    public init(codebook: String, target: String, researcher: String = "") {
        self.codebook = codebook
        self.target = target
        self.researcher = researcher
    }

    /// responses/<codebook>/<target>[--<researcher>].yml
    public var path: String {
        "\(Workspace.responsesFolder)/\(codebook)/\(target)" + (researcher.isEmpty ? "" : "--\(researcher)") + ".yml"
    }

    public static func < (a: ResponseID, b: ResponseID) -> Bool {
        (a.codebook, a.target, a.researcher) < (b.codebook, b.target, b.researcher)
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

/// How complete a response sheet is against its codebook.
public struct SheetCompleteness: Equatable {
    /// Mandatory, blocking questions without an answer: the sheet can't be
    /// saved.
    public var missingBlocking: [CodebookQuestion]
    /// Mandatory, non-blocking questions without an answer: flagged.
    public var missingFlagged: [CodebookQuestion]
    public var answered: Int
    public var total: Int

    public var canSave: Bool { missingBlocking.isEmpty }
    public var isComplete: Bool { missingBlocking.isEmpty && missingFlagged.isEmpty }

    public static func of(_ answers: [String: Answer], against codebook: Codebook) -> SheetCompleteness {
        var blocking: [CodebookQuestion] = []
        var flagged: [CodebookQuestion] = []
        var answered = 0
        for q in codebook.questions {
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
                                 total: codebook.questions.count)
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
    /// Codebooks associated with this interviewee.
    public var codebooks: [String]

    public var id: String { key }

    public init(key: String, firstName: String, lastName: String, consentForm: String = "", codebooks: [String] = []) {
        self.key = key
        self.firstName = firstName
        self.lastName = lastName
        self.consentForm = consentForm
        self.codebooks = codebooks
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
    /// Codebook questions shown as columns in the tables of empirical files,
    /// interviewees, open codes and axial codes: question keys, per table.
    public var tableColumns: [CodebookTarget: [String]]

    public static let defaultInterrelationTypes = ["Compare", "Contrast"]

    public init(key: String, title: String, description: String = "", storeQuotes: Bool = true,
                interlocutorLayer: Bool = false, interrelationTypes: [String] = ProjectSettings.defaultInterrelationTypes,
                researcherNamesFile: String = "", intervieweeNamesFile: String = "",
                tableColumns: [CodebookTarget: [String]] = [:]) {
        self.key = key
        self.title = title
        self.description = description
        self.storeQuotes = storeQuotes
        self.interlocutorLayer = interlocutorLayer
        self.interrelationTypes = interrelationTypes
        self.researcherNamesFile = researcherNamesFile
        self.intervieweeNamesFile = intervieweeNamesFile
        self.tableColumns = tableColumns
    }
}

/// A whole project, as loaded from its workspace.
public struct Project: Equatable {
    public var settings: ProjectSettings
    public var files: [String: EmpiricalFile]
    /// In display order (project.yml lists the order).
    public var layers: [CodingLayer]
    public var codebooks: [String: Codebook]
    public var responses: [ResponseID: ResponseSheet]
    public var researchers: [Researcher]
    public var interviewees: [Interviewee]
    public var speakerMaps: [String: SpeakerMap]

    public init(settings: ProjectSettings, files: [String: EmpiricalFile] = [:], layers: [CodingLayer] = [],
                codebooks: [String: Codebook] = [:], responses: [ResponseID: ResponseSheet] = [:],
                researchers: [Researcher] = [], interviewees: [Interviewee] = [],
                speakerMaps: [String: SpeakerMap] = [:]) {
        self.settings = settings
        self.files = files
        self.layers = layers
        self.codebooks = codebooks
        self.responses = responses
        self.researchers = researchers
        self.interviewees = interviewees
        self.speakerMaps = speakerMaps
    }

    /// A new project with one layer.
    public static func new(title: String, firstLayer: String = "Main") -> Project {
        let settings = ProjectSettings(key: Keys.make(Keys.project), title: title)
        return Project(settings: settings, layers: [CodingLayer(key: Keys.make(Keys.layer), name: firstLayer)])
    }

    // MARK: Lookups

    public func layerIndex(_ key: String) -> Int? { layers.firstIndex { $0.key == key } }

    public func layer(_ key: String) -> CodingLayer? { layers.first { $0.key == key } }

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

    public var sortedCodebooks: [Codebook] {
        codebooks.values.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
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
            for c in layer.codes.values { keys.formUnion(c.interrelations.map(\.key)) }
            for list in layer.selections.values { keys.formUnion(list.map(\.key)) }
        }
        keys.formUnion(codebooks.keys)
        for cb in codebooks.values { keys.formUnion(cb.questions.map(\.key)) }
        keys.formUnion(researchers.map(\.key))
        keys.formUnion(interviewees.map(\.key))
        return keys
    }

    public func newKey(_ prefix: String) -> String { Keys.make(prefix, avoiding: allKeys) }
}

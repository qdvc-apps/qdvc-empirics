import Foundation

// The data behind the Reports pages: the Coding Chart (files → open codes
// → theorising codes) and the Attribute Sheet Report (every response to an attribute sheet).
// Worked out here, without any interface, so they can be tested.

// MARK: - Coding Chart

/// Columns of a layer's coding, left to right: empirical files, open codes,
/// then theorising codes by level (a theorising code built only from open codes is
/// level 1; one built from a level-n theorising code is at least level n + 1), so
/// higher-level theorising codes sit further right. Edges link files to the open
/// codes with evidence in them, and codes to the theorising codes they are
/// evidence for (M:N, possibly skipping columns).
public struct CodingChart: Equatable {
    public struct Edge: Hashable {
        /// The left end (a file, or the code that is evidence).
        public var from: String
        /// The right end (an open code, or the theorising code).
        public var to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    /// Item keys per column, top to bottom.
    public var columns: [[String]]
    public var edges: [Edge]
    /// Items left out because nothing links them (when not included).
    public var unlinked: Int

    public init(columns: [[String]] = [], edges: [Edge] = [], unlinked: Int = 0) {
        self.columns = columns
        self.edges = edges
        self.unlinked = unlinked
    }

    /// The column of each item.
    public var columnOf: [String: Int] {
        var r: [String: Int] = [:]
        for (i, c) in columns.enumerated() { for k in c { r[k] = i } }
        return r
    }

    /// Items linked to `key` through the chart: everything it builds on
    /// (leftwards) and everything built on it (rightwards), and itself.
    public func connected(to key: String) -> Set<String> {
        var left: [String: [String]] = [:], right: [String: [String]] = [:]
        for e in edges {
            left[e.to, default: []].append(e.from)
            right[e.from, default: []].append(e.to)
        }
        var seen: Set<String> = [key]
        for links in [left, right] {
            var stack = [key]
            while let k = stack.popLast() {
                for n in links[k] ?? [] where !seen.contains(n) {
                    seen.insert(n)
                    stack.append(n)
                }
            }
        }
        return seen
    }

    public static func make(_ p: Project, layer layerKey: String, includeUnlinked: Bool = false) -> CodingChart {
        guard let layer = p.layer(layerKey) else { return CodingChart() }
        var fileOf: [String: String] = [:]
        for (file, list) in layer.selections {
            for s in list { fileOf[s.key] = file }
        }
        let open = layer.codes.values.filter { $0.kind == .open }
        let theorising = layer.codes.values.filter { $0.kind == .theorising }

        var edges = Set<Edge>()
        for c in open {
            for e in c.evidence {
                if let f = fileOf[e.target], p.files[f] != nil { edges.insert(Edge(from: f, to: c.key)) }
            }
        }
        for a in theorising {
            for e in a.evidence where layer.codes[e.target] != nil {
                edges.insert(Edge(from: e.target, to: a.key))
            }
        }

        // Levels of theorising codes (cycles can't be made, but are guarded).
        var level: [String: Int] = [:]
        func levelOf(_ key: String, _ visiting: inout Set<String>) -> Int {
            if let l = level[key] { return l }
            guard let c = layer.codes[key], c.kind == .theorising, !visiting.contains(key) else { return 0 }
            visiting.insert(key)
            var l = 1
            for e in c.evidence {
                if let child = layer.codes[e.target], child.kind == .theorising {
                    l = max(l, levelOf(child.key, &visiting) + 1)
                }
            }
            visiting.remove(key)
            level[key] = l
            return l
        }
        for a in theorising {
            var visiting = Set<String>()
            _ = levelOf(a.key, &visiting)
        }

        var linked = Set<String>()
        for e in edges {
            linked.insert(e.from)
            linked.insert(e.to)
        }
        let files = p.files.values.filter { includeUnlinked || linked.contains($0.key) }
        let unlinked = includeUnlinked ? 0
            : layer.codes.keys.filter { !linked.contains($0) }.count + p.files.keys.filter { !linked.contains($0) }.count
        func keep(_ key: String) -> Bool { includeUnlinked || linked.contains(key) }

        func byTitle(_ items: [(key: String, title: String)]) -> [String] {
            items.sorted { a, b in
                let c = a.title.localizedStandardCompare(b.title)
                return c == .orderedSame ? a.key < b.key : c == .orderedAscending
            }.map(\.key)
        }
        var columns: [[String]] = [
            byTitle(files.map { ($0.key, $0.displayTitle) }),
            byTitle(open.filter { keep($0.key) }.map { ($0.key, $0.name) }),
        ]
        let maxLevel = level.values.max() ?? 0
        if maxLevel > 0 {
            for l in 1...maxLevel {
                columns.append(byTitle(theorising.filter { level[$0.key] == l && keep($0.key) }.map { ($0.key, $0.name) }))
            }
        }
        while let last = columns.last, last.isEmpty, columns.count > 2 { columns.removeLast() }

        let sortedEdges = edges.sorted { ($0.from, $0.to) < ($1.from, $1.to) }
        let ordered = reduceCrossings(columns, edges: sortedEdges)
        return CodingChart(columns: ordered, edges: sortedEdges, unlinked: unlinked)
    }

    /// Barycentre ordering: each column is sorted by the mean position of
    /// its items' neighbours, sweeping right then left a few times, so lines
    /// cross less. Ties keep the alphabetical order.
    static func reduceCrossings(_ start: [[String]], edges: [Edge]) -> [[String]] {
        var columns = start
        var neighbours: [String: [String]] = [:]
        for e in edges {
            neighbours[e.from, default: []].append(e.to)
            neighbours[e.to, default: []].append(e.from)
        }
        var columnOf: [String: Int] = [:]
        for (i, c) in columns.enumerated() { for k in c { columnOf[k] = i } }
        func positions() -> [String: Double] {
            var r: [String: Double] = [:]
            for c in columns {
                for (i, k) in c.enumerated() { r[k] = (Double(i) + 0.5) / Double(max(1, c.count)) }
            }
            return r
        }
        func sweep(_ c: Int, towardLeft: Bool) {
            let pos = positions()
            let items = columns[c].enumerated().map { i, key -> (key: String, value: Double, i: Int) in
                let ns = (neighbours[key] ?? []).filter { n in
                    guard let nc = columnOf[n] else { return false }
                    return towardLeft ? nc < c : nc > c
                }
                let value = ns.isEmpty ? (pos[key] ?? 0) : ns.compactMap { pos[$0] }.reduce(0, +) / Double(ns.count)
                return (key, value, i)
            }
            columns[c] = items.sorted { a, b in a.value == b.value ? a.i < b.i : a.value < b.value }.map(\.key)
        }
        guard columns.count > 1 else { return columns }
        for _ in 0..<4 {
            for c in 1..<columns.count { sweep(c, towardLeft: true) }
            for c in stride(from: columns.count - 2, through: 0, by: -1) { sweep(c, towardLeft: false) }
        }
        return columns
    }
}

// MARK: - Attribute Sheet Report

/// Every response to an attribute sheet, one row per response sheet (an item and,
/// when the project lists researchers, whose answers), plus a row for each
/// associated item nobody has answered yet.
public struct AttributeSheetReport: Equatable {
    public struct Row: Equatable, Identifiable {
        /// The file, code or interviewee the answers are about.
        public var target: String
        /// Whose answers ("" when the project has no researchers, or for an
        /// item not answered yet).
        public var researcher: String
        public var sheet: ResponseSheet?
        public var completeness: SheetCompleteness

        public var id: String { target + "--" + researcher }

        public enum Status: String { case notStarted = "Not started", flagged = "Flagged", complete = "Complete" }

        public var status: Status {
            guard sheet != nil else { return .notStarted }
            return completeness.isComplete ? .complete : .flagged
        }

        public func answer(_ question: String) -> Answer? { sheet?.answers[question] }
    }

    public var attributeSheet: AttributeSheet
    public var rows: [Row]

    public static func make(_ p: Project, attributeSheet key: String, title: (String) -> String,
                            person: (String) -> String) -> AttributeSheetReport? {
        guard let cb = p.attributeSheets[key] else { return nil }
        var rows: [Row] = []
        var answered = Set<String>()
        for sheet in p.responses.values where sheet.id.attributeSheet == key {
            answered.insert(sheet.id.target)
            rows.append(Row(target: sheet.id.target, researcher: sheet.id.researcher, sheet: sheet,
                            completeness: SheetCompleteness.of(sheet.answers, against: cb)))
        }
        var targets = p.files.values.filter { $0.attributeSheets.contains(key) }.map(\.key)
        targets += p.interviewees.filter { $0.attributeSheets.contains(key) }.map(\.key)
        for layer in p.layers {
            targets += layer.codes.values.filter { $0.attributeSheets.contains(key) }.map(\.key)
        }
        for t in targets where !answered.contains(t) {
            rows.append(Row(target: t, researcher: "", sheet: nil, completeness: SheetCompleteness.of([:], against: cb)))
        }
        // Files, then interviewees, then open codes, then theorising codes; each
        // by title, then by researcher.
        func group(_ k: String) -> Int {
            if p.files[k] != nil { return 0 }
            if p.interviewee(k) != nil { return 1 }
            return p.code(k)?.kind == .theorising ? 3 : 2
        }
        rows.sort { a, b in
            let ga = group(a.target), gb = group(b.target)
            if ga != gb { return ga < gb }
            let t = title(a.target).localizedStandardCompare(title(b.target))
            if t != .orderedSame { return t == .orderedAscending }
            if a.target != b.target { return a.target < b.target }
            return person(a.researcher).localizedStandardCompare(person(b.researcher)) == .orderedAscending
        }
        return AttributeSheetReport(attributeSheet: cb, rows: rows)
    }

    /// The report as CSV: working identifier, item, kind, researcher,
    /// status, then one column per question (labelled by its label).
    public func csv(workingIDs: [String: String], title: (String) -> String, kind: (String) -> String,
                    person: (String) -> String) -> String {
        var lines = [CSV.line(["No.", "Item", "Kind", "Researcher", "Status"] + attributeSheet.questions.map(\.label))]
        for r in rows {
            var fields = [workingIDs[r.target] ?? "", title(r.target), kind(r.target),
                          r.researcher.isEmpty ? "" : person(r.researcher), r.status.rawValue]
            fields += attributeSheet.questions.map { q in r.answer(q.key)?.values.joined(separator: "; ") ?? "" }
            lines.append(CSV.line(fields))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

// MARK: - Protocol Report

/// A protocol across the empirical files that follow it in a deductive
/// layer: a row per file, a column per protocol item, and in each cell the
/// researcher's summary of what the file says for that item (the layer's
/// Framework Matrix cell for the file and item), with the item's prompt and
/// response segments there, to read the full answer.
public struct ProtocolReport: Equatable {
    public struct Cell: Equatable {
        public var summary: String = ""
        /// Selection keys of the item's segments in the file, in text order.
        public var prompts: [String] = []
        public var responses: [String] = []

        public init(summary: String = "", prompts: [String] = [], responses: [String] = []) {
            self.summary = summary
            self.prompts = prompts
            self.responses = responses
        }

        public var isMarked: Bool { !prompts.isEmpty || !responses.isEmpty }
        public var isEmpty: Bool { summary.isEmpty && !isMarked }
    }

    public struct Row: Equatable, Identifiable {
        public var file: String
        /// By protocol item key.
        public var cells: [String: Cell]

        public var id: String { file }

        public func cell(_ item: String) -> Cell { cells[item] ?? Cell() }
    }

    public var studyProtocol: StudyProtocol
    public var layer: String
    public var rows: [Row]

    /// The report for a protocol in a deductive layer: the files following
    /// it there, in the Empirical Files order.
    public static func make(_ p: Project, protocol key: String, layer layerKey: String) -> ProtocolReport? {
        guard let pr = p.protocols[key], let layer = p.layer(layerKey), layer.isDeductive else { return nil }
        let items = Set(pr.items.map(\.key))
        var rows: [Row] = []
        for f in p.sortedFiles where layer.protocols[f.key] == key {
            var cells: [String: Cell] = [:]
            for (item, summary) in layer.framework[f.key] ?? [:] where items.contains(item) {
                cells[item, default: Cell()].summary = summary
            }
            for s in layer.selections[f.key] ?? [] {
                guard let segment = s.segment, items.contains(segment.item) else { continue }
                if segment.part == .prompt {
                    cells[segment.item, default: Cell()].prompts.append(s.key)
                } else {
                    cells[segment.item, default: Cell()].responses.append(s.key)
                }
            }
            rows.append(Row(file: f.key, cells: cells))
        }
        return ProtocolReport(studyProtocol: pr, layer: layerKey, rows: rows)
    }

    /// The report as CSV: working identifier and file, then one column per
    /// item (its number and label) with the summaries.
    public func csv(workingIDs: [String: String], title: (String) -> String) -> String {
        let headings = studyProtocol.items.enumerated().map { i, item in "\(i + 1) \(item.label)" }
        var lines = [CSV.line(["No.", "File"] + headings)]
        for r in rows {
            lines.append(CSV.line([workingIDs[r.file] ?? "", title(r.file)] + studyProtocol.items.map { r.cell($0.key).summary }))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}

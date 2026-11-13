import Foundation

// Reading and writing each workspace file (docs/FILE_FORMAT.md). Readers
// are forgiving (missing fields take defaults, unknown fields are ignored);
// writers always produce the same bytes for the same data, with keys in a
// fixed order and empty optional fields left out, so diffs stay small.

private func str(_ s: String) -> YAMLNode { .scalar(s) }
private func num(_ n: Int) -> YAMLNode { .scalar(String(n)) }
private func flag(_ b: Bool) -> YAMLNode { .scalar(b ? "true" : "false") }
private func list(_ items: [String]) -> YAMLNode { .sequence(items.map { .scalar($0) }) }

/// Builds a mapping, leaving out empty optional values.
private struct Pairs {
    var pairs: [YAMLPair] = []

    mutating func add(_ key: String, _ value: YAMLNode) { pairs.append(YAMLPair(key, value)) }

    mutating func add(_ key: String, _ s: String, ifEmpty keep: Bool = false) {
        if keep || !s.isEmpty { pairs.append(YAMLPair(key, .scalar(s))) }
    }

    mutating func add(_ key: String, list items: [String]) {
        if !items.isEmpty { pairs.append(YAMLPair(key, .sequence(items.map { .scalar($0) }))) }
    }

    var node: YAMLNode { .mapping(pairs) }
}

extension Workspace {

    // MARK: project.yml

    static func encodeSettings(_ p: Project) -> YAMLNode {
        let s = p.settings
        var m = Pairs()
        m.add("format", num(formatVersion))
        m.add("app", str(appName))
        m.add("key", str(s.key))
        m.add("title", s.title, ifEmpty: true)
        m.add("description", s.description)
        m.add("store_quotes", flag(s.storeQuotes))
        m.add("interlocutor_layer", flag(s.interlocutorLayer))
        m.add("interrelation_types", list(s.interrelationTypes))
        if !s.researcherNamesFile.isEmpty || !s.intervieweeNamesFile.isEmpty {
            var names = Pairs()
            names.add("researchers", s.researcherNamesFile)
            names.add("interviewees", s.intervieweeNamesFile)
            m.add("real_names", names.node)
        }
        let tables = AttributeSheetTarget.allCases.filter { !(s.tableColumns[$0] ?? []).isEmpty }
        if !tables.isEmpty {
            var columns = Pairs()
            for t in tables { columns.add(t.rawValue, list: s.tableColumns[t] ?? []) }
            m.add("table_columns", columns.node)
        }
        let layouts = AttributeSheetTarget.allCases.filter { !(s.tableLayouts[$0] ?? "").isEmpty }
        if !layouts.isEmpty {
            var arranged = Pairs()
            for t in layouts { arranged.add(t.rawValue, s.tableLayouts[t] ?? "") }
            m.add("table_layouts", arranged.node)
        }
        m.add("layers", list(p.layers.map(\.key)))
        return m.node
    }

    static func decodeSettings(_ n: YAMLNode) -> ProjectSettings {
        var columns: [AttributeSheetTarget: [String]] = [:]
        for pair in n["table_columns"]?.pairs ?? [] {
            guard let target = AttributeSheetTarget(rawValue: pair.key) else { continue }
            let keys = pair.value.strings
            if !keys.isEmpty { columns[target] = keys }
        }
        var layouts: [AttributeSheetTarget: String] = [:]
        for pair in n["table_layouts"]?.pairs ?? [] {
            guard let target = AttributeSheetTarget(rawValue: pair.key), let json = pair.value.string, !json.isEmpty else { continue }
            layouts[target] = json
        }
        return ProjectSettings(
            key: n["key"]?.string ?? Keys.make(Keys.project),
            title: n["title"]?.string ?? "Untitled Project",
            description: n["description"]?.string ?? "",
            storeQuotes: n["store_quotes"]?.bool ?? true,
            interlocutorLayer: n["interlocutor_layer"]?.bool ?? false,
            interrelationTypes: n["interrelation_types"].map { $0.strings } ?? ProjectSettings.defaultInterrelationTypes,
            researcherNamesFile: n["real_names"]?["researchers"]?.string ?? "",
            intervieweeNamesFile: n["real_names"]?["interviewees"]?.string ?? "",
            tableColumns: columns,
            tableLayouts: layouts
        )
    }

    // MARK: files/<key>.yml

    static func encodeFile(_ f: EmpiricalFile) -> YAMLNode {
        var m = Pairs()
        m.add("key", str(f.key))
        m.add("path", str(f.path))
        m.add("kind", str(f.kind.rawValue))
        m.add("title", f.title)
        m.add("date", f.date)
        m.add("id", f.customID)
        m.add("status", str(f.status.rawValue))
        m.add("fingerprint", f.fingerprint)
        m.add("attribute_sheets", list: f.attributeSheets)
        m.add("added", f.added)
        if !f.rotations.isEmpty {
            // One-based page numbers, as people count pages.
            m.add("rotations", .mapping(f.rotations.keys.sorted().map { YAMLPair(String($0 + 1), num(f.rotations[$0]!)) }))
        }
        return m.node
    }

    static func decodeFile(key: String, _ n: YAMLNode) -> EmpiricalFile? {
        guard let path = n["path"]?.string, !path.isEmpty else { return nil }
        return EmpiricalFile(
            key: key,
            path: path,
            kind: n["kind"]?.string.flatMap(FileKind.init(rawValue:)) ?? FileKind.forPath(path) ?? .text,
            title: n["title"]?.string ?? "",
            date: n["date"]?.string ?? "",
            customID: n["id"]?.string ?? "",
            status: n["status"]?.string.flatMap(CodingStatus.init(rawValue:)) ?? .notStarted,
            fingerprint: n["fingerprint"]?.string ?? "",
            attributeSheets: n["attribute_sheets"]?.strings ?? [],
            added: n["added"]?.string ?? "",
            rotations: decodeRotations(n["rotations"])
        )
    }

    /// Page rotations: one-based page → 90, 180 or 270 (anything else is
    /// ignored).
    static func decodeRotations(_ n: YAMLNode?) -> [Int: Int] {
        var result: [Int: Int] = [:]
        for pair in n?.pairs ?? [] {
            guard let page = Int(pair.key.trimmingCharacters(in: .whitespaces)), page >= 1,
                  let degrees = pair.value.string.flatMap({ Int($0.trimmingCharacters(in: .whitespaces)) }) else { continue }
            let d = ((degrees % 360) + 360) % 360
            if [90, 180, 270].contains(d) { result[page - 1] = d }
        }
        return result
    }

    // MARK: attribute sheets/<key>.yml

    static func encodeAttributeSheet(_ cb: AttributeSheet) -> YAMLNode {
        var m = Pairs()
        m.add("key", str(cb.key))
        m.add("title", cb.title, ifEmpty: true)
        m.add("description", cb.description)
        m.add("applies_to", list(AttributeSheetTarget.allCases.filter { cb.appliesTo.contains($0) }.map(\.rawValue)))
        m.add("questions", .sequence(cb.questions.map { q in
            var qm = Pairs()
            qm.add("key", str(q.key))
            qm.add("label", q.label, ifEmpty: true)
            qm.add("text", q.text)
            qm.add("type", str(q.type.rawValue))
            if q.type.usesOptions {
                qm.add("options", list(q.options))
                qm.add("strict", flag(q.strict))
            }
            qm.add("requirement", str(q.requirement.rawValue))
            return qm.node
        }))
        return m.node
    }

    static func decodeAttributeSheet(key: String, _ n: YAMLNode) -> AttributeSheet {
        let targets = Set((n["applies_to"]?.strings ?? ["files"]).compactMap(AttributeSheetTarget.init(rawValue:)))
        var seen = Set<String>()
        let questions: [AttributeSheetQuestion] = (n["questions"]?.items ?? []).compactMap { q in
            var k = q["key"]?.string ?? ""
            if k.isEmpty || seen.contains(k) { k = Keys.make(Keys.question, avoiding: seen) }
            seen.insert(k)
            return AttributeSheetQuestion(
                key: k,
                label: q["label"]?.string ?? "",
                text: q["text"]?.string ?? "",
                type: q["type"]?.string.flatMap(QuestionType.init(rawValue:)) ?? .text,
                options: q["options"]?.strings ?? [],
                strict: q["strict"]?.bool ?? false,
                requirement: q["requirement"]?.string.flatMap(Requirement.init(rawValue:)) ?? .optional
            )
        }
        return AttributeSheet(key: key, title: n["title"]?.string ?? "Untitled Attribute Sheet",
                        description: n["description"]?.string ?? "", appliesTo: targets, questions: questions)
    }

    // MARK: responses/<cb>/<target>[--<researcher>].yml

    static func encodeResponse(_ s: ResponseSheet, attributeSheet: AttributeSheet?) -> YAMLNode {
        var m = Pairs()
        m.add("attribute_sheet", str(s.id.attributeSheet))
        m.add("target", str(s.id.target))
        m.add("researcher", s.id.researcher)
        m.add("updated", s.updated)
        // In the attribute sheet's question order; answers to unknown questions last.
        let order = (attributeSheet?.questions.map(\.key) ?? []) + s.answers.keys.sorted()
        var done = Set<String>()
        var items: [YAMLNode] = []
        for k in order where done.insert(k).inserted {
            guard let a = s.answers[k] else { continue }
            var am = Pairs()
            am.add("question", str(k))
            if let label = attributeSheet?.question(k)?.label, !label.isEmpty { am.add("label", str(label)) }
            switch a {
            case .text(let t): am.add("text", str(t))
            case .one(let v): am.add("answer", str(v))
            case .many(let vs): am.add("answers", list(vs))
            }
            items.append(am.node)
        }
        m.add("answers", .sequence(items))
        return m.node
    }

    static func decodeResponse(id: ResponseID, _ n: YAMLNode) -> ResponseSheet {
        var answers: [String: Answer] = [:]
        for item in n["answers"]?.items ?? [] {
            guard let q = item["question"]?.string else { continue }
            if let t = item["text"]?.string {
                answers[q] = .text(t)
            } else if let v = item["answer"]?.string {
                answers[q] = .one(v)
            } else if let vs = item["answers"] {
                answers[q] = .many(vs.strings)
            }
        }
        return ResponseSheet(id: id, answers: answers, updated: n["updated"]?.string ?? "")
    }

    // MARK: layers/<key>/layer.yml

    static func encodeLayer(_ l: CodingLayer) -> YAMLNode {
        var m = Pairs()
        m.add("key", str(l.key))
        m.add("kind", str(l.kind.rawValue))
        m.add("name", l.name, ifEmpty: true)
        m.add("description", l.description)
        m.add("researcher", l.researcher)
        return m.node
    }

    // MARK: layers/<key>/selections/<file>.yml

    static func encodeSelections(file: String, _ list: [CodeSelection], protocolKey: String?) -> YAMLNode {
        var m = Pairs()
        m.add("file", str(file))
        m.add("protocol", protocolKey ?? "")
        m.add("selections", .sequence(list.map { s in
            var sm = Pairs()
            sm.add("key", str(s.key))
            if s.irrelevant { sm.add("irrelevant", flag(true)) }
            if let seg = s.segment {
                sm.add("item", str(seg.item))
                sm.add("part", str(seg.part.rawValue))
            }
            if s.spans.count == 1 {
                encodeSpan(s.spans[0], into: &sm)
            } else {
                sm.add("spans", .sequence(s.spans.map { span in
                    var r = Pairs()
                    encodeSpan(span, into: &r)
                    return r.node
                }))
            }
            sm.add("quote", s.quote)
            sm.add("by", s.by)
            sm.add("created", s.created)
            return sm.node
        }))
        return m.node
    }

    private static func encodeSpan(_ span: TextSpan, into m: inout Pairs) {
        if let page = span.page { m.add("page", num(page + 1)) }
        m.add("start", num(span.start))
        m.add("length", num(span.length))
    }

    private static func decodeSpan(_ n: YAMLNode) -> TextSpan? {
        guard let start = n["start"]?.int, let length = n["length"]?.int, start >= 0, length > 0 else { return nil }
        return TextSpan(page: n["page"]?.int.map { max(0, $0 - 1) }, start: start, length: length)
    }

    static func decodeSelections(fileKey: String, _ n: YAMLNode) -> [CodeSelection] {
        (n["selections"]?.items ?? []).compactMap { item in
            guard let key = item["key"]?.string else { return nil }
            let spans: [TextSpan]
            if let list = item["spans"] {
                spans = list.items.compactMap(decodeSpan)
            } else {
                spans = decodeSpan(item).map { [$0] } ?? []
            }
            guard !spans.isEmpty else { return nil }
            var segment: ProtocolSegment?
            if let pi = item["item"]?.string, !pi.isEmpty {
                segment = ProtocolSegment(item: pi, part: item["part"]?.string.flatMap(ProtocolPart.init(rawValue:)) ?? .response)
            }
            return CodeSelection(key: key, fileKey: fileKey, spans: spans, quote: item["quote"]?.string ?? "",
                                 irrelevant: item["irrelevant"]?.bool ?? false, segment: segment,
                                 by: item["by"]?.string ?? "", created: item["created"]?.string ?? "")
        }
    }

    // MARK: layers/<key>/codes/<code>.yml

    static func encodeCode(_ c: QDACode) -> YAMLNode {
        var m = Pairs()
        m.add("key", str(c.key))
        m.add("kind", str(c.kind.rawValue))
        m.add("name", c.name, ifEmpty: true)
        m.add("colour", c.colour)
        m.add("description", c.description)
        let evidenceKey = c.kind == .open ? "selection" : "code"
        m.add("evidence", .sequence(c.evidence.map { e in
            var em = Pairs()
            em.add(evidenceKey, str(e.target))
            em.add("memo", e.memo)
            return em.node
        }))
        if !c.comments.isEmpty { m.add("comments", list(c.comments)) }
        if !c.questions.isEmpty { m.add("questions", list(c.questions)) }
        if !c.interrelations.isEmpty {
            m.add("interrelations", .sequence(c.interrelations.map { x in
                var xm = Pairs()
                xm.add("key", str(x.key))
                xm.add("type", str(x.type))
                xm.add("members", list(x.members))
                xm.add("description", x.description)
                return xm.node
            }))
        }
        if !c.links.isEmpty {
            m.add("links", .sequence(c.links.map { l in
                var lm = Pairs()
                lm.add("key", str(l.key))
                lm.add("apriori_code", str(l.aprioriCode))
                lm.add("type", str(l.type.rawValue))
                lm.add("memo", l.memo)
                return lm.node
            }))
        }
        m.add("attribute_sheets", list: c.attributeSheets)
        m.add("by", c.by)
        m.add("created", c.created)
        return m.node
    }

    static func decodeCode(key: String, _ n: YAMLNode) -> QDACode {
        let kind = n["kind"]?.string.flatMap(CodeKind.init(rawValue:)) ?? .open
        let evidence: [Evidence] = (n["evidence"]?.items ?? []).compactMap { e in
            if let t = e.string { return Evidence(target: t) }   // "- s-1234abcd" shorthand
            guard let t = e["selection"]?.string ?? e["code"]?.string else { return nil }
            return Evidence(target: t, memo: e["memo"]?.string ?? "")
        }
        var seen = Set<String>()
        let interrelations: [Interrelation] = (n["interrelations"]?.items ?? []).map { x in
            var k = x["key"]?.string ?? ""
            if k.isEmpty || seen.contains(k) { k = Keys.make(Keys.interrelation, avoiding: seen) }
            seen.insert(k)
            return Interrelation(key: k, type: x["type"]?.string ?? "", members: x["members"]?.strings ?? [],
                                 description: x["description"]?.string ?? "")
        }
        var seenLinks = Set<String>()
        let links: [CodeLink] = (n["links"]?.items ?? []).compactMap { l in
            guard let apc = l["apriori_code"]?.string, !apc.isEmpty else { return nil }
            var k = l["key"]?.string ?? ""
            if k.isEmpty || seenLinks.contains(k) { k = Keys.make(Keys.link, avoiding: seenLinks) }
            seenLinks.insert(k)
            return CodeLink(key: k, aprioriCode: apc,
                            type: l["type"]?.string.flatMap(LinkType.init(rawValue:)) ?? .confirms,
                            memo: l["memo"]?.string ?? "")
        }
        var unique = Set<String>()
        return QDACode(
            key: key,
            kind: kind,
            name: n["name"]?.string ?? "Untitled Code",
            description: n["description"]?.string ?? "",
            colour: n["colour"]?.string ?? n["color"]?.string ?? "",
            evidence: evidence.filter { unique.insert($0.target).inserted },
            comments: n["comments"]?.strings ?? [],
            questions: n["questions"]?.strings ?? [],
            interrelations: interrelations,
            links: links,
            attributeSheets: n["attribute_sheets"]?.strings ?? [],
            by: n["by"]?.string ?? "",
            created: n["created"]?.string ?? ""
        )
    }

    // MARK: protocols/<key>.yml

    static func encodeProtocol(_ pr: StudyProtocol) -> YAMLNode {
        var m = Pairs()
        m.add("key", str(pr.key))
        m.add("title", pr.title, ifEmpty: true)
        m.add("description", pr.description)
        m.add("items", .sequence(pr.items.map { item in
            var im = Pairs()
            im.add("key", str(item.key))
            im.add("label", item.label, ifEmpty: true)
            im.add("text", item.text)
            return im.node
        }))
        return m.node
    }

    static func decodeProtocol(key: String, _ n: YAMLNode) -> StudyProtocol {
        var seen = Set<String>()
        let items: [ProtocolItem] = (n["items"]?.items ?? []).map { item in
            var k = item["key"]?.string ?? ""
            if k.isEmpty || seen.contains(k) { k = Keys.make(Keys.protocolItem, avoiding: seen) }
            seen.insert(k)
            return ProtocolItem(key: k, label: item["label"]?.string ?? "", text: item["text"]?.string ?? "")
        }
        return StudyProtocol(key: key, title: n["title"]?.string ?? "Untitled Protocol",
                             description: n["description"]?.string ?? "", items: items)
    }

    // MARK: apriori-codes/<key>.yml

    static func encodeAprioriCode(_ c: AprioriCode) -> YAMLNode {
        var m = Pairs()
        m.add("key", str(c.key))
        m.add("name", c.name, ifEmpty: true)
        m.add("colour", c.colour)
        m.add("definition", c.definition)
        m.add("included", c.included)
        m.add("excluded", c.excluded)
        m.add("example", c.example)
        m.add("counter_example", c.counterExample)
        m.add("source", c.source)
        m.add("by", c.by)
        m.add("created", c.created)
        return m.node
    }

    static func decodeAprioriCode(key: String, _ n: YAMLNode) -> AprioriCode {
        AprioriCode(key: key,
                    name: n["name"]?.string ?? "Untitled Code",
                    colour: n["colour"]?.string ?? n["color"]?.string ?? "",
                    definition: n["definition"]?.string ?? "",
                    included: n["included"]?.string ?? "",
                    excluded: n["excluded"]?.string ?? "",
                    example: n["example"]?.string ?? "",
                    counterExample: n["counter_example"]?.string ?? "",
                    source: n["source"]?.string ?? "",
                    by: n["by"]?.string ?? "",
                    created: n["created"]?.string ?? "")
    }

    // MARK: layers/<key>/apriori/<apc-key>.yml

    static func encodeAprioriEvidence(code: String, _ evidence: [Evidence]) -> YAMLNode {
        var m = Pairs()
        m.add("apriori_code", str(code))
        m.add("evidence", .sequence(evidence.map { e in
            var em = Pairs()
            em.add("selection", str(e.target))
            em.add("memo", e.memo)
            return em.node
        }))
        return m.node
    }

    static func decodeAprioriEvidence(_ n: YAMLNode) -> [Evidence] {
        var unique = Set<String>()
        let evidence: [Evidence] = (n["evidence"]?.items ?? []).compactMap { e in
            if let t = e.string { return Evidence(target: t) }   // "- s-1234abcd" shorthand
            guard let t = e["selection"]?.string else { return nil }
            return Evidence(target: t, memo: e["memo"]?.string ?? "")
        }
        return evidence.filter { unique.insert($0.target).inserted }
    }

    // MARK: layers/<key>/framework/<row>.yml

    static func encodeFrameworkRow(row: String, _ cells: [String: String]) -> YAMLNode {
        var m = Pairs()
        m.add("row", str(row))
        m.add("cells", .sequence(cells.keys.sorted().map { column in
            var cm = Pairs()
            cm.add("column", str(column))
            cm.add("summary", str(cells[column] ?? ""))
            return cm.node
        }))
        return m.node
    }

    static func decodeFrameworkRow(_ n: YAMLNode) -> [String: String] {
        var cells: [String: String] = [:]
        for c in n["cells"]?.items ?? [] {
            guard let column = c["column"]?.string, let summary = c["summary"]?.string,
                  !summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            cells[column] = summary
        }
        return cells
    }

    // MARK: people

    static func encodeResearcher(_ r: Researcher) -> YAMLNode {
        var m = Pairs()
        m.add("key", str(r.key))
        m.add("first", r.firstName, ifEmpty: true)
        m.add("last", r.lastName, ifEmpty: true)
        return m.node
    }

    static func decodeResearcher(_ n: YAMLNode) -> Researcher? {
        guard let key = n["key"]?.string else { return nil }
        return Researcher(key: key, firstName: n["first"]?.string ?? "", lastName: n["last"]?.string ?? "")
    }

    static func encodeInterviewee(_ i: Interviewee) -> YAMLNode {
        var m = Pairs()
        m.add("key", str(i.key))
        m.add("first", i.firstName, ifEmpty: true)
        m.add("last", i.lastName, ifEmpty: true)
        m.add("consent_form", i.consentForm)
        m.add("attribute_sheets", list: i.attributeSheets)
        return m.node
    }

    static func decodeInterviewee(_ n: YAMLNode) -> Interviewee? {
        guard let key = n["key"]?.string else { return nil }
        return Interviewee(key: key, firstName: n["first"]?.string ?? "", lastName: n["last"]?.string ?? "",
                           consentForm: n["consent_form"]?.string ?? "", attributeSheets: n["attribute_sheets"]?.strings ?? [])
    }

    // MARK: interlocutors/<file>.yml

    static func encodeSpeakers(_ s: SpeakerMap) -> YAMLNode {
        var m = Pairs()
        m.add("file", str(s.fileKey))
        m.add("speakers", .sequence(s.assignments.map { a in
            .mapping([YAMLPair("label", str(a.label)), YAMLPair("person", str(a.person))])
        }))
        m.add("not_speakers", list: s.ignored)
        return m.node
    }

    static func decodeSpeakers(fileKey: String, _ n: YAMLNode) -> SpeakerMap {
        let assignments: [SpeakerAssignment] = (n["speakers"]?.items ?? []).compactMap { a in
            guard let label = a["label"]?.string, let person = a["person"]?.string else { return nil }
            return SpeakerAssignment(label: label, person: person)
        }
        return SpeakerMap(fileKey: fileKey, assignments: assignments, ignored: n["not_speakers"]?.strings ?? [])
    }
}

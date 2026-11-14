import Foundation
import XCTest
@testable import EmpiricsCore

/// Editing a full-text in place, writing it back as it was encoded, merging
/// selections next to each other, page rotations, table layouts and the
/// Protocol Responses.
final class TextEditTests: XCTestCase {
    func makeProject() -> (Project, layer: String, deductive: String, file: String) {
        var p = Project.new(title: "Edits")
        let f = p.addFile(path: "interviews/one.txt", kind: .text)
        return (p, p.inductiveLayers[0].key, p.deductiveLayers[0].key, f)
    }

    func text(_ p: Project, _ key: String, in text: String) -> String {
        TextNormaliser.quote(p.selection(key)?.spans ?? [], pages: [text])
    }

    func testSpanAdjustment() {
        let span = TextSpan(start: 10, length: 10)   // 10 ..< 20
        // Before, after, around, at the edges.
        XCTAssertEqual(span.adjusted(start: 25, length: 2, count: 5), span)
        XCTAssertEqual(span.adjusted(start: 0, length: 4, count: 1), TextSpan(start: 7, length: 10))
        XCTAssertEqual(span.adjusted(start: 12, length: 3, count: 5), TextSpan(start: 10, length: 12))
        XCTAssertEqual(span.adjusted(start: 20, length: 0, count: 3), span)                       // inserted at its end
        XCTAssertEqual(span.adjusted(start: 10, length: 0, count: 3), TextSpan(start: 13, length: 10)) // at its start
        // Overlapping one end: takes in the replacement, or stops at it.
        XCTAssertEqual(span.adjusted(start: 15, length: 10, count: 2), TextSpan(start: 10, length: 7))
        XCTAssertEqual(span.adjusted(start: 15, length: 10, count: 2, inclusive: false), TextSpan(start: 10, length: 5))
        XCTAssertEqual(span.adjusted(start: 5, length: 10, count: 2), TextSpan(start: 5, length: 7))
        XCTAssertEqual(span.adjusted(start: 5, length: 10, count: 2, inclusive: false), TextSpan(start: 7, length: 5))
        // Wholly replaced: becomes the replacement, or nothing.
        XCTAssertEqual(span.adjusted(start: 10, length: 10, count: 4), TextSpan(start: 10, length: 4))
        XCTAssertEqual(span.adjusted(start: 8, length: 15, count: 0).length, 0)
    }

    func testTypoFixAdjustsEveryLayer() throws {
        var (p, l, d, f) = makeProject()
        let old = "Teh interview began. I liked teh tool a lot. Then we stopped."
        let ns = old as NSString
        func span(_ s: String) -> TextSpan {
            let r = ns.range(of: s)
            return TextSpan(start: r.location, length: r.length)
        }
        let before = try p.addSelection(layer: l, file: f, spans: [span("Teh interview began.")], quote: "Teh interview began.")
        let inside = try p.addSelection(layer: l, file: f, spans: [span("I liked teh tool a lot.")], quote: "I liked teh tool a lot.")
        let after = try p.addSelection(layer: d, file: f, spans: [span("Then we stopped.")], quote: "Then we stopped.")
        let typo = ns.range(of: "teh tool")
        let impact = p.textEditImpact(file: f, start: typo.location, length: 3, replacement: "the")
        XCTAssertEqual(impact.resized, 1)
        XCTAssertEqual(impact.moved, 0)   // same length: the one after doesn't move
        let new = try p.applyTextEdit(file: f, oldText: old, start: typo.location, length: 3, replacement: "the",
                                      fingerprint: "sha256:new")
        XCTAssertEqual(new, "Teh interview began. I liked the tool a lot. Then we stopped.")
        XCTAssertEqual(text(p, inside, in: new), "I liked the tool a lot.")
        XCTAssertEqual(p.selection(inside)?.quote, "I liked the tool a lot.")
        XCTAssertEqual(text(p, before, in: new), "Teh interview began.")
        XCTAssertEqual(text(p, after, in: new), "Then we stopped.")
        XCTAssertEqual(p.files[f]?.fingerprint, "sha256:new")

        // A longer replacement moves what follows, in other layers too.
        let first = (new as NSString).range(of: "Teh")
        let newer = try p.applyTextEdit(file: f, oldText: new, start: first.location, length: 3, replacement: "The long",
                                        fingerprint: "sha256:newer")
        XCTAssertEqual(text(p, before, in: newer), "The long interview began.")
        XCTAssertEqual(text(p, inside, in: newer), "I liked the tool a lot.")
        XCTAssertEqual(text(p, after, in: newer), "Then we stopped.")
        XCTAssertEqual(p.selection(after)?.quote, "Then we stopped.")

        // Deleting all of a selection's text deletes it (and its evidence).
        let c = try p.addCode(layer: l, kind: .open, name: "Liking")
        try p.addEvidence(code: c, target: inside)
        let liked = (newer as NSString).range(of: " I liked the tool a lot.")
        XCTAssertEqual(p.textEditImpact(file: f, start: liked.location, length: liked.length, replacement: "").emptied, [inside])
        let last = try p.applyTextEdit(file: f, oldText: newer, start: liked.location, length: liked.length, replacement: "",
                                       fingerprint: "sha256:last")
        XCTAssertNil(p.selection(inside))
        XCTAssertEqual(p.code(c)?.evidence, [])
        XCTAssertEqual(text(p, after, in: last), "Then we stopped.")
        // Out of range is refused.
        XCTAssertThrowsError(try p.applyTextEdit(file: f, oldText: last, start: 500, length: 1, replacement: "x", fingerprint: ""))
    }

    func testIrrelevantStopsAtTheEdit() throws {
        var (p, l, _, f) = makeProject()
        let old = "aaaaa bbbbb ccccc"
        let irr = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 0, length: 6)], irrelevant: true)
        let sel = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 6, length: 5)], quote: "bbbbb")
        // Replace "a bb" (straddling both) with "X".
        let new = try p.applyTextEdit(file: f, oldText: old, start: 4, length: 4, replacement: "X", fingerprint: "")
        XCTAssertEqual(new, "aaaaXbbb ccccc")
        XCTAssertEqual(text(p, irr, in: new), "aaaa")
        XCTAssertEqual(text(p, sel, in: new), "Xbbb")
        let i = try XCTUnwrap(p.selection(irr)), s = try XCTUnwrap(p.selection(sel))
        XCTAssertFalse(i.overlaps(s))
    }

    func testWritesBackAsEncoded() {
        let text = "Line one — “quoted”\nLine two\n"
        // UTF-8, with and without a byte-order mark, LF and CRLF.
        for original in [Data("a\nb".utf8), Data([0xEF, 0xBB, 0xBF]) + Data("a\r\nb".utf8), Data("a\rb".utf8)] {
            let (data, changed) = TextNormaliser.data(for: text, like: original)
            XCTAssertFalse(changed)
            XCTAssertEqual(TextNormaliser.text(from: data), text)
            XCTAssertEqual(data.starts(with: [0xEF, 0xBB, 0xBF]), original.starts(with: [0xEF, 0xBB, 0xBF]))
        }
        let crlf = TextNormaliser.data(for: "a\nb", like: Data("x\r\ny".utf8)).data
        XCTAssertEqual(crlf, Data("a\r\nb".utf8))
        // UTF-16 both ways.
        for bom in [[UInt8(0xFF), 0xFE], [0xFE, 0xFF]] {
            let original = Data(bom) + (bom[0] == 0xFF ? Data([0x61, 0x00]) : Data([0x00, 0x61]))
            let (data, _) = TextNormaliser.data(for: text, like: original)
            XCTAssertEqual(Array(data.prefix(2)), bom)
            XCTAssertEqual(TextNormaliser.text(from: data), text)
        }
        // Windows-1252 stays Windows-1252 while it can.
        let cp1252 = Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94])   // café “q”
        XCTAssertEqual(TextNormaliser.text(from: cp1252), "café “q”")
        let (same, changed) = TextNormaliser.data(for: "café “q” €", like: cp1252)
        XCTAssertFalse(changed)
        XCTAssertEqual(same, Data([0x63, 0x61, 0x66, 0xE9, 0x20, 0x93, 0x71, 0x94, 0x20, 0x80]))
        let (utf8, switched) = TextNormaliser.data(for: "café ☕︎", like: cp1252)
        XCTAssertTrue(switched)
        XCTAssertEqual(TextNormaliser.text(from: utf8), "café ☕︎")
    }

    func testFullTextsWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ft-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("interviews"), withIntermediateDirectories: true)
        let ft = FullTexts(root: dir)
        try ft.write(Data("old".utf8), to: "interviews/a.txt")
        try ft.write(Data("new".utf8), to: "interviews/a.txt")
        XCTAssertEqual(try ft.text("interviews/a.txt"), "new")
    }

    func testMergeAdjacent() throws {
        var (p, l, d, f) = makeProject()
        let text = "One two. Three four.  Five six. Seven."
        let ns = text as NSString
        func span(_ s: String) -> TextSpan {
            let r = ns.range(of: s)
            return TextSpan(start: r.location, length: r.length)
        }
        let a = try p.addSelection(layer: l, file: f, spans: [span("One two.")], quote: "One two.")
        let b = try p.addSelection(layer: l, file: f, spans: [span("Three four.")], quote: "Three four.")
        let c = try p.addSelection(layer: l, file: f, spans: [span("Five six.")], quote: "Five six.")
        let e = try p.addSelection(layer: l, file: f, spans: [span("Seven.")], quote: "Seven.")
        let code = try p.addCode(layer: l, kind: .open, name: "Counting")
        let other = try p.addCode(layer: l, kind: .open, name: "Other")
        try p.addEvidence(code: code, target: a, memo: "First memo.")
        try p.addEvidence(code: code, target: b, memo: "Second memo.")
        try p.addEvidence(code: code, target: c)
        try p.addEvidence(code: other, target: c)
        let x = try p.addInterrelation(code: code, type: "Compare", members: [a, b])
        // Same codes, next to each other: a and b. c has another code too; e
        // has none (and isn't next to a highlight without codes).
        XCTAssertEqual(p.mergeCandidates(for: a, pages: [text]), [b])
        XCTAssertEqual(p.mergeCandidates(for: b, pages: [text]), [a])
        XCTAssertEqual(p.mergeCandidates(for: c, pages: [text]), [])
        XCTAssertEqual(p.mergeCandidates(for: e, pages: [text]), [])
        XCTAssertThrowsError(try p.mergeSelections(b, c, pages: [text]))

        let kept = try p.mergeSelections(b, a, pages: [text])
        XCTAssertEqual(kept, a)
        XCTAssertNil(p.selection(b))
        XCTAssertEqual(p.selection(a)?.spans, [TextSpan(start: 0, length: span("Three four.").end)])
        XCTAssertEqual(p.selection(a)?.quote, "One two. Three four.")
        XCTAssertEqual(p.code(code)?.memo(for: a), "First memo.\n\nSecond memo.")
        XCTAssertFalse(p.code(code)?.hasEvidence(b) ?? true)
        XCTAssertEqual(p.code(code)?.interrelations.first { $0.key == x }?.members, [a])

        // Two highlights without codes, and on a deductive layer with a
        // priori codes.
        let h1 = try p.addSelection(layer: d, file: f, spans: [span("One two.")])
        let h2 = try p.addSelection(layer: d, file: f, spans: [span("Three four.")])
        XCTAssertEqual(p.mergeCandidates(for: h1, pages: [text]), [h2])
        let apc = try p.addAprioriCode(name: "Order")
        try p.addAprioriEvidence(code: apc, selection: h1, memo: "m1")
        XCTAssertEqual(p.mergeCandidates(for: h1, pages: [text]), [])
        try p.addAprioriEvidence(code: apc, selection: h2, memo: "m2")
        try p.mergeSelections(h1, h2, pages: [text])
        XCTAssertEqual(p.layer(d)?.aprioriEvidence[apc], [Evidence(target: h1, memo: "m1\n\nm2")])
    }

    func testMergeRefusedOverIrrelevantGap() throws {
        var (p, l, _, f) = makeProject()
        let text = "Alpha.   Beta."
        let a = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 0, length: 6)])
        let b = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 9, length: 5)])
        _ = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 7, length: 1)], irrelevant: true)
        XCTAssertEqual(p.mergeCandidates(for: a, pages: [text]), [b])
        XCTAssertThrowsError(try p.mergeSelections(a, b, pages: [text]))
    }

    func testRotationsTableLayoutsAndProtocolResponsesRoundTrip() throws {
        var p = Project.new(title: "Round trip")
        let pdf = p.addFile(path: "articles/a.pdf", kind: .pdf)
        let txt = p.addFile(path: "interviews/b.txt", kind: .text)
        p.rotatePage(file: pdf, page: 2, by: 90)
        p.rotatePage(file: pdf, page: 0, by: -90)
        p.rotatePage(file: pdf, page: 4, by: 90)
        p.rotatePage(file: pdf, page: 4, by: 270)
        p.rotatePage(file: txt, page: 0, by: 90)
        XCTAssertEqual(p.files[pdf]?.rotations, [2: 90, 0: 270])
        XCTAssertEqual(p.files[txt]?.rotations, [:])
        p.settings.tableLayouts[.files] = #"{"columns":["q-1","q-2"],"note":"a: b, \"c\""}"#

        // A protocol with summaries and segments, for the report.
        let d = p.deductiveLayers[0].key
        let pr = p.addProtocol(title: "Interview")
        let q1 = try XCTUnwrap(p.addProtocolItem(to: pr, label: "Background"))
        let q2 = try XCTUnwrap(p.addProtocolItem(to: pr, label: "Tools"))
        let prompt = try p.addSelection(layer: d, file: txt, spans: [TextSpan(start: 0, length: 5)], segment: ProtocolSegment(item: q1, part: .prompt))
        let response = try p.addSelection(layer: d, file: txt, spans: [TextSpan(start: 6, length: 9)], segment: ProtocolSegment(item: q1, part: .response))
        try p.setFrameworkSummary("Ten years in the field, “mostly” fieldwork.", layer: d, row: txt, column: q1)

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("edits-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Workspace.create(at: dir, project: p)
        XCTAssertEqual(try Workspace.load(dir).project, p)
        let yaml = try String(contentsOf: dir.appendingPathComponent("files/\(pdf).yml"), encoding: .utf8)
        XCTAssertTrue(yaml.contains("rotations:\n  1: 270\n  3: 90"), yaml)

        let report = try XCTUnwrap(ProtocolResponses.make(p, protocol: pr, layer: d))
        XCTAssertEqual(report.rows.map(\.file), [txt])
        XCTAssertEqual(report.rows[0].cell(q1), ProtocolResponses.Cell(summary: "Ten years in the field, “mostly” fieldwork.",
                                                                    prompts: [prompt], responses: [response]))
        XCTAssertTrue(report.rows[0].cell(q2).isEmpty)
        XCTAssertNil(ProtocolResponses.make(p, protocol: pr, layer: p.inductiveLayers[0].key))
        XCTAssertEqual(report.csv(workingIDs: [txt: "EF 2"], title: { _ in "B" }),
                       "No.,File,1 Background,2 Tools\nEF 2,B,\"Ten years in the field, “mostly” fieldwork.\",\n")
    }
}

final class ProgressTests: XCTestCase {
    func testTimeIndicators() {
        let text = "We started. [~5 min] Then [~20 min] more [5 mins] and [~1.5 h], [~2–3 min] but not [5] or [min] or [~5 apples]."
        let found = TimeIndicators.ranges(in: text).map { (text as NSString).substring(with: $0) }
        XCTAssertEqual(found, ["[~5 min]", "[~20 min]", "[5 mins]", "[~1.5 h]", "[~2–3 min]"])
        // Trimmed from the ends of a selection, not from its middle.
        let ns = text as NSString
        let all = TextSpan(start: ns.range(of: "[~5 min]").location, length: ns.range(of: " more").location - ns.range(of: "[~5 min]").location)
        let trimmed = TimeIndicators.trim([all], pages: [text])
        XCTAssertEqual(trimmed.map { ns.substring(with: NSRange(location: $0.start, length: $0.length)) }, ["Then"])
        let middle = TextSpan(start: 0, length: ns.range(of: " Then").location + 5)
        XCTAssertEqual(TimeIndicators.trim([middle], pages: [text]), [middle])
        // Nothing but an indicator: nothing left.
        let only = ns.range(of: "[5 mins]")
        XCTAssertEqual(TimeIndicators.trim([TextSpan(start: only.location - 1, length: only.length + 2)], pages: [text]), [])
    }

    func testCodingProgress() throws {
        var p = Project.new(title: "Progress")
        let f = p.addFile(path: "a.txt", kind: .text)
        let l = p.inductiveLayers[0].key
        // 10 + 10 + 10 letters; spaces and the time indicator don't count.
        let text = "aaaaaaaaaa [~5 min] bbbbbbbbbb cccccccccc"
        let a = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 0, length: 10)])
        _ = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 20, length: 10)], irrelevant: true)
        _ = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 31, length: 5)])   // a highlight: pending
        XCTAssertEqual(CodingProgress.of(p, layer: l, file: f, pages: [text]), CodingProgress(coded: 0, irrelevant: 10, pending: 20))
        let c = try p.addCode(layer: l, kind: .open, name: "A")
        try p.addEvidence(code: c, target: a)
        let progress = CodingProgress.of(p, layer: l, file: f, pages: [text])
        XCTAssertEqual(progress, CodingProgress(coded: 10, irrelevant: 10, pending: 10))
        XCTAssertEqual(progress.fraction(progress.coded), 1.0 / 3.0, accuracy: 0.0001)
        // Ignored spans (speaker headers) leave the count.
        XCTAssertEqual(CodingProgress.of(p, layer: l, file: f, pages: [text], ignoring: [TextSpan(start: 31, length: 10)]).pending, 0)
        // Another layer has its own progress.
        XCTAssertEqual(CodingProgress.of(p, layer: p.deductiveLayers[0].key, file: f, pages: [text]).pending, 30)
    }
}

final class ProtocolOutcomesTests: XCTestCase {
    func testCountsPerItemAndPart() throws {
        var p = Project.new(title: "Outcomes")
        let f = p.addFile(path: "a.txt", kind: .text)
        let g = p.addFile(path: "b.txt", kind: .text)
        let d = p.deductiveLayers[0].key, i = p.inductiveLayers[0].key
        let pr = p.addProtocol(title: "Interview")
        let q1 = try XCTUnwrap(p.addProtocolItem(to: pr, label: "Tools"))
        let q2 = try XCTUnwrap(p.addProtocolItem(to: pr, label: "Worries"))
        // In a.txt: Q1 prompt 0–20, response 20–100; Q2 response 100–200.
        _ = try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 0, length: 20)], segment: ProtocolSegment(item: q1, part: .prompt))
        _ = try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 20, length: 80)], segment: ProtocolSegment(item: q1, part: .response))
        _ = try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 100, length: 100)], segment: ProtocolSegment(item: q2, part: .response))
        // Open code "Speed": one instance in Q1's response, one across Q1's
        // response and Q2's response, one in b.txt (no segments).
        let speed = try p.addCode(layer: i, kind: .open, name: "Speed")
        let s1 = try p.addSelection(layer: i, file: f, spans: [TextSpan(start: 30, length: 10)])
        let s2 = try p.addSelection(layer: i, file: f, spans: [TextSpan(start: 90, length: 20)])
        let s3 = try p.addSelection(layer: i, file: g, spans: [TextSpan(start: 0, length: 10)])
        for s in [s1, s2, s3] { try p.addEvidence(code: speed, target: s) }
        let other = try p.addCode(layer: i, kind: .open, name: "Doubt")
        try p.addEvidence(code: other, target: s2)
        let theme = try p.addCode(layer: i, kind: .theorising, name: "Pace")
        try p.addEvidence(code: theme, target: speed)
        try p.addEvidence(code: theme, target: other)

        let r = try XCTUnwrap(ProtocolOutcomes.make(p, protocol: pr, segmentLayer: d, coding: .open, codeLayer: i))
        XCTAssertEqual(r.columns.count, 4)
        XCTAssertEqual(r.rows.map(\.code), [other, speed])   // by name
        let row = try XCTUnwrap(r.rows.first { $0.code == speed })
        XCTAssertEqual(row.count(.init(item: q1, part: .prompt)), 0)
        XCTAssertEqual(row.count(.init(item: q1, part: .response)), 2)
        XCTAssertEqual(row.count(.init(item: q2, part: .response)), 1)
        XCTAssertEqual(row.elsewhere, [s3])
        XCTAssertEqual(row.instances.count, 3)
        XCTAssertEqual(r.maxCount, 2)
        // A theorising code counts the selections beneath it, once each.
        let t = try XCTUnwrap(ProtocolOutcomes.make(p, protocol: pr, segmentLayer: d, coding: .theorising, codeLayer: i))
        XCTAssertEqual(t.rows.first?.instances.count, 3)
        XCTAssertEqual(t.rows.first?.count(.init(item: q2, part: .response)), 1)
        // A priori codes, from a deductive layer.
        let apc = try p.addAprioriCode(name: "Ease")
        let e = try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 5, length: 5)])
        try p.addAprioriEvidence(code: apc, selection: e)
        let a = try XCTUnwrap(ProtocolOutcomes.make(p, protocol: pr, segmentLayer: d, coding: .apriori, codeLayer: d))
        XCTAssertEqual(a.rows.first?.count(.init(item: q1, part: .prompt)), 1)
        // The wrong kind of layer gives nothing.
        XCTAssertNil(ProtocolOutcomes.make(p, protocol: pr, segmentLayer: d, coding: .open, codeLayer: d))
        XCTAssertTrue(r.csv(workingIDs: [:], title: { p.code($0)?.name ?? "" })
            .hasPrefix("No.,Code,1 Tools (Prompt),1 Tools (Response),2 Worries (Prompt),2 Worries (Response),Elsewhere,Total\n,Doubt,0,1,0,1,0,1\n"))
    }
}

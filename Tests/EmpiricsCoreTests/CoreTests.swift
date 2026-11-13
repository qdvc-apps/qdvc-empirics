import Foundation
import XCTest
@testable import EmpiricsCore

final class SHA256Tests: XCTestCase {
    func testKnownVectors() {
        XCTAssertEqual(SHA256.hex(Data()), "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(SHA256.hex(Data("abc".utf8)), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
        XCTAssertEqual(SHA256.hex(Data(repeating: 0x61, count: 1000)),
                       "41edece42d63e8d9bf515a9ba6932e1c20cbc9f5a5d134645adb5db1b9737ea3")
    }
}

final class TurnDetectorTests: XCTestCase {
    /// The example from the specification, with its inconsistent case,
    /// colons and line breaks.
    let transcript = """
    Alice Bob
    I now like to ask you a little bit about the user interface for QDVC Empirics. Do you think it's user friendly?

    John Smith:
    Well, it's certainly an improvement over alternatives. The existing crop of QDA software is very limited. But I'm still getting used to the user interface of QDVC Empirics, to be honest.

    ALICE BOB:
    Which part of the user interface is taking the longest to get used to?

    John Smith

    Oh, that's a hard one. I can't remember off the top of my head. Is it okay if I pull it up on my laptop here?
    """

    func testCandidates() {
        let c = TurnDetector.candidates(in: transcript)
        XCTAssertEqual(c.map(\.speaker), ["alice bob", "john smith"])
        XCTAssertEqual(c.map(\.count), [2, 2])
        XCTAssertEqual(c[0].label, "Alice Bob")
    }

    func testTurns() {
        let turns = TurnDetector.turns(in: transcript, speakers: ["alice bob", "john smith"])
        XCTAssertEqual(turns.map(\.speaker), ["alice bob", "john smith", "alice bob", "john smith"])
        let ns = transcript as NSString
        func body(_ t: Turn) -> String { ns.substring(with: NSRange(location: t.body.start, length: t.body.length)) }
        XCTAssertTrue(body(turns[0]).hasPrefix("I now like"))
        XCTAssertTrue(body(turns[0]).hasSuffix("user friendly?"))
        XCTAssertTrue(body(turns[1]).hasPrefix("Well, it's"))
        XCTAssertEqual(body(turns[2]), "Which part of the user interface is taking the longest to get used to?")
        XCTAssertTrue(body(turns[3]).hasPrefix("Oh, that's"))
        XCTAssertEqual(turns[2].label, "ALICE BOB")
        XCTAssertEqual(TurnDetector.turn(at: turns[1].body.start + 5, in: turns)?.speaker, "john smith")
    }

    func testInlineTimestampsAndMarkdown() {
        let text = """
        Interview notes, 3 March.

        [00:00:05] Interviewer: Thanks for coming. Shall we start?
        [00:00:09] P3: Sure: happy to.
        **Interviewer:** Great.
        P3: Okay.
        """
        let c = TurnDetector.candidates(in: text)
        XCTAssertEqual(Set(c.map(\.speaker)), ["interviewer", "p3"])
        let turns = TurnDetector.turns(in: text, speakers: ["interviewer", "p3"])
        XCTAssertEqual(turns.map(\.speaker), ["interviewer", "p3", "interviewer", "p3"])
        let ns = text as NSString
        XCTAssertEqual(ns.substring(with: NSRange(location: turns[1].body.start, length: turns[1].body.length)), "Sure: happy to.")
        XCTAssertEqual(ns.substring(with: NSRange(location: turns[2].body.start, length: turns[2].body.length)), "Great.")
    }

    func testSentencesAreNotHeaders() {
        XCTAssertNil(TurnDetector.header("Yes."))
        XCTAssertNil(TurnDetector.header("Well, I think so"))
        XCTAssertNil(TurnDetector.header("This is a long line that is certainly not a speaker label at all"))
        XCTAssertNil(TurnDetector.header("10:30"))
        XCTAssertNotNil(TurnDetector.header("Dr. Jane O'Neil:"))
    }

    func testSuggest() {
        let r = [Researcher(key: "r-00000001", firstName: "Alice", lastName: "Bob")]
        let i = [Interviewee(key: "i-00000001", firstName: "John", lastName: "Smith")]
        XCTAssertEqual(TurnDetector.suggest("ALICE BOB:", researchers: r, interviewees: i), "r-00000001")
        XCTAssertEqual(TurnDetector.suggest("Smith, John", researchers: r, interviewees: i), "i-00000001")
        XCTAssertEqual(TurnDetector.suggest("john", researchers: r, interviewees: i), "i-00000001")
        XCTAssertNil(TurnDetector.suggest("Interviewer", researchers: r, interviewees: i))
    }
}

final class RuleTests: XCTestCase {
    func makeProject() -> (Project, layer: String, file: String) {
        var p = Project.new(title: "Test")
        let f = p.addFile(path: "interviews/one.txt", kind: .text)
        return (p, p.inductiveLayers[0].key, f)
    }

    func testIrrelevantNeverEvidence() throws {
        var (p, l, f) = makeProject()
        let s = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 10, length: 20)], quote: "x")
        let c = try p.addCode(layer: l, kind: .open, name: "Frustration")
        try p.addEvidence(code: c, target: s)

        // Evidence can't become irrelevant, nor can text overlapping it.
        XCTAssertThrowsError(try p.setIrrelevant(s, true))
        XCTAssertThrowsError(try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 25, length: 10)], irrelevant: true))

        // Irrelevant text can't be selected.
        let irr = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 100, length: 50)], irrelevant: true)
        XCTAssertThrowsError(try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 140, length: 20)]))
        // Touching (not overlapping) is fine.
        XCTAssertNoThrow(try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 150, length: 5)]))
        // Another layer has its own rules.
        let l2 = p.addLayer(name: "Second lens", kind: .inductive)
        XCTAssertNoThrow(try p.addSelection(layer: l2, file: f, spans: [TextSpan(start: 140, length: 20)]))
        // An irrelevant selection is never accepted as evidence.
        XCTAssertNotNil(p.evidenceProblem(code: c, target: irr))
        XCTAssertEqual(p.files[f]?.status, .inProgress)
    }

    func testIrrelevantMerges() throws {
        var (p, l, f) = makeProject()
        let a = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 0, length: 10)], irrelevant: true)
        let b = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 10, length: 5)], irrelevant: true)
        XCTAssertEqual(a, b)
        XCTAssertEqual(p.layer(l)?.selections[f]?.count, 1)
        XCTAssertEqual(p.layer(l)?.selections[f]?.first?.spans, [TextSpan(start: 0, length: 15)])
    }

    func testDuplicateSelectionReused() throws {
        var (p, l, f) = makeProject()
        let a = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 5, length: 10)])
        let b = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 5, length: 10)])
        XCTAssertEqual(a, b)
        let c = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 6, length: 10)])
        XCTAssertNotEqual(a, c)
    }

    func testAxialCycles() throws {
        var (p, l, _) = makeProject()
        let o = try p.addCode(layer: l, kind: .open, name: "Open")
        let a = try p.addCode(layer: l, kind: .axial, name: "A")
        let b = try p.addCode(layer: l, kind: .axial, name: "B")
        try p.addEvidence(code: a, target: o)
        try p.addEvidence(code: b, target: a)
        XCTAssertThrowsError(try p.addEvidence(code: a, target: b))   // loop
        XCTAssertThrowsError(try p.addEvidence(code: a, target: a))   // itself
        XCTAssertThrowsError(try p.addEvidence(code: o, target: a))   // open codes take selections
        let index = ProjectIndex(p)
        XCTAssertEqual(index.parents[a], [b])
    }

    func testDeleteSelectionUnlinks() throws {
        var (p, l, f) = makeProject()
        let s1 = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 0, length: 5)])
        let s2 = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 10, length: 5)])
        let c = try p.addCode(layer: l, kind: .open, name: "C")
        try p.addEvidence(code: c, target: s1, memo: "why")
        try p.addEvidence(code: c, target: s2)
        p.addInterrelation(code: c, type: "Compare", members: [s1, s2])
        p.deleteSelection(s1)
        XCTAssertEqual(p.code(c)?.evidence.map(\.target), [s2])
        XCTAssertEqual(p.code(c)?.interrelations.first?.members, [s2])
    }

    func testMoveComponent() throws {
        var (p, l, f) = makeProject()
        let s1 = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 0, length: 5)])
        let s2 = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 10, length: 5)])
        let s3 = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 20, length: 5)])
        let c1 = try p.addCode(layer: l, kind: .open, name: "C1")
        let c2 = try p.addCode(layer: l, kind: .open, name: "C2")
        let ax = try p.addCode(layer: l, kind: .axial, name: "Theme")
        let lone = try p.addCode(layer: l, kind: .open, name: "Lone")
        try p.addEvidence(code: c1, target: s1)
        try p.addEvidence(code: c2, target: s2)
        try p.addEvidence(code: c2, target: s1)   // s1 joins c1 and c2
        try p.addEvidence(code: ax, target: c2)
        try p.addEvidence(code: lone, target: s3)

        let comp = p.component(of: c1)
        XCTAssertEqual(comp.selections, [s1, s2])
        XCTAssertEqual(comp.codes, [c1, c2, ax])

        let l2 = p.addLayer(name: "Other", kind: .inductive)
        try p.move(c1, toLayer: l2)
        XCTAssertEqual(p.layerKey(holding: s2), l2)
        XCTAssertEqual(p.layerKey(holding: ax), l2)
        XCTAssertEqual(p.layerKey(holding: s3), l)
        XCTAssertEqual(p.layerKey(holding: lone), l)
    }

    func testMoveRefusedOnIrrelevantClash() throws {
        var (p, l, f) = makeProject()
        let s = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 0, length: 10)])
        let l2 = p.addLayer(name: "Other", kind: .inductive)
        try p.addSelection(layer: l2, file: f, spans: [TextSpan(start: 5, length: 10)], irrelevant: true)
        XCTAssertThrowsError(try p.move(s, toLayer: l2))
        XCTAssertEqual(p.layerKey(holding: s), l)
    }

    func testSheetBlocking() throws {
        var (p, _, f) = makeProject()
        let cb = AttributeSheet(key: "ast-00000001", title: "Interview", appliesTo: [.files], questions: [
            AttributeSheetQuestion(key: "q-00000001", label: "Setting", type: .chooseOne, options: ["Home", "Work"],
                             strict: false, requirement: .blocking),
            AttributeSheetQuestion(key: "q-00000002", label: "Mood", type: .text, requirement: .flagged),
            AttributeSheetQuestion(key: "q-00000003", label: "Way too long a label for this", requirement: .optional),
        ])
        XCTAssertEqual(cb.questions[2].label.count, AttributeSheetQuestion.maxLabelLength)
        p.attributeSheets[cb.key] = cb
        try p.associate(attributeSheet: cb.key, with: f)
        var sheet = ResponseSheet(id: ResponseID(attributeSheet: cb.key, target: f, researcher: "r-00000001"))
        XCTAssertThrowsError(try p.saveSheet(sheet))
        sheet.answers["q-00000001"] = .one("Café")
        XCTAssertNoThrow(try p.saveSheet(sheet))
        let saved = p.responses[sheet.id]!
        XCTAssertFalse(SheetCompleteness.of(saved.answers, against: p.attributeSheets[cb.key]!).isComplete)
        // Not strict: the new option joins the attribute sheet.
        XCTAssertEqual(p.attributeSheets[cb.key]?.questions[0].options, ["Home", "Work", "Café"])
        // An attribute sheet for codes can't go on a file.
        p.attributeSheets["ast-00000002"] = AttributeSheet(key: "ast-00000002", title: "Codes only", appliesTo: [.openCodes])
        XCTAssertThrowsError(try p.associate(attributeSheet: "ast-00000002", with: f))
    }

    func testAttributeSheetsForInterviewees() throws {
        var p = Project.new(title: "People")
        p.interviewees = [Interviewee(key: "i-00000001", firstName: "John", lastName: "Smith")]
        p.attributeSheets["ast-00000001"] = AttributeSheet(key: "ast-00000001", title: "Background", appliesTo: [.interviewees])
        p.attributeSheets["ast-00000002"] = AttributeSheet(key: "ast-00000002", title: "Files only", appliesTo: [.files])
        try p.associate(attributeSheet: "ast-00000001", with: "i-00000001")
        XCTAssertThrowsError(try p.associate(attributeSheet: "ast-00000002", with: "i-00000001"))
        XCTAssertEqual(p.attributeSheets(for: "i-00000001").map(\.key), ["ast-00000001"])
        try p.saveSheet(ResponseSheet(id: ResponseID(attributeSheet: "ast-00000001", target: "i-00000001")))
        let report = try XCTUnwrap(AttributeSheetReport.make(p, attributeSheet: "ast-00000001", title: { $0 }, person: { $0 }))
        XCTAssertEqual(report.rows.map(\.target), ["i-00000001"])
        var dropped = p
        dropped.deleteAttributeSheet("ast-00000001")
        XCTAssertEqual(dropped.interviewees[0].attributeSheets, [])
        // Deleting the interviewee deletes the sheets about them.
        p.deleteInterviewee("i-00000001")
        XCTAssertTrue(p.responses.isEmpty)
    }

    func testAnswersAndTableColumns() throws {
        var p = Project.new(title: "Columns")
        let f = p.addFile(path: "a.txt", kind: .text)
        p.researchers = [Researcher(key: "r-00000002", firstName: "Zoe", lastName: "Ash"),
                         Researcher(key: "r-00000001", firstName: "Al", lastName: "Bo")]
        p.attributeSheets["ast-00000001"] = AttributeSheet(key: "ast-00000001", title: "Sheet", appliesTo: [.files], questions: [
            AttributeSheetQuestion(key: "q-00000001", label: "Setting", type: .text),
            AttributeSheetQuestion(key: "q-00000002", label: "Mood", type: .text)])
        try p.saveSheet(ResponseSheet(id: ResponseID(attributeSheet: "ast-00000001", target: f, researcher: "r-00000001"),
                                      answers: ["q-00000001": .text("Home")]))
        try p.saveSheet(ResponseSheet(id: ResponseID(attributeSheet: "ast-00000001", target: f, researcher: "r-00000002"),
                                      answers: ["q-00000001": .text("Work"), "q-00000002": .text("Calm")]))
        // In the order of the researchers list; unanswered left out.
        let setting = p.answers(attributeSheet: "ast-00000001", question: "q-00000001", target: f)
        XCTAssertEqual(setting.map { $0.researcher }, ["r-00000002", "r-00000001"])
        XCTAssertEqual(setting.map { $0.answer }, [.text("Work"), .text("Home")])
        XCTAssertEqual(p.answers(attributeSheet: "ast-00000001", question: "q-00000002", target: f).map { $0.researcher }, ["r-00000002"])

        p.settings.tableColumns = [.files: ["q-00000001", "q-00000002"]]
        p.deleteQuestion("q-00000002", from: "ast-00000001")
        XCTAssertEqual(p.settings.tableColumns[.files], ["q-00000001"])
        p.deleteAttributeSheet("ast-00000001")
        XCTAssertNil(p.settings.tableColumns[.files])
    }
}

final class WorkspaceTests: XCTestCase {
    var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("empirics-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    func richProject() throws -> Project {
        var p = Project.new(title: "Zoom fatigue: a study")
        p.settings.description = "Two lines\nof description"
        p.settings.interlocutorLayer = true
        let f = p.addFile(path: "interviews/SF-01.txt", kind: .text, title: "Interview 1", fingerprint: "sha256:00")
        p.files[f]!.customID = "SF-2026-KXV-01"
        p.files[f]!.date = "2026-03-14"
        let pdf = p.addFile(path: "papers/wang 2022.pdf", kind: .pdf)
        let l = p.inductiveLayers[0].key
        let s1 = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 3, length: 12)],
                                    quote: "It's \"great\": really\n#not", by: "r-00000001")
        let s2 = try p.addSelection(layer: l, file: pdf, spans: [TextSpan(page: 0, start: 5, length: 9), TextSpan(page: 1, start: 0, length: 4)],
                                    quote: "multi page")
        try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 40, length: 4)], irrelevant: true)
        let c = try p.addCode(layer: l, kind: .open, name: "Tired eyes")
        try p.addEvidence(code: c, target: s1, memo: "She names the screen.\nTwice.")
        try p.addEvidence(code: c, target: s2)
        var code = p.code(c)!
        code.comments = ["A comment", "- starts with a dash"]
        code.questions = ["Is this about light, or attention?"]
        code.description = "Physical strain from screens."
        p.updateCode(code)
        p.addInterrelation(code: c, type: "Contrast", members: [s1, s2], description: "Home vs office")
        let ax = try p.addCode(layer: l, kind: .axial, name: "Embodiment")
        try p.addEvidence(code: ax, target: c, memo: "")
        let l2 = p.addLayer(name: "Second coder", kind: .inductive)
        p.layers[p.layerIndex(l2)!].description = "Blind recode"
        try p.addCode(layer: l2, kind: .open, name: "Empty")
        p.attributeSheets["ast-00000001"] = AttributeSheet(key: "ast-00000001", title: "Interview sheet", description: "About the interview",
                                               appliesTo: [.files, .openCodes], questions: [
            AttributeSheetQuestion(key: "q-00000001", label: "Setting", text: "Where did it happen?", type: .chooseOne,
                             options: ["Home", "Office"], strict: true, requirement: .blocking),
            AttributeSheetQuestion(key: "q-00000002", label: "Notes", text: "Anything else?", type: .text),
            AttributeSheetQuestion(key: "q-00000003", label: "Tools", type: .chooseMany, options: ["Zoom", "Teams"]),
        ])
        try p.associate(attributeSheet: "ast-00000001", with: f)
        try p.associate(attributeSheet: "ast-00000001", with: c)
        try p.saveSheet(ResponseSheet(id: ResponseID(attributeSheet: "ast-00000001", target: f, researcher: "r-00000001"),
                                      answers: ["q-00000001": .one("Home"), "q-00000002": .text("Line one\nLine two"),
                                                "q-00000003": .many(["Zoom", "Teams"])]))
        p.researchers = [Researcher(key: "r-00000001", firstName: "Alice", lastName: "Bob")]
        p.interviewees = [Interviewee(key: "i-00000001", firstName: "John", lastName: "Smith", consentForm: "consent/js.pdf")]
        p.speakerMaps[f] = SpeakerMap(fileKey: f, assignments: [SpeakerAssignment(label: "Alice Bob", person: "r-00000001"),
                                                                  SpeakerAssignment(label: "John Smith", person: "i-00000001")],
                                      ignored: ["okay"])
        p.attributeSheets["ast-00000003"] = AttributeSheet(key: "ast-00000003", title: "Interviewee background", appliesTo: [.interviewees],
                                               questions: [AttributeSheetQuestion(key: "q-00000004", label: "Role", type: .text)])
        try p.associate(attributeSheet: "ast-00000003", with: "i-00000001")
        try p.saveSheet(ResponseSheet(id: ResponseID(attributeSheet: "ast-00000003", target: "i-00000001", researcher: "r-00000001"),
                                      answers: ["q-00000004": .text("Nurse")]))
        p.settings.tableColumns = [.files: ["q-00000001", "q-00000003"], .interviewees: ["q-00000004"]]

        // Deductive: a protocol with a prompt and a response segment, an a
        // priori code with evidence, a link to it and a Framework Matrix cell.
        let d = p.deductiveLayers[0].key
        let pr = p.addProtocol(title: "Interview protocol")
        let q1 = p.addProtocolItem(to: pr, label: "Q1", text: "How do you feel after a long call?")!
        _ = p.addProtocolItem(to: pr, label: "Q2")
        try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 0, length: 3)], quote: "It'",
                           segment: ProtocolSegment(item: q1, part: .prompt))
        try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 3, length: 12)], quote: "s \"great\": r",
                           segment: ProtocolSegment(item: q1, part: .response))
        let apc = try p.addAprioriCode(name: "Technostress")
        var def = p.aprioriCodes[apc]!
        def.definition = "Strain from technology use."
        def.included = "Fatigue, overload"
        def.excluded = "General work stress"
        def.example = "My eyes hurt after Zoom."
        def.counterExample = "I was tired after the commute."
        def.source = "Tarafdar et al. (2007)"
        try p.updateAprioriCode(def)
        let ds = try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 20, length: 10)], quote: "evidence!!")
        try p.addAprioriEvidence(code: apc, selection: ds, memo: "Clear case.")
        try p.addLink(from: c, to: apc, type: .refines, memo: "Eyes, specifically.")
        try p.setFrameworkSummary("Strain after calls.\nMostly eyes.", layer: d, row: f, column: apc)
        try p.setFrameworkSummary("Answered at length.", layer: d, row: "i-00000001", column: q1)
        return p
    }

    func testRoundTrip() throws {
        let p = try richProject()
        try Workspace.create(at: dir, project: p)
        let loaded = try Workspace.load(dir)
        XCTAssertEqual(loaded.notes, [])
        XCTAssertEqual(loaded.project, p)

        // Saving again writes nothing new.
        let before = Workspace.signature(dir)
        Thread.sleep(forTimeInterval: 0.01)
        try Workspace.save(loaded.project, parts: Workspace.allParts(of: loaded.project), to: dir)
        XCTAssertEqual(before, Workspace.signature(dir))
    }

    func testChangedPartsAndDeletion() throws {
        var p = try richProject()
        try Workspace.create(at: dir, project: p)
        let old = p
        let main = p.inductiveLayers[0]
        let s = main.selections.values.flatMap { $0 }.first { !$0.irrelevant && $0.spans.count == 1 }!
        p.deleteSelection(s.key)
        let parts = Workspace.changedParts(from: old, to: p)
        XCTAssertTrue(parts.contains(.selections(layer: main.key, file: s.fileKey)))
        XCTAssertFalse(parts.contains(.project))
        try Workspace.save(p, parts: parts, to: dir)
        XCTAssertEqual(try Workspace.load(dir).project, p)

        // Deleting a layer removes its folder.
        let old2 = p
        let l2 = p.inductiveLayers[1].key
        try p.deleteLayer(l2)
        try Workspace.save(p, parts: Workspace.changedParts(from: old2, to: p), to: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("layers/\(l2)").path))
        XCTAssertEqual(try Workspace.load(dir).project, p)
    }

    func testMoveBetweenLayersOnDisk() throws {
        var p = try richProject()
        try Workspace.create(at: dir, project: p)
        let old = p
        let from = p.inductiveLayers[0].key
        let code = p.inductiveLayers[0].codes.values.first { $0.kind == .axial }!
        try p.move(code.key, toLayer: p.inductiveLayers[1].key)
        try Workspace.save(p, parts: Workspace.changedParts(from: old, to: p), to: dir)
        let reloaded = try Workspace.load(dir).project
        XCTAssertEqual(reloaded, p)
        XCTAssertNil(reloaded.layer(from)?.codes[code.key])
        // Never to a layer of the other kind.
        XCTAssertThrowsError(try p.move(code.key, toLayer: p.deductiveLayers[0].key))
    }

    func testHandWrittenYAML() throws {
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("layers/l-0000000a/codes"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: dir.appendingPathComponent("files"), withIntermediateDirectories: true)
        try """
        title: Hand made
        key: p-12345678
        """.write(to: dir.appendingPathComponent("project.yml"), atomically: true, encoding: .utf8)
        try """
        path: a.md
        """.write(to: dir.appendingPathComponent("files/f-0000000b.yml"), atomically: true, encoding: .utf8)
        try """
        name: Hope
        evidence:
          - s-00000001
        """.write(to: dir.appendingPathComponent("layers/l-0000000a/codes/c-0000000c.yml"), atomically: true, encoding: .utf8)
        let loaded = try Workspace.load(dir)
        XCTAssertEqual(loaded.project.files["f-0000000b"]?.kind, .markdown)
        // A layer that doesn't give its kind is inductive.
        let layer = try XCTUnwrap(loaded.project.layer("l-0000000a"))
        XCTAssertEqual(layer.kind, .inductive)
        XCTAssertEqual(layer.codes["c-0000000c"]?.name, "Hope")
        // Evidence to a selection that doesn't exist is ignored, with a note.
        XCTAssertEqual(layer.codes["c-0000000c"]?.evidence, [])
        // A project always has a layer of each kind.
        XCTAssertEqual(loaded.project.deductiveLayers.count, 1)
        XCTAssertFalse(loaded.notes.isEmpty)
    }

    func testConflictMarkersReported() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "<<<<<<< HEAD\ntitle: A\n=======\ntitle: B\n>>>>>>> x\n".write(to: dir.appendingPathComponent("project.yml"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try Workspace.load(dir)) { error in
            XCTAssertTrue((error as? WorkspaceError)?.message.contains("merge conflict") == true)
        }
    }

    func testNoQuotesWhenSwitchedOff() throws {
        var p = Project.new(title: "Private")
        p.settings.storeQuotes = false
        let f = p.addFile(path: "x.txt", kind: .text)
        let s = try p.addSelection(layer: p.layers[0].key, file: f, spans: [TextSpan(start: 0, length: 3)], quote: "abc")
        XCTAssertEqual(p.selection(s)?.quote, "")
    }
}

final class AnchoringTests: XCTestCase {
    func testReanchor() throws {
        var p = Project.new(title: "T")
        let f = p.addFile(path: "x.txt", kind: .text)
        let l = p.layers[0].key
        let original = "Hello there. The quick brown fox. Goodbye."
        let ns = original as NSString
        let r = ns.range(of: "quick brown fox")
        let s = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: r.location, length: r.length)],
                                   quote: ns.substring(with: r))
        let gone = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 0, length: 5)], quote: "Hello")
        let edited = "Hi there, friend. The quick brown fox. Goodbye."
        let result = Anchoring.reanchor(&p, file: f, pages: [edited])
        XCTAssertEqual(result.moved, 1)
        XCTAssertEqual(result.lost, [gone])
        let moved = p.selection(s)!
        XCTAssertEqual(TextNormaliser.quote(moved.spans, pages: [edited]), "quick brown fox")
    }

    func testCheckNewVersion() throws {
        var p = Project.new(title: "T")
        let f = p.addFile(path: "x.txt", kind: .text)
        let l = p.layers[0].key
        let old = "Intro line.\nThe quick brown fox jumps.\nA lazy dog sleeps here.\nGoodbye now."
        let ns = old as NSString
        func span(_ text: String) -> [TextSpan] {
            let r = ns.range(of: text)
            return [TextSpan(start: r.location, length: r.length)]
        }
        let same = try p.addSelection(layer: l, file: f, spans: span("Intro line."), quote: "Intro line.")
        let moved = try p.addSelection(layer: l, file: f, spans: span("quick brown fox"), quote: "quick brown fox")
        let wrapped = try p.addSelection(layer: l, file: f, spans: span("A lazy dog sleeps"), quote: "A lazy dog sleeps")
        let gone = try p.addSelection(layer: l, file: f, spans: span("Goodbye now."), quote: "Goodbye now.")
        let irrelevant = try p.addSelection(layer: l, file: f, spans: span("jumps."), irrelevant: true)
        let edited = "Intro line.\nA new sentence. The quick brown fox jumps.\nA lazy\ndog  sleeps here.\nFarewell."

        let checks = Anchoring.check(p, file: f, newPages: [edited], oldPages: [old])
        func fate(_ key: String) -> Anchoring.Fate? { checks.first { $0.selection == key }?.fate }
        XCTAssertEqual(fate(same), .unchanged)
        XCTAssertEqual(fate(gone), .lost)
        guard case .moved(let ms, _)? = fate(moved) else { return XCTFail("not moved") }
        XCTAssertEqual(TextNormaliser.quote(ms, pages: [edited]), "quick brown fox")
        // Found again although its line breaks and spaces changed.
        guard case .moved(let ws, let wq)? = fate(wrapped) else { return XCTFail("not found across white space") }
        XCTAssertEqual(TextNormaliser.quote(ws, pages: [edited]), "A lazy\ndog  sleeps")
        XCTAssertEqual(wq, "A lazy\ndog  sleeps")
        // Irrelevant text has no quote: it is looked for with the old text.
        guard case .moved(let irs, _)? = fate(irrelevant) else { return XCTFail("irrelevant text not found") }
        XCTAssertEqual(TextNormaliser.quote(irs, pages: [edited]), "jumps.")
        // Without the old text it can only be kept where it is.
        let blind = Anchoring.check(p, file: f, newPages: [edited], oldPages: nil)
        XCTAssertEqual(blind.first { $0.selection == irrelevant }?.fate, .unverified)

        var kept = p
        Anchoring.apply(checks, to: &kept, deleteLost: false)
        XCTAssertNotNil(kept.selection(gone))
        XCTAssertEqual(kept.selection(wrapped)?.quote, "A lazy\ndog  sleeps")
        XCTAssertEqual(kept.selection(irrelevant)?.quote, "")
        XCTAssertEqual(TextNormaliser.quote(kept.selection(moved)!.spans, pages: [edited]), "quick brown fox")
        let starts = kept.layers[0].selections[f]!.map { $0.first!.start }
        XCTAssertEqual(starts, starts.sorted())
        var trimmed = p
        Anchoring.apply(checks, to: &trimmed, deleteLost: true)
        XCTAssertNil(trimmed.selection(gone))
        XCTAssertNotNil(trimmed.selection(same))
    }

    func testNormaliser() {
        let data = Data([0xEF, 0xBB, 0xBF]) + Data("a\r\nb\rc".utf8)
        XCTAssertEqual(TextNormaliser.text(from: data), "a\nb\nc")
        let latin = Data([0x63, 0x61, 0x66, 0xE9])   // "café" in Windows-1252
        XCTAssertEqual(TextNormaliser.text(from: latin), "café")
    }

    func testRelativePath() {
        let ft = FullTexts(root: URL(fileURLWithPath: "/tmp/full texts"))
        XCTAssertEqual(ft.relativePath(of: URL(fileURLWithPath: "/tmp/full texts/a/b.txt")), "a/b.txt")
        XCTAssertNil(ft.relativePath(of: URL(fileURLWithPath: "/tmp/other/b.txt")))
        XCTAssertEqual(ft.url("a/b.txt").path, "/tmp/full texts/a/b.txt")
    }
}

final class WorkingIDTests: XCTestCase {
    func testAlphabeticalAndRenumbering() throws {
        var p = Project.new(title: "IDs")
        let b = p.addFile(path: "b.txt", kind: .text, title: "Beta")
        let a = p.addFile(path: "a.txt", kind: .text, title: "alpha")
        let l = p.inductiveLayers[0].key
        let o2 = try p.addCode(layer: l, kind: .open, name: "Zebra")
        let o1 = try p.addCode(layer: l, kind: .open, name: "Apple 10")
        let o3 = try p.addCode(layer: l, kind: .open, name: "Apple 9")
        let ax = try p.addCode(layer: l, kind: .axial, name: "Theme")
        var ids = WorkingIDs.compute(p)
        XCTAssertEqual(ids[a], "EF 1")
        XCTAssertEqual(ids[b], "EF 2")
        XCTAssertEqual(ids[o3], "OC 1")   // numbers in order: 9 before 10
        XCTAssertEqual(ids[o1], "OC 2")
        XCTAssertEqual(ids[o2], "OC 3")
        XCTAssertEqual(ids[ax], "AC 1")
        // A new file sorting first renumbers the others.
        let c = p.addFile(path: "0.txt", kind: .text, title: "Aardvark")
        ids = ProjectIndex(p).workingID
        XCTAssertEqual(ids[c], "EF 1")
        XCTAssertEqual(ids[a], "EF 2")
        XCTAssertEqual(ids[b], "EF 3")
    }
}

final class ReportTests: XCTestCase {
    func testCodingChartColumnsLevelsAndEdges() throws {
        var p = Project.new(title: "Chart")
        let l = p.inductiveLayers[0].key
        let f1 = p.addFile(path: "a.txt", kind: .text, title: "A")
        let f2 = p.addFile(path: "b.txt", kind: .text, title: "B")
        _ = p.addFile(path: "c.txt", kind: .text, title: "C (not coded)")
        let s1 = try p.addSelection(layer: l, file: f1, spans: [TextSpan(start: 0, length: 5)])
        let s2 = try p.addSelection(layer: l, file: f2, spans: [TextSpan(start: 0, length: 5)])
        let o1 = try p.addCode(layer: l, kind: .open, name: "Fatigue")
        let o2 = try p.addCode(layer: l, kind: .open, name: "Breaks")
        let lonely = try p.addCode(layer: l, kind: .open, name: "Unused")
        try p.addEvidence(code: o1, target: s1)
        try p.addEvidence(code: o1, target: s2)
        try p.addEvidence(code: o2, target: s2)
        let a1 = try p.addCode(layer: l, kind: .axial, name: "Work rhythm")
        let a2 = try p.addCode(layer: l, kind: .axial, name: "Wellbeing")
        try p.addEvidence(code: a1, target: o1)
        try p.addEvidence(code: a1, target: o2)
        try p.addEvidence(code: a2, target: a1)   // level 2
        try p.addEvidence(code: a2, target: o1)   // skips a column

        let chart = CodingChart.make(p, layer: l)
        XCTAssertEqual(chart.columns.count, 4)
        XCTAssertEqual(Set(chart.columns[0]), [f1, f2])
        XCTAssertEqual(Set(chart.columns[1]), [o1, o2])
        XCTAssertEqual(chart.columns[2], [a1])
        XCTAssertEqual(chart.columns[3], [a2])
        XCTAssertEqual(chart.unlinked, 2)   // "Unused" and the uncoded file
        XCTAssertEqual(chart.edges.count, 3 + 2 + 2)
        XCTAssertEqual(chart.connected(to: o2), [o2, f2, a1, a2])

        let all = CodingChart.make(p, layer: l, includeUnlinked: true)
        XCTAssertTrue(all.columns[1].contains(lonely))
        XCTAssertEqual(all.columns[0].count, 3)
    }

    func testAttributeSheetReportRowsAndCSV() throws {
        var p = Project.new(title: "Report")
        let f1 = p.addFile(path: "a.txt", kind: .text, title: "Alpha")
        let f2 = p.addFile(path: "b.txt", kind: .text, title: "Beta")
        let cb = p.newKey(Keys.attributeSheet)
        p.attributeSheets[cb] = AttributeSheet(key: cb, title: "Context", appliesTo: [.files], questions: [
            AttributeSheetQuestion(key: "q-1", label: "Setting", type: .chooseOne, options: ["Office", "Home"], requirement: .flagged),
            AttributeSheetQuestion(key: "q-2", label: "Notes"),
        ])
        try p.associate(attributeSheet: cb, with: f1)
        try p.associate(attributeSheet: cb, with: f2)
        try p.saveSheet(ResponseSheet(id: ResponseID(attributeSheet: cb, target: f2), answers: ["q-1": .one("Home"), "q-2": .text("Said \"tired\", twice")]))
        let report = try XCTUnwrap(AttributeSheetReport.make(p, attributeSheet: cb, title: { p.files[$0]?.displayTitle ?? "" }, person: { $0 }))
        XCTAssertEqual(report.rows.map(\.target), [f1, f2])
        XCTAssertEqual(report.rows[0].status, .notStarted)
        XCTAssertEqual(report.rows[1].status, .complete)
        let csv = report.csv(workingIDs: WorkingIDs.compute(p), title: { p.files[$0]?.displayTitle ?? "" },
                             kind: { _ in "Empirical File" }, person: { $0 })
        XCTAssertEqual(csv, """
        No.,Item,Kind,Researcher,Status,Setting,Notes
        EF 1,Alpha,Empirical File,,Not started,,
        EF 2,Beta,Empirical File,,Complete,Home,"Said ""tired"", twice"

        """)
    }
}

final class DeductiveTests: XCTestCase {
    func testLayerKinds() throws {
        var p = Project.new(title: "Kinds")
        XCTAssertEqual(p.layers.map(\.kind), [.deductive, .inductive])
        XCTAssertEqual(p.layers.map(\.name), ["Main Deductive", "Main Inductive"])
        let d = p.deductiveLayers[0].key, i = p.inductiveLayers[0].key
        // The last layer of each kind stays, and keeps its kind.
        XCTAssertThrowsError(try p.deleteLayer(d))
        XCTAssertThrowsError(try p.setLayerKind(i, .deductive))
        // A new layer can change kind while nothing is coded in it.
        let extra = p.addLayer(name: "Extra", kind: .inductive)
        try p.setLayerKind(extra, .deductive)
        XCTAssertEqual(p.layer(extra)?.kind, .deductive)
        let f = p.addFile(path: "a.txt", kind: .text)
        try p.addSelection(layer: extra, file: f, spans: [TextSpan(start: 0, length: 4)])
        XCTAssertThrowsError(try p.setLayerKind(extra, .inductive))
        try p.deleteLayer(d)   // another deductive layer remains
        // Open and axial codes only on inductive layers.
        XCTAssertThrowsError(try p.addCode(layer: extra, kind: .open, name: "Nope"))
        XCTAssertNoThrow(try p.addCode(layer: i, kind: .open, name: "Yes"))
    }

    func testProtocolSegments() throws {
        var p = Project.new(title: "Protocols")
        let f = p.addFile(path: "a.txt", kind: .text)
        let d = p.deductiveLayers[0].key, i = p.inductiveLayers[0].key
        let pr1 = p.addProtocol(title: "Interview")
        let q1 = try XCTUnwrap(p.addProtocolItem(to: pr1, label: "Q1"))
        let pr2 = p.addProtocol(title: "Article")
        let intro = try XCTUnwrap(p.addProtocolItem(to: pr2, label: "Introduction"))
        // Not on inductive layers.
        XCTAssertThrowsError(try p.addSelection(layer: i, file: f, spans: [TextSpan(start: 0, length: 5)],
                                                segment: ProtocolSegment(item: q1, part: .prompt)))
        let prompt = try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 0, length: 5)],
                                        segment: ProtocolSegment(item: q1, part: .prompt))
        XCTAssertEqual(p.layer(d)?.protocols[f], pr1)
        // One protocol per file per layer.
        XCTAssertThrowsError(try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 10, length: 5)],
                                                segment: ProtocolSegment(item: intro, part: .response)))
        XCTAssertThrowsError(try p.setProtocol(pr2, layer: d, file: f))
        // A segment is never a priori code evidence, nor irrelevant.
        let apc = try p.addAprioriCode(name: "Trust")
        XCTAssertThrowsError(try p.addAprioriEvidence(code: apc, selection: prompt))
        XCTAssertThrowsError(try p.setIrrelevant(prompt, true))
        // The same text as a plain selection is a separate selection.
        let plain = try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 0, length: 5)])
        XCTAssertNotEqual(plain, prompt)
        // Deleting the item deletes its segments; then the protocol can change.
        p.deleteProtocolItem(q1)
        XCTAssertNil(p.selection(prompt))
        XCTAssertNotNil(p.selection(plain))
        try p.setProtocol(pr2, layer: d, file: f)
        XCTAssertEqual(p.layer(d)?.protocols[f], pr2)
        p.deleteProtocol(pr2)
        XCTAssertNil(p.layer(d)?.protocols[f])
    }

    func testAprioriEvidenceLinksAndFramework() throws {
        var p = Project.new(title: "A priori")
        let f = p.addFile(path: "a.txt", kind: .text)
        let d = p.deductiveLayers[0].key, i = p.inductiveLayers[0].key
        let apc = try p.addAprioriCode(name: "Trust")
        XCTAssertThrowsError(try p.addAprioriCode(name: "  "))
        let s = try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 0, length: 5)])
        try p.addAprioriEvidence(code: apc, selection: s, memo: "why")
        XCTAssertThrowsError(try p.addAprioriEvidence(code: apc, selection: s))   // twice
        XCTAssertEqual(ProjectIndex(p).aprioriForSelection[s], [apc])
        XCTAssertThrowsError(try p.setIrrelevant(s, true))
        // Inductive selections can't be a priori evidence.
        let si = try p.addSelection(layer: i, file: f, spans: [TextSpan(start: 0, length: 5)])
        XCTAssertNotNil(p.aprioriEvidenceProblem(code: apc, selection: si))
        // Links from open and axial codes.
        let oc = try p.addCode(layer: i, kind: .open, name: "Doubt")
        try p.addLink(from: oc, to: apc, type: .contradicts)
        XCTAssertThrowsError(try p.addLink(from: oc, to: apc, type: .confirms))   // already linked
        var changed = try XCTUnwrap(p.code(oc)?.links.first)
        changed.type = .extends
        changed.memo = "Wider."
        p.updateLink(changed, of: oc)
        XCTAssertEqual(p.code(oc)?.links.first?.type, .extends)
        XCTAssertEqual(p.code(oc)?.links.first?.memo, "Wider.")
        // Framework Matrix: deductive layers only; an empty summary clears.
        try p.setFrameworkSummary("Strong.", layer: d, row: f, column: apc)
        XCTAssertEqual(p.layer(d)?.framework[f]?[apc], "Strong.")
        XCTAssertThrowsError(try p.setFrameworkSummary("No.", layer: i, row: f, column: apc))
        try p.setFrameworkSummary("", layer: d, row: f, column: apc)
        XCTAssertNil(p.layer(d)?.framework[f])
        try p.setFrameworkSummary("Again.", layer: d, row: f, column: apc)
        // Deleting the code drops its evidence, links and column; the
        // selection stays.
        p.deleteAprioriCode(apc)
        XCTAssertTrue(p.layer(d)!.aprioriEvidence.isEmpty)
        XCTAssertTrue(p.code(oc)!.links.isEmpty)
        XCTAssertTrue(p.layer(d)!.framework.isEmpty)
        XCTAssertNotNil(p.selection(s))
    }

    func testDeductiveMove() throws {
        var p = Project.new(title: "Move")
        let f = p.addFile(path: "a.txt", kind: .text)
        let d = p.deductiveLayers[0].key
        let d2 = p.addLayer(name: "Second coder", kind: .deductive)
        let apc = try p.addAprioriCode(name: "Trust")
        let s = try p.addSelection(layer: d, file: f, spans: [TextSpan(start: 0, length: 5)])
        try p.addAprioriEvidence(code: apc, selection: s, memo: "m")
        try p.move(s, toLayer: d2)
        XCTAssertEqual(p.layerKey(holding: s), d2)
        XCTAssertNil(p.layer(d)?.aprioriEvidence[apc])
        XCTAssertEqual(p.layer(d2)?.aprioriEvidence[apc], [Evidence(target: s, memo: "m")])
    }

    func testWorkingIDs() throws {
        var p = Project.new(title: "IDs")
        let pr = p.addProtocol(title: "Interview")
        let apc = try p.addAprioriCode(name: "Trust")
        let ids = WorkingIDs.compute(p)
        XCTAssertEqual(ids[pr], "PR 1")
        XCTAssertEqual(ids[apc], "APC 1")
    }
}

final class RealNamesTests: XCTestCase {
    let people = [(key: "i-00000001", pseudonym: "John Smith"), (key: "r-00000001", pseudonym: "Alice Bob")]

    func testCSV() {
        XCTAssertEqual(CSV.parse("a,\"b, c\",\"say \"\"hi\"\"\"\r\nx,,z\n"), [["a", "b, c", "say \"hi\""], ["x", "", "z"]])
        XCTAssertEqual(CSV.line(["a", "b,c", "d\"e"]), "a,\"b,c\",\"d\"\"e\"")
    }

    func testReadByKeyAndPseudonym() throws {
        let text = """
        key,pseudonym,real_first_name,real_last_name
        i-00000001,John Smith,Jonathan,Realname
        ,ALICE BOB,Alicia,Truename
        r-99999999,Nobody,,
        """
        let names = try RealNames.read(text, people: people)
        XCTAssertEqual(names, ["i-00000001": "Jonathan Realname", "r-00000001": "Alicia Truename"])
    }

    func testTemplateRoundTrip() throws {
        let t = RealNames.template(people: people)
        XCTAssertTrue(t.hasPrefix("key,pseudonym,real_first_name,real_last_name\n"))
        XCTAssertEqual(try RealNames.read(t, people: people), [:])
        XCTAssertThrowsError(try RealNames.read("a,b\n1,2\n", people: people))
    }

    func testSettingsRoundTrip() throws {
        var p = Project.new(title: "Names")
        p.settings.researcherNamesFile = "private/researchers.csv"
        p.settings.intervieweeNamesFile = "private/interviewees.csv"
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("names-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Workspace.create(at: dir, project: p)
        XCTAssertEqual(try Workspace.load(dir).project, p)
    }
}

/// Nothing in the app may touch the network (docs/MAINTENANCE.md
/// §Network): no networking API appears anywhere in the sources.
final class NetworkPolicyTests: XCTestCase {
    func testNoNetworkingAPIs() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let sources = root.appendingPathComponent("Sources")
        let forbidden = ["URLSession", "URLRequest", "import Network", "NWConnection", "NWPathMonitor", "import WebKit",
                         "WKWebView", "NSURLConnection", "CFNetwork", "CFSocket", "openURL", "NSWorkspace.shared.open(",
                         "Link(", "import Combine", "socket(", "getaddrinfo", "NSSharingService", "ShareLink"]
        var offences: [String] = []
        let e = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
        while let url = e?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in text.components(separatedBy: "\n").enumerated() {
                let code = line.components(separatedBy: "//").first ?? ""
                for f in forbidden where code.contains(f) {
                    offences.append("\(url.lastPathComponent):\(n + 1): \(f)")
                }
            }
        }
        XCTAssertEqual(offences, [], "Networking APIs found in the sources")
        // And no package dependencies.
        let manifest = try String(contentsOf: root.appendingPathComponent("Package.swift"), encoding: .utf8)
        XCTAssertFalse(manifest.contains(".package("), "Package.swift must not declare dependencies")
    }
}

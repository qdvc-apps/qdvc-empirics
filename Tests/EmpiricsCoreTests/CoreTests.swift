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
        return (p, p.layers[0].key, f)
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
        let l2 = p.addLayer(name: "Second lens")
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
        XCTAssertEqual(p.layers[0].selections[f]?.count, 1)
        XCTAssertEqual(p.layers[0].selections[f]?.first?.spans, [TextSpan(start: 0, length: 15)])
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

        let l2 = p.addLayer(name: "Other")
        try p.move(c1, toLayer: l2)
        XCTAssertEqual(p.layerKey(holding: s2), l2)
        XCTAssertEqual(p.layerKey(holding: ax), l2)
        XCTAssertEqual(p.layerKey(holding: s3), l)
        XCTAssertEqual(p.layerKey(holding: lone), l)
    }

    func testMoveRefusedOnIrrelevantClash() throws {
        var (p, l, f) = makeProject()
        let s = try p.addSelection(layer: l, file: f, spans: [TextSpan(start: 0, length: 10)])
        let l2 = p.addLayer(name: "Other")
        try p.addSelection(layer: l2, file: f, spans: [TextSpan(start: 5, length: 10)], irrelevant: true)
        XCTAssertThrowsError(try p.move(s, toLayer: l2))
        XCTAssertEqual(p.layerKey(holding: s), l)
    }

    func testSheetBlocking() throws {
        var (p, _, f) = makeProject()
        let cb = Codebook(key: "cb-00000001", title: "Interview", appliesTo: [.files], questions: [
            CodebookQuestion(key: "q-00000001", label: "Setting", type: .chooseOne, options: ["Home", "Work"],
                             strict: false, requirement: .blocking),
            CodebookQuestion(key: "q-00000002", label: "Mood", type: .text, requirement: .flagged),
            CodebookQuestion(key: "q-00000003", label: "Way too long a label for this", requirement: .optional),
        ])
        XCTAssertEqual(cb.questions[2].label.count, CodebookQuestion.maxLabelLength)
        p.codebooks[cb.key] = cb
        try p.associate(codebook: cb.key, with: f)
        var sheet = ResponseSheet(id: ResponseID(codebook: cb.key, target: f, researcher: "r-00000001"))
        XCTAssertThrowsError(try p.saveSheet(sheet))
        sheet.answers["q-00000001"] = .one("Café")
        XCTAssertNoThrow(try p.saveSheet(sheet))
        let saved = p.responses[sheet.id]!
        XCTAssertFalse(SheetCompleteness.of(saved.answers, against: p.codebooks[cb.key]!).isComplete)
        // Not strict: the new option joins the codebook.
        XCTAssertEqual(p.codebooks[cb.key]?.questions[0].options, ["Home", "Work", "Café"])
        // A codebook for codes can't go on a file.
        p.codebooks["cb-00000002"] = Codebook(key: "cb-00000002", title: "Codes only", appliesTo: [.openCodes])
        XCTAssertThrowsError(try p.associate(codebook: "cb-00000002", with: f))
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
        let l = p.layers[0].key
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
        let l2 = p.addLayer(name: "Second coder")
        p.layers[1].description = "Blind recode"
        try p.addCode(layer: l2, kind: .open, name: "Empty")
        p.codebooks["cb-00000001"] = Codebook(key: "cb-00000001", title: "Interview sheet", description: "About the interview",
                                               appliesTo: [.files, .openCodes], questions: [
            CodebookQuestion(key: "q-00000001", label: "Setting", text: "Where did it happen?", type: .chooseOne,
                             options: ["Home", "Office"], strict: true, requirement: .blocking),
            CodebookQuestion(key: "q-00000002", label: "Notes", text: "Anything else?", type: .text),
            CodebookQuestion(key: "q-00000003", label: "Tools", type: .chooseMany, options: ["Zoom", "Teams"]),
        ])
        try p.associate(codebook: "cb-00000001", with: f)
        try p.associate(codebook: "cb-00000001", with: c)
        try p.saveSheet(ResponseSheet(id: ResponseID(codebook: "cb-00000001", target: f, researcher: "r-00000001"),
                                      answers: ["q-00000001": .one("Home"), "q-00000002": .text("Line one\nLine two"),
                                                "q-00000003": .many(["Zoom", "Teams"])]))
        p.researchers = [Researcher(key: "r-00000001", firstName: "Alice", lastName: "Bob")]
        p.interviewees = [Interviewee(key: "i-00000001", firstName: "John", lastName: "Smith", consentForm: "consent/js.pdf")]
        p.speakerMaps[f] = SpeakerMap(fileKey: f, assignments: [SpeakerAssignment(label: "Alice Bob", person: "r-00000001"),
                                                                  SpeakerAssignment(label: "John Smith", person: "i-00000001")],
                                      ignored: ["okay"])
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
        let s = p.layers[0].selections.values.flatMap { $0 }.first { !$0.irrelevant && $0.spans.count == 1 }!
        p.deleteSelection(s.key)
        let parts = Workspace.changedParts(from: old, to: p)
        XCTAssertTrue(parts.contains(.selections(layer: p.layers[0].key, file: s.fileKey)))
        XCTAssertFalse(parts.contains(.project))
        try Workspace.save(p, parts: parts, to: dir)
        XCTAssertEqual(try Workspace.load(dir).project, p)

        // Deleting a layer removes its folder.
        let old2 = p
        let l2 = p.layers[1].key
        try p.deleteLayer(l2)
        try Workspace.save(p, parts: Workspace.changedParts(from: old2, to: p), to: dir)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("layers/\(l2)").path))
        XCTAssertEqual(try Workspace.load(dir).project, p)
    }

    func testMoveBetweenLayersOnDisk() throws {
        var p = try richProject()
        try Workspace.create(at: dir, project: p)
        let old = p
        let code = p.layers[0].codes.values.first { $0.kind == .axial }!
        try p.move(code.key, toLayer: p.layers[1].key)
        try Workspace.save(p, parts: Workspace.changedParts(from: old, to: p), to: dir)
        let reloaded = try Workspace.load(dir).project
        XCTAssertEqual(reloaded, p)
        XCTAssertNil(reloaded.layers[0].codes[code.key])
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
        XCTAssertEqual(loaded.project.layers.first?.codes["c-0000000c"]?.name, "Hope")
        // Evidence to a selection that doesn't exist is ignored, with a note.
        XCTAssertEqual(loaded.project.layers.first?.codes["c-0000000c"]?.evidence, [])
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

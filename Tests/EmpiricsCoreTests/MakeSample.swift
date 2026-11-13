import Foundation
import XCTest
@testable import EmpiricsCore

/// Rebuilds sample-workspace/ and sample-full-texts/ through the core API,
/// so the sample is always valid:
///
///     MAKE_SAMPLE=$PWD swift test --filter MakeSampleTests
///
/// Without MAKE_SAMPLE it builds the sample in a temporary folder and checks
/// that it loads back unchanged.
final class MakeSampleTests: XCTestCase {
    func testMakeSample() throws {
        let root: URL
        if let dir = ProcessInfo.processInfo.environment["MAKE_SAMPLE"] {
            root = URL(fileURLWithPath: dir)
        } else {
            root = FileManager.default.temporaryDirectory.appendingPathComponent("empirics-sample-\(UUID().uuidString)")
        }
        let workspace = root.appendingPathComponent("sample-workspace")
        let fullTexts = root.appendingPathComponent("sample-full-texts")
        for u in [workspace, fullTexts] where FileManager.default.fileExists(atPath: u.path) {
            try FileManager.default.removeItem(at: u)
        }
        try writeFullTexts(fullTexts)
        // Repeatable keys, so regenerating the sample changes nothing.
        var state: UInt64 = 0x5EED_1234_ABCD_0001
        let saved = Keys.source
        Keys.source = {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            return UInt32(truncatingIfNeeded: state >> 33)
        }
        defer { Keys.source = saved }
        let project = try buildProject(FullTexts(root: fullTexts))
        try Workspace.create(at: workspace, project: project)
        let loaded = try Workspace.load(workspace)
        XCTAssertEqual(loaded.notes, [])
        XCTAssertEqual(loaded.project, project)
        let people = project.interviewees.map { (key: $0.key, pseudonym: $0.fullName) }
        let names = try RealNames.read(try FullTexts(root: fullTexts).text(project.settings.intervieweeNamesFile), people: people)
        XCTAssertEqual(names["i-05a17400"], "Jonathan Example-Participant")
        if ProcessInfo.processInfo.environment["MAKE_SAMPLE"] == nil {
            try? FileManager.default.removeItem(at: root)
        }
    }

    // MARK: Full-texts

    static let interview1 = """
    Interview SF-2026-01 (pseudonymised transcript)
    Recorded by video call. Transcribed by the research team.

    Alice Bob
    Can you hear me okay? Sorry, my microphone was muted.

    John Smith:
    Yes, loud and clear.

    Alice Bob
    I now like to ask you a little bit about the user interface for QDVC Empirics. Do you think it's user friendly?

    John Smith:
    Well, it's certainly an improvement over alternatives. The existing crop of QDA software is very limited. But I'm still getting used to the user interface of QDVC Empirics, to be honest.

    ALICE BOB:
    Which part of the user interface is taking the longest to get used to?

    John Smith

    Oh, that's a hard one. I can't remember off the top of my head. Is it okay if I pull it up on my laptop here?

    Alice Bob:
    Of course, take your time.

    John Smith:
    Right. I think it's the layers. In other tools everything sits in one big tree of nodes, so I keep looking for the tree. Here I code in a layer and the codes only make sense inside it. Once it clicked, I liked it, because my supervisor and I can each have our own reading of the same transcript.

    Alice Bob
    And how do you find working with it over a long session?

    John Smith:
    Much better than I expected. After three or four hours of coding my eyes usually give up, but the serif text and the wide margins help. The numbers for quick codes save a lot of clicking. I barely touch the mouse now.

    Alice Bob:
    Is there anything that worries you about it?

    John Smith:
    Only that I need to show my reviewers where each claim comes from. If I can point them to the Git history of the YAML files, that would answer the usual "you made this up" question.
    """

    static let interview2 = """
    Interview SF-2026-02 (pseudonymised transcript)

    [00:00:04] Alice Bob: Thanks for making the time. Shall we start?
    [00:00:07] Priya Natarajan: Sure, happy to.
    [00:00:15] Alice Bob: How did you analyse your interviews before?
    [00:00:19] Priya Natarajan: Highlighters and a printout, honestly, then a spreadsheet. It was slow, and I lost track of why I had put a quote under a theme. I had the quotes but not my reasons.
    [00:01:02] Alice Bob: And now?
    [00:01:05] Priya Natarajan: Now every quote carries a short memo saying why it is evidence. Writing the memo forces me to think. It is slower per quote but much faster when I write up, because the argument is already there.
    [00:01:40] Alice Bob: Anything you would compare it with?
    [00:01:44] Priya Natarajan: It reminds me of the big commercial packages, but without the lock-in. The files are just text. My university's ethics office was relieved that the transcripts never leave the encrypted drive.
    """

    static let fieldNotes = """
    # Field notes, March 2026

    ## Observation 1

    The participant coded for ninety minutes without a break. Most actions were keyboard shortcuts.

    ## Observation 2

    Long sessions show a pattern: the first hour is fast, then the participant slows down and starts writing longer memos. Fatigue seems to change the kind of work rather than stop it.
    """

    func writeFullTexts(_ root: URL) throws {
        let fm = FileManager.default
        for folder in ["interviews", "notes", "literature", "consent"] {
            try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        try Self.interview1.write(to: root.appendingPathComponent("interviews/SF-2026-01.txt"), atomically: true, encoding: .utf8)
        try Self.interview2.write(to: root.appendingPathComponent("interviews/SF-2026-02.txt"), atomically: true, encoding: .utf8)
        try Self.fieldNotes.write(to: root.appendingPathComponent("notes/field-notes.md"), atomically: true, encoding: .utf8)
        try Self.pdf(pages: [[
            "Coding as interpretation: a short note (sample PDF)",
            "",
            "Qualitative coding is not the mechanical sorting of quotes into boxes.",
            "Each code records an interpretation, and each interpretation can be",
            "questioned. Keeping the reasons beside the evidence makes the chain",
            "from data to finding visible to readers and reviewers.",
        ], [
            "Page two",
            "",
            "Hermeneutic approaches treat analysis as a circle: the parts are read",
            "in the light of the whole, and the whole in the light of the parts.",
        ]]).write(to: root.appendingPathComponent("literature/coding-note.pdf"))
        try Self.pdf(pages: [["SAMPLE CONSENT FORM", "", "Participant pseudonym: John Smith", "Signed: (sample only)"]])
            .write(to: root.appendingPathComponent("consent/john-smith.pdf"))
        try Self.pdf(pages: [["SAMPLE CONSENT FORM", "", "Participant pseudonym: Priya Natarajan", "Signed: (sample only)"]])
            .write(to: root.appendingPathComponent("consent/priya-natarajan.pdf"))
        // Real-name mapping files (the "real" names here are invented too).
        try fm.createDirectory(at: root.appendingPathComponent("private"), withIntermediateDirectories: true)
        try """
        key,pseudonym,real_first_name,real_last_name
        r-a11ce000,Alice Bob,Alexandra,Example-Researcher
        """.write(to: root.appendingPathComponent("private/researchers-real-names.csv"), atomically: true, encoding: .utf8)
        try """
        key,pseudonym,real_first_name,real_last_name
        i-05a17400,John Smith,Jonathan,Example-Participant
        i-0c0ffee0,Priya Natarajan,Padma,Example-Participant
        """.write(to: root.appendingPathComponent("private/interviewees-real-names.csv"), atomically: true, encoding: .utf8)
        try """
        Full-texts for the QDVC Empirics sample project.

        In a real project this folder holds interview transcripts, articles,
        signed consent forms and the real-name mapping files (private/). It is
        never put in the workspace or in Git; the app only ever reads it. The
        names in this sample, pseudonyms and "real" names alike, are invented.
        """.write(to: root.appendingPathComponent("README.txt"), atomically: true, encoding: .utf8)
    }

    /// A minimal PDF with one Helvetica text block per page.
    static func pdf(pages: [[String]]) -> Data {
        var objects: [String] = []
        // 1: catalog, 2: pages, 3: font, then page and content pairs.
        let n = pages.count
        let kids = (0..<n).map { "\(4 + $0 * 2) 0 R" }.joined(separator: " ")
        objects.append("<< /Type /Catalog /Pages 2 0 R >>")
        objects.append("<< /Type /Pages /Kids [\(kids)] /Count \(n) >>")
        objects.append("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica /Encoding /WinAnsiEncoding >>")
        for (i, lines) in pages.enumerated() {
            var stream = "BT /F1 13 Tf 16 TL 72 740 Td\n"
            for line in lines {
                let escaped = line.replacingOccurrences(of: "\\", with: "\\\\")
                    .replacingOccurrences(of: "(", with: "\\(").replacingOccurrences(of: ")", with: "\\)")
                stream += "(\(escaped)) Tj T*\n"
            }
            stream += "ET"
            objects.append("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 3 0 R >> >> /Contents \(5 + i * 2) 0 R >>")
            objects.append("<< /Length \(stream.utf8.count) >>\nstream\n\(stream)\nendstream")
        }
        var out = "%PDF-1.4\n"
        var offsets: [Int] = []
        for (i, o) in objects.enumerated() {
            offsets.append(out.utf8.count)
            out += "\(i + 1) 0 obj\n\(o)\nendobj\n"
        }
        let xref = out.utf8.count
        out += "xref\n0 \(objects.count + 1)\n0000000000 65535 f \n"
        for o in offsets { out += String(format: "%010d 00000 n \n", o) }
        out += "trailer\n<< /Size \(objects.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"
        return Data(out.utf8)
    }

    // MARK: Project

    func span(_ needle: String, in text: String) throws -> [TextSpan] {
        let r = (text as NSString).range(of: needle)
        guard r.location != NSNotFound else { throw RuleError("Sample text not found: \(needle)") }
        return [TextSpan(start: r.location, length: r.length)]
    }

    func buildProject(_ ft: FullTexts) throws -> Project {
        var p = Project(settings: ProjectSettings(key: "p-5a3f1c20", title: "Using QDA software (sample)",
                                                  description: "A small sample project: two interviews about qualitative data analysis software, field notes and a short PDF.",
                                                  interlocutorLayer: true,
                                                  researcherNamesFile: "private/researchers-real-names.csv",
                                                  intervieweeNamesFile: "private/interviewees-real-names.csv"))
        p.layers = [CodingLayer(key: "l-dedc0001", kind: .deductive, name: "Main Deductive",
                                description: "The interview protocol and the Technology Acceptance Model", researcher: "r-a11ce000"),
                    CodingLayer(key: "l-0a1b2c3d", kind: .inductive, name: "Main Inductive", description: "First reading",
                                researcher: "r-a11ce000"),
                    CodingLayer(key: "l-4e5f6a7b", kind: .inductive, name: "Affordances lens",
                                description: "Rereading with an affordances lens", researcher: "r-a11ce000")]
        p.researchers = [Researcher(key: "r-a11ce000", firstName: "Alice", lastName: "Bob")]
        p.interviewees = [Interviewee(key: "i-05a17400", firstName: "John", lastName: "Smith", consentForm: "consent/john-smith.pdf"),
                          Interviewee(key: "i-0c0ffee0", firstName: "Priya", lastName: "Natarajan", consentForm: "consent/priya-natarajan.pdf")]

        func file(_ key: String, _ path: String, _ title: String, _ id: String, _ date: String, _ status: CodingStatus) throws {
            p.files[key] = EmpiricalFile(key: key, path: path, kind: FileKind.forPath(path)!, title: title, date: date,
                                         customID: id, status: status, fingerprint: try ft.fingerprint(path), added: "2026-11-01")
        }
        try file("f-1e7e0001", "interviews/SF-2026-01.txt", "Interview with John Smith", "SF-2026-01", "2026-03-14", .coded)
        try file("f-1e7e0002", "interviews/SF-2026-02.txt", "Interview with Priya Natarajan", "SF-2026-02", "2026-03-21", .inProgress)
        try file("f-1e7e0003", "notes/field-notes.md", "Field notes, March", "FN-2026-03", "2026-03-31", .inProgress)
        try file("f-1e7e0004", "literature/coding-note.pdf", "Coding as interpretation (note)", "", "2025-11-02", .notStarted)

        // Turn on Interlocutor mapping for the transcripts.
        p.speakerMaps["f-1e7e0001"] = SpeakerMap(fileKey: "f-1e7e0001", assignments: [
            SpeakerAssignment(label: "Alice Bob", person: "r-a11ce000"),
            SpeakerAssignment(label: "John Smith", person: "i-05a17400"),
        ])
        p.speakerMaps["f-1e7e0002"] = SpeakerMap(fileKey: "f-1e7e0002", assignments: [
            SpeakerAssignment(label: "Alice Bob", person: "r-a11ce000"),
            SpeakerAssignment(label: "Priya Natarajan", person: "i-0c0ffee0"),
        ])

        let t1 = try ft.text("interviews/SF-2026-01.txt")
        let t2 = try ft.text("interviews/SF-2026-02.txt")
        let t3 = try ft.text("notes/field-notes.md")
        let main = "l-0a1b2c3d"
        let lens = "l-4e5f6a7b"

        @discardableResult
        func sel(_ layer: String, _ file: String, _ text: String, _ needle: String, irrelevant: Bool = false,
                 segment: ProtocolSegment? = nil) throws -> String {
            let spans = try span(needle, in: text)
            return try p.addSelection(layer: layer, file: file, spans: spans, quote: TextNormaliser.quote(spans, pages: [text]),
                                      irrelevant: irrelevant, segment: segment, by: "r-a11ce000")
        }

        // Main layer.
        try sel(main, "f-1e7e0001", t1, "Can you hear me okay? Sorry, my microphone was muted.", irrelevant: true)
        try sel(main, "f-1e7e0001", t1, "Yes, loud and clear.", irrelevant: true)
        let s1 = try sel(main, "f-1e7e0001", t1, "The existing crop of QDA software is very limited.")
        let s2 = try sel(main, "f-1e7e0001", t1, "But I'm still getting used to the user interface of QDVC Empirics, to be honest.")
        let s3 = try sel(main, "f-1e7e0001", t1, "In other tools everything sits in one big tree of nodes, so I keep looking for the tree.")
        let s4 = try sel(main, "f-1e7e0001", t1, "After three or four hours of coding my eyes usually give up, but the serif text and the wide margins help.")
        let s5 = try sel(main, "f-1e7e0001", t1, "If I can point them to the Git history of the YAML files, that would answer the usual \"you made this up\" question.")
        let s6 = try sel(main, "f-1e7e0002", t2, "I had the quotes but not my reasons.")
        let s7 = try sel(main, "f-1e7e0002", t2, "Writing the memo forces me to think.")
        let s8 = try sel(main, "f-1e7e0002", t2, "It reminds me of the big commercial packages, but without the lock-in.")
        let s9 = try sel(main, "f-1e7e0002", t2, "My university's ethics office was relieved that the transcripts never leave the encrypted drive.")
        let s10 = try sel(main, "f-1e7e0003", t3, "Fatigue seems to change the kind of work rather than stop it.")
        try sel(main, "f-1e7e0002", t2, "Thanks for making the time. Shall we start?", irrelevant: true)
        let s11 = try sel(main, "f-1e7e0001", t1, "Once it clicked, I liked it")

        func code(_ layer: String, _ kind: CodeKind, _ name: String, _ description: String, _ colour: String) throws -> String {
            let k = try p.addCode(layer: layer, kind: kind, name: name, by: "r-a11ce000")
            var c = p.code(k)!
            c.description = description
            c.colour = colour
            c.created = "2026-11-01T09:00:00Z"
            p.updateCode(c)
            return k
        }
        let learning = try code(main, .open, "Learning curve", "Getting used to the tool; what takes time to learn.", "#F2C14E")
        let compare = try code(main, .open, "Comparison with other tools", "Participants measuring the tool against tools they know.", "#5BC0EB")
        let transparency = try code(main, .open, "Transparency to reviewers", "Showing others where findings come from.", "#9BC53D")
        let fatigue = try code(main, .open, "Fatigue in long sessions", "Tiredness, eyes, pace over hours of coding.", "#E55934")
        let reasons = try code(main, .open, "Memo as reasoning", "Writing why a quote is evidence.", "#B07CC6")
        let ethics = try code(main, .open, "Data protection", "Keeping participants' data safe.", "#4ECDC4")
        let adoption = try code(main, .axial, "Adoption barriers", "What stands between researchers and a new QDA tool.", "#FA7921")
        let rigour = try code(main, .axial, "Rigour made visible", "Practices that let others check the analysis.", "#7E9CD8")

        try p.addEvidence(code: learning, target: s2, memo: "He names the interface itself as the thing still being learnt.")
        try p.addEvidence(code: learning, target: s3, memo: "The old mental model (a tree of nodes) gets in the way.")
        try p.addEvidence(code: learning, target: s11)
        try p.addEvidence(code: compare, target: s1, memo: "A blunt judgement of existing tools.")
        try p.addEvidence(code: compare, target: s3)
        try p.addEvidence(code: compare, target: s8, memo: "Commercial packages as the yardstick; lock-in as the difference.")
        try p.addEvidence(code: transparency, target: s5, memo: "Git history imagined as an answer to reviewers' doubts.")
        try p.addEvidence(code: transparency, target: s6)
        try p.addEvidence(code: fatigue, target: s4, memo: "Reading comfort matters over hours.")
        try p.addEvidence(code: fatigue, target: s10, memo: "From observation, not self-report: compare with John's own account.")
        try p.addEvidence(code: reasons, target: s6, memo: "The missing reasons are exactly what memos supply.")
        try p.addEvidence(code: reasons, target: s7)
        try p.addEvidence(code: ethics, target: s9)
        try p.addEvidence(code: adoption, target: learning, memo: "Learning cost is the first barrier.")
        try p.addEvidence(code: adoption, target: compare, memo: "Comparisons frame what counts as better.")
        try p.addEvidence(code: rigour, target: transparency)
        try p.addEvidence(code: rigour, target: reasons, memo: "Memos make the interpretation inspectable.")

        var f = p.code(fatigue)!
        f.comments = ["Self-report (John) and observation (field notes) point the same way."]
        f.questions = ["Is this fatigue, or a shift from coding to interpreting?"]
        p.updateCode(f)
        p.addInterrelation(code: fatigue, type: "Compare", members: [s4, s10],
                           description: "Interview and observation agree that long sessions are tiring, but the field notes suggest the work changes rather than stops.")
        p.addInterrelation(code: compare, type: "Contrast", members: [s1, s8],
                           description: "One dismisses existing software; the other credits it and objects only to lock-in.")
        var c = p.code(compare)!
        c.questions = ["Are participants comparing features, or ways of working?"]
        p.updateCode(c)

        // A second layer, with its own reading.
        let s12 = try sel(lens, "f-1e7e0001", t1, "The numbers for quick codes save a lot of clicking. I barely touch the mouse now.")
        let keyboard = try code(lens, .open, "Keyboard affords flow", "The keyboard as what lets coding continue uninterrupted.", "#58B368")
        try p.addEvidence(code: keyboard, target: s12, memo: "Fewer interruptions: the tool recedes.")

        // Deductive: an interview protocol, with its prompts and responses
        // marked in both interviews.
        let deductive = "l-dedc0001"
        p.protocols["pr-1a7e0001"] = StudyProtocol(key: "pr-1a7e0001", title: "Interview protocol",
                                                   description: "The questions planned for every interview.", items: [
            ProtocolItem(key: "pi-0a000001", label: "Interface", text: "Do you think the user interface is user friendly?"),
            ProtocolItem(key: "pi-0a000002", label: "Long sessions", text: "How do you find working with it over a long session?"),
            ProtocolItem(key: "pi-0a000003", label: "Worries", text: "Is there anything that worries you about it?"),
            ProtocolItem(key: "pi-0a000004", label: "Earlier practice", text: "How did you analyse your interviews before?"),
        ])
        func segment(_ item: String, _ part: ProtocolPart) -> ProtocolSegment { ProtocolSegment(item: item, part: part) }
        try sel(deductive, "f-1e7e0001", t1, "Can you hear me okay? Sorry, my microphone was muted.", irrelevant: true)
        try sel(deductive, "f-1e7e0001", t1, "I now like to ask you a little bit about the user interface for QDVC Empirics. Do you think it's user friendly?",
                segment: segment("pi-0a000001", .prompt))
        try sel(deductive, "f-1e7e0001", t1, "Well, it's certainly an improvement over alternatives. The existing crop of QDA software is very limited. But I'm still getting used to the user interface of QDVC Empirics, to be honest.",
                segment: segment("pi-0a000001", .response))
        try sel(deductive, "f-1e7e0001", t1, "And how do you find working with it over a long session?",
                segment: segment("pi-0a000002", .prompt))
        try sel(deductive, "f-1e7e0001", t1, "Much better than I expected. After three or four hours of coding my eyes usually give up, but the serif text and the wide margins help. The numbers for quick codes save a lot of clicking. I barely touch the mouse now.",
                segment: segment("pi-0a000002", .response))
        try sel(deductive, "f-1e7e0001", t1, "Is there anything that worries you about it?", segment: segment("pi-0a000003", .prompt))
        try sel(deductive, "f-1e7e0001", t1, "Only that I need to show my reviewers where each claim comes from.",
                segment: segment("pi-0a000003", .response))
        try sel(deductive, "f-1e7e0002", t2, "How did you analyse your interviews before?", segment: segment("pi-0a000004", .prompt))
        try sel(deductive, "f-1e7e0002", t2, "Highlighters and a printout, honestly, then a spreadsheet. It was slow, and I lost track of why I had put a quote under a theme. I had the quotes but not my reasons.",
                segment: segment("pi-0a000004", .response))

        // A priori codes from the Technology Acceptance Model, with evidence.
        p.aprioriCodes["apc-7a0e0001"] = AprioriCode(
            key: "apc-7a0e0001", name: "Perceived ease of use", colour: "#F78FB3",
            definition: "The degree to which a researcher believes that using the tool would be free of effort.",
            included: "Learning the tool, effort, friction, fluency, speed of use.",
            excluded: "Whether the tool makes the research better (see Perceived usefulness).",
            example: "I barely touch the mouse now.",
            counterExample: "It's certainly an improvement over alternatives. (A judgement of value, not of effort.)",
            source: "Davis, F. D. (1989). Perceived usefulness, perceived ease of use, and user acceptance of information technology. MIS Quarterly, 13(3), 319–340.",
            by: "r-a11ce000", created: "2026-11-01T09:00:00Z")
        p.aprioriCodes["apc-7a0e0002"] = AprioriCode(
            key: "apc-7a0e0002", name: "Perceived usefulness", colour: "#C3A46C",
            definition: "The degree to which a researcher believes that using the tool would improve their research.",
            included: "Gains in the quality, rigour, transparency or speed of analysis and writing.",
            excluded: "How easy the tool is to use (see Perceived ease of use).",
            example: "Writing the memo forces me to think.",
            counterExample: "The files are just text. (A property of the tool, not a gain for the research.)",
            source: "Davis, F. D. (1989). MIS Quarterly, 13(3), 319–340.",
            by: "r-a11ce000", created: "2026-11-01T09:00:00Z")
        let d1 = try sel(deductive, "f-1e7e0001", t1, "But I'm still getting used to the user interface of QDVC Empirics, to be honest.")
        let d2 = try sel(deductive, "f-1e7e0001", t1, "The numbers for quick codes save a lot of clicking. I barely touch the mouse now.")
        let d3 = try sel(deductive, "f-1e7e0001", t1, "If I can point them to the Git history of the YAML files")
        let d4 = try sel(deductive, "f-1e7e0002", t2, "Writing the memo forces me to think.")
        try p.addAprioriEvidence(code: "apc-7a0e0001", selection: d1, memo: "Ease of use is still being earned.")
        try p.addAprioriEvidence(code: "apc-7a0e0001", selection: d2, memo: "Effort falls with the shortcuts.")
        try p.addAprioriEvidence(code: "apc-7a0e0002", selection: d3, memo: "Useful to reviewers, not only to him.")
        try p.addAprioriEvidence(code: "apc-7a0e0002", selection: d4, memo: "The tool changes how she thinks.")

        // Where what emerged meets what was defined beforehand.
        try p.addLink(from: learning, to: "apc-7a0e0001", type: .refines,
                      memo: "Ease of use is learnt over time, not a fixed perception.")
        try p.addLink(from: transparency, to: "apc-7a0e0002", type: .extends,
                      memo: "Usefulness to others (reviewers), which the model doesn't name.")
        try p.addLink(from: keyboard, to: "apc-7a0e0001", type: .confirms)

        // Framework Matrix summaries.
        try p.setFrameworkSummary("Still learning the interface; the shortcuts make long sessions easier.",
                                  layer: deductive, row: "f-1e7e0001", column: "apc-7a0e0001")
        try p.setFrameworkSummary("Memos make her think; the argument is ready when she writes up.",
                                  layer: deductive, row: "i-0c0ffee0", column: "apc-7a0e0002")

        // An attribute sheet for files, answered for the first interview.
        p.attributeSheets["ast-c0debee1"] = AttributeSheet(key: "ast-c0debee1", title: "Interview context",
                                               description: "Answer once per interview.", appliesTo: [.files], questions: [
            AttributeSheetQuestion(key: "q-5e771460", label: "Setting", text: "How was the interview conducted?", type: .chooseOne,
                             options: ["In person", "Video call", "Phone"], strict: true, requirement: .blocking),
            AttributeSheetQuestion(key: "q-d0a7104e", label: "Duration", text: "About how long did it last?", type: .text,
                             requirement: .flagged),
            AttributeSheetQuestion(key: "q-70b1c500", label: "Topics", text: "Which topics came up?", type: .chooseMany,
                             options: ["Interface", "Ethics", "Fatigue", "Collaboration"], strict: false, requirement: .optional),
            AttributeSheetQuestion(key: "q-a07e5000", label: "Notes", text: "Anything that might colour the interview (interruptions, mood)?",
                             type: .text, requirement: .optional),
        ])
        p.attributeSheets["ast-c0debee2"] = AttributeSheet(key: "ast-c0debee2", title: "Code quality", description: "A check on each axial code.",
                                               appliesTo: [.axialCodes], questions: [
            AttributeSheetQuestion(key: "q-9a110001", label: "Saturated", text: "Do new quotes still change this code's meaning?",
                             type: .chooseOne, options: ["Yes", "No", "Unsure"], strict: true, requirement: .flagged),
            AttributeSheetQuestion(key: "q-9a110002", label: "Counter-evidence", text: "What evidence speaks against it?", type: .text),
        ])
        for file in ["f-1e7e0001", "f-1e7e0002"] { try p.associate(attributeSheet: "ast-c0debee1", with: file) }
        try p.associate(attributeSheet: "ast-c0debee2", with: adoption)
        try p.saveSheet(ResponseSheet(id: ResponseID(attributeSheet: "ast-c0debee1", target: "f-1e7e0001", researcher: "r-a11ce000"),
                                      answers: ["q-5e771460": .one("Video call"), "q-d0a7104e": .text("About 40 minutes"),
                                                "q-70b1c500": .many(["Interface", "Fatigue", "Transparency"])]))
        try p.saveSheet(ResponseSheet(id: ResponseID(attributeSheet: "ast-c0debee1", target: "f-1e7e0002", researcher: "r-a11ce000"),
                                      answers: ["q-5e771460": .one("Video call")]))

        // Fixed timestamps, so regenerating the sample changes nothing.
        for li in p.layers.indices {
            for fk in p.layers[li].selections.keys {
                for si in p.layers[li].selections[fk]!.indices { p.layers[li].selections[fk]![si].created = "2026-11-01T09:00:00Z" }
            }
        }
        for id in p.responses.keys { p.responses[id]!.updated = "2026-11-01T09:30:00Z" }
        p.files["f-1e7e0003"]!.status = .inProgress
        return p
    }
}

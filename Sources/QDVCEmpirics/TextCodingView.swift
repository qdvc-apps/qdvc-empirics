import AppKit
import EmpiricsCore
import SwiftUI

/// What the text view draws over the text: highlights of the active layer,
/// dimmed irrelevant text, underlines from other visible layers, speaker
/// header lines; and what the margins show beside it.
struct TextDecorations: Equatable {
    struct Fill: Equatable {
        var range: NSRange
        var color: NSColor
    }

    var fills: [Fill] = []
    var dimmed: [NSRange] = []
    var underlines: [Fill] = []
    var headers: [Fill] = []
    /// Coding stripes (one per selection of the active layer).
    var stripes: [StripeSpec] = []
    /// Speaker turns.
    var turns: [TurnSpec] = []
}

struct StripeSpec: Equatable {
    var key: String
    var range: NSRange
    var color: NSColor
    var help: String
    var focused: Bool
    /// Shown beside the stripe when there is room: the open codes' names,
    /// or "Irrelevant".
    var label: String = ""
    /// The open codes' working identifiers, on the label's first line.
    var badges: [LabelBadge] = []
    /// Irrelevant text: a dashed grey ribbon.
    var dashed = false
}

/// A working identifier ("OC 12") on a stripe's label, in its code's colour.
struct LabelBadge: Equatable {
    var text: String
    var color: NSColor
}

struct TurnSpec: Equatable {
    var range: NSRange
    var name: String
    var color: NSColor
}

/// A stripe or turn placed beside its lines.
struct PlacedMark: Identifiable, Equatable {
    var id: String
    var y: CGFloat
    var height: CGFloat
    var lane: Int
    var color: NSColor
    var text: String
    var focused: Bool
    var label: String = ""
    var badges: [LabelBadge] = []
    var dashed = false
}

/// How the file page's width is shared: speaker names, the text, coding
/// stripes and open code names, centred, with whatever is left over as the
/// outer margins. As the window narrows, the outer margins go first; then
/// the text narrows a little; then the code names shrink and go; then the
/// speaker margin narrows; only then does the text narrow further. Nothing
/// ever asks for more than the width given, so the sidebar is never pushed.
struct ColumnLayout: Equatable {
    var speaker: CGFloat
    var text: CGFloat
    var stripes: CGFloat
    var labels: CGFloat

    var total: CGFloat { speaker + text + stripes + labels }

    static let stripeWidth: CGFloat = 56
    static let speakerWidth: CGFloat = 132
    static let minSpeakerWidth: CGFloat = 88
    static let maxLabelWidth: CGFloat = 200
    static let minLabelWidth: CGFloat = 110

    static func make(width: CGFloat, reading: CGFloat, speakers: Bool, stripes: Bool, labels: Bool) -> ColumnLayout {
        let w = max(0, width)
        let sp: CGFloat = speakers ? speakerWidth : 24
        let st: CGFloat = stripes ? stripeWidth : 24
        let room = w - sp - st
        // The text gives up a quarter of its width (not below 420) to make
        // room for code names before they are hidden.
        let soft = min(reading, max(420, reading * 0.75))
        if stripes, labels, room - soft >= minLabelWidth {
            let label = min(maxLabelWidth, room - soft)
            return ColumnLayout(speaker: sp, text: min(reading, room - label), stripes: st, labels: label)
        }
        var speaker = sp
        var text = min(reading, room)
        if speakers, text < 380 {
            speaker = max(minSpeakerWidth, sp - (380 - text))
            text = min(reading, w - speaker - st)
        }
        return ColumnLayout(speaker: speaker, text: max(120, text), stripes: st, labels: 0)
    }
}

/// A text or Markdown file, for reading and coding: the text in a readable
/// column, speaker names on the left (Interlocutor layer), coding stripes on
/// the right (with open code names beside them when there is room), and the
/// coding bar below.
struct TextCodingView: View {
    @Environment(AppModel.self) private var model
    let fileKey: String
    let text: String
    @State private var stripes: [PlacedMark] = []
    @State private var turnMarks: [PlacedMark] = []

    var body: some View {
        let speakers = model.project.settings.interlocutorLayer && model.showSpeakers
        let deco = decorations(speakers: speakers)
        VStack(spacing: 0) {
            GeometryReader { geo in
                let layout = ColumnLayout.make(width: geo.size.width, reading: model.readingWidth, speakers: speakers,
                                               stripes: model.showStripes, labels: model.showCodeNames)
                // The scroll view spans the whole width (so the margins
                // scroll too); the column is centred inside it.
                FillingScroll {
                    HStack(alignment: .top, spacing: 0) {
                        if speakers {
                            SpeakerMargin(marks: turnMarks, width: layout.speaker)
                                .frame(width: layout.speaker)
                                .frame(maxHeight: .infinity, alignment: .top)
                        } else {
                            Color.clear.frame(width: layout.speaker)
                        }
                        textView(deco)
                            .frame(width: layout.text)
                        if model.showStripes {
                            StripeMargin(marks: stripes)
                                .frame(width: layout.stripes)
                                .frame(maxHeight: .infinity, alignment: .top)
                        } else {
                            Color.clear.frame(width: layout.stripes)
                        }
                        if layout.labels > 0 {
                            CodeNameMargin(marks: stripes, width: layout.labels)
                                .frame(width: layout.labels)
                                .frame(maxHeight: .infinity, alignment: .top)
                        }
                    }
                    .frame(width: layout.total)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipped()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            CodingBar(fileKey: fileKey)
        }
    }

    func textView(_ deco: TextDecorations) -> CodingTextView {
        CodingTextView(
            model: model,
            fileKey: fileKey,
            text: text,
            markdown: model.project.files[fileKey]?.kind == .markdown,
            font: model.readingFont.font(size: model.readingSize),
            lineSpacing: model.lineSpacing,
            decorations: deco,
            reveal: model.reveal?.file == fileKey ? model.reveal : nil,
            clearRevision: model.clearTextSelectionRevision,
            position: model.positions[fileKey],
            onSelection: { spans in model.documentSelectionChanged(file: fileKey, spans: spans) },
            onClick: { offset in model.documentClicked(file: fileKey, page: nil, offset: offset) },
            onKey: { key, tv in handleKey(key, tv) },
            onPlaced: { s, t in
                stripes = s
                turnMarks = t
            },
            onPosition: { model.rememberPosition(file: fileKey, $0) }
        )
    }

    // MARK: Decorations

    func decorations(speakers: Bool) -> TextDecorations {
        var d = TextDecorations()
        let length = (text as NSString).length
        func ok(_ s: TextSpan) -> Bool { s.page == nil && s.start >= 0 && s.end <= length && s.length > 0 }
        let p = model.project
        let strength = model.highlightStrength

        if let layer = model.activeLayer {
            let list = layer.selections[fileKey] ?? []
            let relevant = list.filter { !$0.irrelevant }
            for s in list where s.irrelevant {
                for span in s.spans where ok(span) { d.dimmed.append(NSRange(location: span.start, length: span.length)) }
            }
            // Elementary segments between every boundary, each coloured by
            // its innermost selection, a little stronger where they overlap.
            // A sweep over start and end points, so long transcripts with many
            // selections stay quick to redraw.
            var starts: [Int: [Int]] = [:], ends: [Int: [Int]] = [:]
            for (i, s) in relevant.enumerated() {
                for span in s.spans where ok(span) {
                    starts[span.start, default: []].append(i)
                    ends[span.end, default: []].append(i)
                }
            }
            let cuts = Set(starts.keys).union(ends.keys).sorted()
            let colours = relevant.map { colour(of: $0, in: layer) }
            var active = Set<Int>()
            for (n, a) in cuts.enumerated() {
                for i in ends[a] ?? [] { active.remove(i) }
                for i in starts[a] ?? [] { active.insert(i) }
                guard n + 1 < cuts.count, !active.isEmpty else { continue }
                let b = cuts[n + 1]
                guard let inner = active.min(by: { relevant[$0].totalLength < relevant[$1].totalLength }) else { continue }
                let focused = active.contains { relevant[$0].key == model.focusedSelection }
                var alpha = strength + 0.1 * Double(active.count - 1)
                if focused { alpha = min(0.75, alpha + 0.25) }
                d.fills.append(.init(range: NSRange(location: a, length: b - a), color: colours[inner].withAlphaComponent(alpha)))
            }
            for s in list {
                guard let first = s.spans.first, ok(first), let last = s.spans.last else { continue }
                let range = NSRange(location: first.start, length: last.end - first.start)
                let focused = s.key == model.focusedSelection
                if s.irrelevant {
                    d.stripes.append(StripeSpec(key: s.key, range: range, color: .systemGray,
                                                help: "Irrelevant: can never be evidence in this layer", focused: focused,
                                                label: "Irrelevant", dashed: true))
                    continue
                }
                let codes = (model.index.codesForSelection[s.key] ?? []).compactMap { layer.codes[$0] }
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                let help = codes.isEmpty ? "Highlighted, no open code yet"
                    : codes.map { model.itemLabel($0.key) }.joined(separator: "\n")
                let label = codes.isEmpty ? "No open code yet" : codes.map(\.name).joined(separator: ", ")
                let badges = codes.map { LabelBadge(text: model.wid($0.key), color: $0.nsColor) }.filter { !$0.text.isEmpty }
                d.stripes.append(StripeSpec(key: s.key, range: range, color: colour(of: s, in: layer), help: help,
                                            focused: focused, label: label, badges: badges))
            }
        }
        if model.showOtherLayers {
            for layer in p.layers where layer.key != model.activeLayerKey && model.isLayerVisible(layer.key) {
                for s in layer.selections[fileKey] ?? [] where !s.irrelevant {
                    for span in s.spans where ok(span) {
                        d.underlines.append(.init(range: NSRange(location: span.start, length: span.length),
                                                  color: colour(of: s, in: layer)))
                    }
                }
            }
        }
        if speakers {
            // A turn whose words are all irrelevant is greyed out like them,
            // header line and margin name included.
            let ns = text as NSString
            let quiet = d.dimmed.sorted { $0.location < $1.location }
            for t in model.turns(fileKey) {
                var color = model.speakerColor(t.label, in: fileKey)
                if !quiet.isEmpty, Self.covered(t.body, by: quiet, in: ns) { color = Self.irrelevantColor }
                d.headers.append(.init(range: NSRange(location: t.header.start, length: t.header.length), color: color))
                let end = max(t.header.end, t.body.end)
                d.turns.append(TurnSpec(range: NSRange(location: t.header.start, length: end - t.header.start),
                                        name: model.speakerName(t.label, in: fileKey), color: color))
            }
        }
        return d
    }

    /// Irrelevant text, and everything in it (speaker names too).
    static let irrelevantColor = NSColor.tertiaryLabelColor

    /// True if `span` has words and every one of them lies in `ranges`
    /// (sorted by location); blank characters between ranges don't count.
    static func covered(_ span: TextSpan, by ranges: [NSRange], in ns: NSString) -> Bool {
        let end = min(span.end, ns.length)
        guard span.start >= 0, end > span.start, !blank(ns, span.start, end) else { return false }
        var pos = span.start
        for r in ranges where NSMaxRange(r) > pos {
            if r.location >= end { break }
            if r.location > pos, !blank(ns, pos, r.location) { return false }
            pos = max(pos, NSMaxRange(r))
            if pos >= end { return true }
        }
        return blank(ns, pos, end)
    }

    static func blank(_ ns: NSString, _ a: Int, _ b: Int) -> Bool {
        guard b > a else { return true }
        return ns.substring(with: NSRange(location: a, length: b - a))
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// A selection's colour: its first code's (by name), or grey.
    func colour(of s: CodeSelection, in layer: CodingLayer) -> NSColor {
        let codes = (model.index.codesForSelection[s.key] ?? []).compactMap { layer.codes[$0] }
        return codes.min { $0.name.localizedCompare($1.name) == .orderedAscending }?.nsColor ?? .systemGray
    }

    // MARK: Keys

    /// Single keys while reading (no modifiers): see the coding bar's
    /// keyboard help. Returns true if handled.
    func handleKey(_ key: String, _ tv: CodingNSTextView) -> Bool {
        switch key {
        case "\r", "\u{3}", "k":
            guard model.canCode else { return false }
            model.paletteVisible = true
        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            guard model.canCode, let n = Int(key) else { return false }
            model.applyQuickCode(n)
        case "0":
            guard model.canCode else { return false }
            model.toggleIrrelevant()
        case "h":
            guard model.hasTextSelection else { return false }
            model.highlightOnly()
        case "t":
            selectTurn(tv)
        case "p":
            selectUnit(tv, sentences: false)
        case "s":
            selectUnit(tv, sentences: true)
        case "]":
            model.stepSelection(1)
        case "[":
            model.stepSelection(-1)
        case "\u{7f}", "\u{f728}":
            guard !model.hasTextSelection, model.focusedSelection != nil else { return false }
            model.deleteFocusedSelection()
        case "\u{1b}":
            model.paletteVisible = false
            model.focusedSelection = nil
            tv.setSelectedRange(NSRange(location: tv.selectedRange().location, length: 0))
        default:
            return false
        }
        return true
    }

    /// Selects the speaker turn at the insertion point (its words, not the
    /// header).
    func selectTurn(_ tv: CodingNSTextView) {
        let caret = tv.selectedRange().location
        guard let turn = TurnDetector.turn(at: caret, in: model.turns(fileKey)), turn.body.length > 0 else {
            NSSound.beep()
            return
        }
        tv.setSelectedRange(NSRange(location: turn.body.start, length: turn.body.length))
    }

    /// Selects the paragraph (or sentence) at the insertion point, without
    /// surrounding spaces.
    func selectUnit(_ tv: CodingNSTextView, sentences: Bool) {
        let ns = tv.string as NSString
        guard ns.length > 0 else { return }
        let caret = min(tv.selectedRange().location, ns.length - 1)
        var range = ns.paragraphRange(for: NSRange(location: caret, length: 0))
        if sentences {
            var found: NSRange?
            ns.enumerateSubstrings(in: range, options: .bySentences) { _, r, _, stop in
                if NSLocationInRange(caret, r) || r.location > caret {
                    found = r
                    stop.pointee = true
                }
            }
            if let found { range = found }
        }
        tv.setSelectedRange(Self.trimmed(range, in: ns))
    }

    static func trimmed(_ r: NSRange, in ns: NSString) -> NSRange {
        var a = r.location, b = NSMaxRange(r)
        while a < b, let u = UnicodeScalar(ns.character(at: a)), CharacterSet.whitespacesAndNewlines.contains(u) { a += 1 }
        while b > a, let u = UnicodeScalar(ns.character(at: b - 1)), CharacterSet.whitespacesAndNewlines.contains(u) { b -= 1 }
        return NSRange(location: a, length: b - a)
    }
}

// MARK: - Margins

/// Coding stripes beside the text, one per selection, in lanes so
/// overlapping selections sit side by side; irrelevant text has a dashed
/// grey ribbon. Click one to focus it.
struct StripeMargin: View {
    @Environment(AppModel.self) private var model
    var marks: [PlacedMark]

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(marks) { m in
                Ribbon(color: Color(nsColor: m.color), focused: m.focused, dashed: m.dashed, height: max(6, m.height))
                    .padding(.horizontal, 3)
                    .contentShape(Rectangle())
                    .onTapGesture { model.focusSelection(m.id) }
                    .help(m.text)
                    .offset(x: 8 + CGFloat(m.lane) * 9, y: m.y)
            }
        }
    }
}

/// One coding stripe: solid in the code's colour, or dashed grey for
/// irrelevant text.
struct Ribbon: View {
    var color: Color
    var focused: Bool
    var dashed: Bool
    var height: CGFloat

    var body: some View {
        let width: CGFloat = focused ? 6 : 4
        Group {
            if dashed {
                Path { p in
                    p.move(to: CGPoint(x: width / 2, y: 0))
                    p.addLine(to: CGPoint(x: width / 2, y: height))
                }
                .stroke(color.opacity(focused ? 0.9 : 0.6), style: StrokeStyle(lineWidth: width, lineCap: .butt, dash: [5, 3]))
            } else {
                RoundedRectangle(cornerRadius: 2).fill(color.opacity(focused ? 1 : 0.8))
            }
        }
        .frame(width: width, height: height)
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(Color.primary.opacity(focused ? 0.6 : 0), lineWidth: 1)
        )
    }
}

/// Open code labels beside the stripes (only when the window is wide
/// enough). Each label sits level with the top of its stripe, in the
/// stripe's colour: the open codes' working identifiers on the first line,
/// then their names in bold, wrapped so the whole label shows. When labels
/// would overlap, the later one moves down, and is left out if that would
/// take its first line past its stripe (a focused selection's label always
/// shows).
struct CodeNameMargin: View {
    @Environment(AppModel.self) private var model
    var marks: [PlacedMark]
    var width: CGFloat

    /// The names' font (bold, as drawn below) for measuring.
    static let nameFont = NSFont.boldSystemFont(ofSize: 11)
    /// The badges' font (WorkingBadge: caption, medium, monospaced digits).
    static let badgeFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    static let badgeRowHeight: CGFloat = 17
    static let badgeSpacing: CGFloat = 4
    static let rowSpacing: CGFloat = 2
    /// Space kept free between one label and the next.
    static let gap: CGFloat = 6

    struct Placed: Identifiable {
        var mark: PlacedMark
        var y: CGFloat
        var badgeRows: [[LabelBadge]]
        var id: String { mark.id }
    }

    /// The width a label's text and badges wrap to.
    static func textWidth(_ width: CGFloat) -> CGFloat { max(40, width - 14) }

    /// A badge's width as WorkingBadge draws it (text, padding, border),
    /// rounded up.
    static func badgeWidth(_ text: String) -> CGFloat {
        let w = (text as NSString).size(withAttributes: [.font: badgeFont]).width
        return ceil(w) + 16
    }

    /// The badges in rows that fit the width (nearly always one row).
    static func badgeRows(_ badges: [LabelBadge], width: CGFloat) -> [[LabelBadge]] {
        var rows: [[LabelBadge]] = []
        var row: [LabelBadge] = []
        var used: CGFloat = 0
        for b in badges {
            let w = badgeWidth(b.text)
            if !row.isEmpty, used + badgeSpacing + w > width {
                rows.append(row)
                row = []
                used = 0
            }
            used += (row.isEmpty ? 0 : badgeSpacing) + w
            row.append(b)
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }

    /// The height of the names, wrapped to `width`.
    static func nameHeight(_ text: String, width: CGFloat) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let r = (text as NSString).boundingRect(with: NSSize(width: width, height: CGFloat.greatestFiniteMagnitude),
                                                options: [.usesLineFragmentOrigin, .usesFontLeading],
                                                attributes: [.font: nameFont])
        return ceil(r.height) + 1
    }

    static func arrange(_ marks: [PlacedMark], width: CGFloat) -> [Placed] {
        let w = textWidth(width)
        var result: [Placed] = []
        var nextFree: CGFloat = -.infinity
        let sorted = marks.sorted { a, b in a.y != b.y ? a.y < b.y : a.lane < b.lane }
        for m in sorted where !m.label.isEmpty || !m.badges.isEmpty {
            let rows = badgeRows(m.badges, width: w)
            let names = nameHeight(m.label, width: w)
            let parts = rows.count + (m.label.isEmpty ? 0 : 1)
            let height = CGFloat(rows.count) * badgeRowHeight + names + rowSpacing * CGFloat(max(0, parts - 1))
            let firstLine = rows.isEmpty ? min(names, 15) : badgeRowHeight
            let y = max(m.y - 1, nextFree)
            guard y <= m.y + max(0, m.height - firstLine) || m.focused else { continue }
            result.append(Placed(mark: m, y: y, badgeRows: rows))
            nextFree = y + height + gap
        }
        return result
    }

    var body: some View {
        let w = Self.textWidth(width)
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(Self.arrange(marks, width: width)) { p in
                let color = Color(nsColor: p.mark.color)
                VStack(alignment: .leading, spacing: Self.rowSpacing) {
                    ForEach(Array(p.badgeRows.enumerated()), id: \.offset) { _, row in
                        HStack(spacing: Self.badgeSpacing) {
                            ForEach(Array(row.enumerated()), id: \.offset) { _, badge in
                                WorkingBadge(text: badge.text, color: Color(nsColor: badge.color))
                            }
                        }
                        .frame(height: Self.badgeRowHeight)
                    }
                    if !p.mark.label.isEmpty {
                        Text(p.mark.label)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(width: w, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(p.mark.focused ? 0.12 : 0))
                        .padding(-3)
                )
                .contentShape(Rectangle())
                .onTapGesture { model.focusSelection(p.mark.id) }
                .help(p.mark.text)
                .offset(x: 6, y: p.y)
            }
        }
    }
}

/// Speaker names at the start of each turn, with a bar down the turn, in
/// greyscale (see AppModel.speakerColor).
struct SpeakerMargin: View {
    var marks: [PlacedMark]
    var width: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.clear
            ForEach(marks) { m in
                HStack(alignment: .top, spacing: 6) {
                    Text(m.text)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(nsColor: m.color))
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.top, 2)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color(nsColor: m.color).opacity(0.3))
                        .frame(width: 2, height: max(8, m.height))
                }
                .frame(width: max(0, width - 14), alignment: .trailing)
                .offset(x: -8, y: m.y)
            }
        }
    }
}

// MARK: - The text view

/// The full-text's text view: read-only, selectable, as tall as its text
/// (SwiftUI scrolls it). Single keys code and select (`onKey`).
final class CodingNSTextView: NSTextView {
    var onKey: ((String, CodingNSTextView) -> Bool)?
    var onWidthChange: (() -> Void)?
    var extraMenuItems: (() -> [NSMenuItem])?

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { onWidthChange?() }
    }

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if mods.isEmpty, let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty,
           let onKey, onKey(chars, self) {
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        Platform.stripOutsideServices(menu)
        if let extra = extraMenuItems?(), !extra.isEmpty {
            menu.insertItem(.separator(), at: 0)
            for item in extra.reversed() { menu.insertItem(item, at: 0) }
        }
        return menu
    }

    override var acceptsFirstResponder: Bool { true }
}

struct CodingTextView: NSViewRepresentable {
    var model: AppModel
    var fileKey: String
    var text: String
    var markdown: Bool
    var font: NSFont
    var lineSpacing: Double
    var decorations: TextDecorations
    var reveal: RevealRequest?
    var clearRevision: Int
    var position: Int?
    var onSelection: ([TextSpan]) -> Void
    var onClick: (Int) -> Void
    var onKey: (String, CodingNSTextView) -> Bool
    var onPlaced: ([PlacedMark], [PlacedMark]) -> Void
    var onPosition: (Int) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CodingNSTextView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let tv = CodingNSTextView(frame: .zero, textContainer: container)
        tv.isEditable = false
        tv.isSelectable = true
        tv.isRichText = false
        tv.importsGraphics = false
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = []
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 28)
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        // Nothing that could look things up, fetch link previews or hand
        // text to a service.
        tv.isAutomaticLinkDetectionEnabled = false
        tv.isAutomaticDataDetectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.isAutomaticTextCompletionEnabled = false
        tv.displaysLinkToolTips = false
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) { tv.writingToolsBehavior = .none }
        #endif
        tv.delegate = context.coordinator
        context.coordinator.parent = self
        tv.onKey = { [weak coordinator = context.coordinator] key, view in
            coordinator?.parent?.onKey(key, view) ?? false
        }
        tv.onWidthChange = { [weak coordinator = context.coordinator, weak tv] in
            guard let coordinator, let tv else { return }
            coordinator.place(in: tv, force: true)
        }
        tv.extraMenuItems = { [weak coordinator = context.coordinator] in
            coordinator?.menuItems() ?? []
        }
        apply(to: tv, coordinator: context.coordinator, initial: true)
        model.documentView = tv
        return tv
    }

    static func dismantleNSView(_ tv: CodingNSTextView, coordinator: Coordinator) {
        coordinator.reportPosition(tv)
    }

    /// Measures only real widths, and remembers the height until the text or
    /// width changes (docs/MAINTENANCE.md §Layout).
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: CodingNSTextView, context: Context) -> CGSize? {
        let c = context.coordinator
        let offered = proposal.height.flatMap { $0.isFinite ? $0 : nil } ?? 0
        guard let width = proposal.width, width.isFinite, width > 0 else {
            return CGSize(width: c.measured?.width ?? 600, height: max(c.measured?.height ?? 600, offered))
        }
        if let m = c.measured, abs(m.width - width) < 0.5, m.version == c.version {
            return CGSize(width: width, height: max(m.height, offered))
        }
        let height = Self.fittingHeight(of: nsView, width: width)
        c.measured = (width, c.version, height)
        return CGSize(width: width, height: max(height, offered))
    }

    static func fittingHeight(of tv: NSTextView, width: CGFloat) -> CGFloat {
        guard let lm = tv.layoutManager, let tc = tv.textContainer else { return 0 }
        let inset = tv.textContainerInset
        let lineWidth = max(1, width - 2 * inset.width)
        if abs(tc.containerSize.width - lineWidth) > 0.5 {
            tc.containerSize = NSSize(width: lineWidth, height: CGFloat.greatestFiniteMagnitude)
        }
        lm.ensureLayout(for: tc)
        let used = lm.usedRect(for: tc)
        let extra = lm.extraLineFragmentRect
        let line = (tv.font?.pointSize ?? 15) * 1.6
        return ceil(max(used.maxY, extra.maxY, line) + 2 * inset.height)
    }

    func updateNSView(_ tv: CodingNSTextView, context: Context) {
        context.coordinator.parent = self
        apply(to: tv, coordinator: context.coordinator, initial: false)
    }

    private func apply(to tv: CodingNSTextView, coordinator c: Coordinator, initial: Bool) {
        if initial || text != c.text || font != c.font || lineSpacing != c.lineSpacing {
            c.programmatic = true
            // (Not tv.font = …: that would restyle Markdown headings too.)
            tv.textStorage?.setAttributedString(Self.styled(text, markdown: markdown, font: font, lineSpacing: lineSpacing))
            c.programmatic = false
            c.text = text
            c.font = font
            c.lineSpacing = lineSpacing
            c.applied = nil
            c.version += 1
            c.measured = nil
        }
        if let lm = tv.layoutManager, c.applied != decorations {
            let full = NSRange(location: 0, length: (tv.string as NSString).length)
            for key in [NSAttributedString.Key.backgroundColor, .foregroundColor, .underlineStyle, .underlineColor] {
                lm.removeTemporaryAttribute(key, forCharacterRange: full)
            }
            func fits(_ r: NSRange) -> Bool { NSMaxRange(r) <= full.length }
            for f in decorations.fills where fits(f.range) {
                lm.addTemporaryAttribute(.backgroundColor, value: f.color, forCharacterRange: f.range)
            }
            for u in decorations.underlines where fits(u.range) {
                lm.addTemporaryAttribute(.underlineStyle, value: NSUnderlineStyle.thick.rawValue, forCharacterRange: u.range)
                lm.addTemporaryAttribute(.underlineColor, value: u.color.withAlphaComponent(0.8), forCharacterRange: u.range)
            }
            for h in decorations.headers where fits(h.range) {
                lm.addTemporaryAttribute(.foregroundColor, value: h.color, forCharacterRange: h.range)
            }
            // After the speaker headers, so irrelevant text is greyed out
            // whole, speaker names included.
            for r in decorations.dimmed where fits(r) {
                lm.addTemporaryAttribute(.foregroundColor, value: TextCodingView.irrelevantColor, forCharacterRange: r)
            }
            c.applied = decorations
            c.place(in: tv, force: true)
        } else {
            c.place(in: tv, force: false)
        }
        if clearRevision != c.clearRevision {
            c.clearRevision = clearRevision
            if !initial {
                let r = tv.selectedRange()
                c.programmatic = true
                tv.setSelectedRange(NSRange(location: NSMaxRange(r), length: 0))
                c.programmatic = false
            }
        }
        if let reveal, reveal.revision != c.revealRevision {
            c.revealRevision = reveal.revision
            c.restored = true
            model.consumeReveal(reveal.revision)
            if let first = reveal.spans.first, let last = reveal.spans.last {
                let range = NSRange(location: first.start, length: last.end - first.start)
                if NSMaxRange(range) <= (tv.string as NSString).length {
                    DispatchQueue.main.async { c.scrollToCentre(range, in: tv, flash: true) }
                }
            }
        } else if !c.restored {
            c.restored = true
            if let position, position > 0, position < (tv.string as NSString).length {
                DispatchQueue.main.async { c.scrollToTop(position, in: tv) }
            }
        }
        if initial {
            c.clearRevision = clearRevision
            DispatchQueue.main.async { tv.window?.makeFirstResponder(tv) }
        }
    }

    /// The text with the reading font and spacing; Markdown headings bold.
    static func styled(_ text: String, markdown: Bool, font: NSFont, lineSpacing: Double) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = CGFloat(lineSpacing)
        paragraph.paragraphSpacing = font.pointSize * 0.5
        let s = NSMutableAttributedString(string: text, attributes: [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ])
        if markdown {
            let ns = text as NSString
            var location = 0
            while location < ns.length {
                let line = ns.lineRange(for: NSRange(location: location, length: 0))
                let content = ns.substring(with: line)
                if content.hasPrefix("#") {
                    let level = content.prefix(while: { $0 == "#" }).count
                    let size = font.pointSize + CGFloat(max(0, 4 - level)) * 1.5
                    let bold = NSFontManager.shared.convert(NSFont(descriptor: font.fontDescriptor, size: size) ?? font,
                                                            toHaveTrait: .boldFontMask)
                    s.addAttribute(.font, value: bold, range: line)
                }
                location = NSMaxRange(line)
            }
        }
        return s
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodingTextView?
        var text = ""
        var font: NSFont?
        var lineSpacing: Double = 0
        var applied: TextDecorations?
        var clearRevision = -1
        var revealRevision = -1
        var restored = false
        /// On while the app itself changes the text or selection.
        var programmatic = false
        var version = 0
        var measured: (width: CGFloat, version: Int, height: CGFloat)?
        var placedFor: (version: Int, width: CGFloat, decorations: TextDecorations?)?
        var lastStripes: [PlacedMark] = []
        var lastTurns: [PlacedMark] = []

        /// Works out where stripes and speaker names go, from the text laid
        /// out at the view's actual width; reports them when they change.
        func place(in tv: NSTextView, force: Bool) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer, tv.frame.width > 0, let parent else { return }
            let width = tv.frame.width
            if !force, let p = placedFor, p.version == version, abs(p.width - width) < 0.5, p.decorations == applied { return }
            placedFor = (version, width, applied)
            let length = (tv.string as NSString).length
            guard length > 0 else { return }
            lm.ensureLayout(for: tc)
            let originY = tv.textContainerInset.height
            func yRange(_ r: NSRange) -> (CGFloat, CGFloat) {
                let a = max(0, min(r.location, length - 1))
                let b = max(a, min(NSMaxRange(r) - 1, length - 1))
                let top = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: a), effectiveRange: nil)
                let bottom = lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: b), effectiveRange: nil)
                return (originY + top.minY, originY + bottom.maxY)
            }
            // Stripes in lanes: each takes the first lane free at its top.
            var laneEnds: [CGFloat] = []
            var stripes: [PlacedMark] = []
            for s in parent.decorations.stripes.sorted(by: { $0.range.location < $1.range.location }) {
                let (y0, y1) = yRange(s.range)
                var lane = laneEnds.firstIndex { $0 < y0 - 2 } ?? laneEnds.count
                if lane >= 5 { lane = 4 }
                if lane == laneEnds.count { laneEnds.append(y1) } else { laneEnds[lane] = max(laneEnds[lane], y1) }
                stripes.append(PlacedMark(id: s.key, y: y0 + 3, height: y1 - y0 - 6, lane: lane, color: s.color,
                                          text: s.help, focused: s.focused, label: s.label, badges: s.badges,
                                          dashed: s.dashed))
            }
            var turns: [PlacedMark] = []
            for (i, t) in parent.decorations.turns.enumerated() {
                let (y0, y1) = yRange(t.range)
                turns.append(PlacedMark(id: "t\(i)", y: y0, height: y1 - y0, lane: 0, color: t.color, text: t.name, focused: false))
            }
            guard stripes != lastStripes || turns != lastTurns else { return }
            lastStripes = stripes
            lastTurns = turns
            // Not during a view update.
            DispatchQueue.main.async { [weak self] in self?.parent?.onPlaced(stripes, turns) }
        }

        func scrollToCentre(_ range: NSRange, in tv: NSTextView, flash: Bool) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let glyphs = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            var rect = lm.boundingRect(forGlyphRange: glyphs, in: tc)
            rect.origin.y += tv.textContainerInset.height
            let visible = tv.visibleRect.height > 0 ? tv.visibleRect.height : 600
            let pad = max(0, (visible - min(rect.height, visible)) / 2)
            tv.scrollToVisible(rect.insetBy(dx: 0, dy: -pad))
            if flash { tv.showFindIndicator(for: range) }
        }

        func scrollToTop(_ offset: Int, in tv: NSTextView) {
            guard let lm = tv.layoutManager, let tc = tv.textContainer else { return }
            lm.ensureLayout(for: tc)
            let glyph = lm.glyphIndexForCharacter(at: offset)
            let line = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            tv.scroll(NSPoint(x: 0, y: max(0, line.minY + tv.textContainerInset.height - 12)))
        }

        func reportPosition(_ tv: NSTextView) {
            let visible = tv.visibleRect
            guard visible.height > 0 else { return }
            let index = tv.characterIndexForInsertion(at: NSPoint(x: 10, y: visible.minY + tv.textContainerInset.height + 4))
            parent?.onPosition(index)
        }

        /// Context-menu items for the selection under the pointer.
        func menuItems() -> [NSMenuItem] {
            guard let parent else { return [] }
            let model = parent.model
            var items: [NSMenuItem] = []
            if model.hasTextSelection {
                items.append(ClosureMenuItem(title: "Apply Open Code…") { model.paletteVisible = true })
                items.append(ClosureMenuItem(title: "Highlight Without Open Code") { model.highlightOnly() })
                items.append(ClosureMenuItem(title: "Mark as Irrelevant") { model.toggleIrrelevant() })
            } else if let key = model.focusedSelection {
                items.append(ClosureMenuItem(title: "Add Open Code…") { model.paletteVisible = true })
                items.append(ClosureMenuItem(title: "Delete Selection") { model.deleteSelection(key) })
            }
            return items
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !programmatic, let tv = notification.object as? NSTextView else { return }
            let range = tv.selectedRange()
            let spans = range.length > 0 ? [TextSpan(start: range.location, length: range.length)] : []
            // Defer: SwiftUI state must not change during a view update.
            DispatchQueue.main.async { [weak self] in
                guard let parent = self?.parent else { return }
                parent.onSelection(spans)
                if range.length == 0 {
                    parent.onClick(range.location)
                }
                parent.onPosition(range.location)
            }
        }
    }
}

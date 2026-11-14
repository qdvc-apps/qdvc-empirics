import AppKit
import EmpiricsCore
import PDFKit
import SwiftUI

/// A selection drawn over a PDF's pages.
struct PDFHighlight: Equatable {
    var key: String
    var spans: [TextSpan]
    var color: NSColor
}

/// A PDF, coded on its own pages: drag to select text, then code it as in
/// a text file. Highlights are drawn by the view (`highlightedSelections`);
/// beside the pages are the same margins as beside a text file (protocol
/// segments with their labels and summary bubbles on the left, coding
/// stripes and the codes' labels on the right: `PDFMarginsView`, hosted in
/// the PDF's document view so it scrolls with the pages); the document
/// itself is never changed, and it was loaded from memory, so
/// nothing could be written back to the file anyway. Pages can be turned
/// for reading (right-click a page): the turn is kept in the workspace and
/// applied to the copy in memory.
struct PDFCodingView: View {
    @Environment(AppModel.self) private var model
    let fileKey: String
    let document: PDFDocument

    var body: some View {
        VStack(spacing: 0) {
            PDFCodingRepresentable(
                model: model,
                fileKey: fileKey,
                document: document,
                highlights: highlights(),
                stripes: model.showStripes ? model.stripeSources(file: fileKey) : [],
                segments: model.segmentSources(file: fileKey),
                showStripes: model.showStripes,
                showLabels: model.showStripes && model.showCodeNames,
                rotations: model.project.files[fileKey]?.rotations ?? [:],
                baseRotations: model.documents.pageRotations[fileKey] ?? [],
                reveal: model.reveal?.file == fileKey ? model.reveal : nil,
                clearRevision: model.clearTextSelectionRevision,
                position: model.positions[fileKey]
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            CodingProgressBar(fileKey: fileKey)
            CodingBar(fileKey: fileKey)
        }
    }

    func highlights() -> [PDFHighlight] {
        var result: [PDFHighlight] = []
        let strength = model.highlightStrength
        if model.showOtherLayers {
            for layer in model.project.layers where layer.key != model.activeLayerKey && model.isLayerVisible(layer.key) {
                for s in layer.selections[fileKey] ?? [] where !s.irrelevant && s.segment == nil {
                    result.append(PDFHighlight(key: s.key, spans: s.spans, color: model.selectionColour(s, in: layer).withAlphaComponent(0.12)))
                }
            }
        }
        if let layer = model.activeLayer {
            for s in (layer.selections[fileKey] ?? []).sorted(by: { $0.totalLength > $1.totalLength }) {
                let focused = s.key == model.focusedSelection
                // Protocol segments are in the margin; a light wash only
                // while focused, as in text.
                if s.segment != nil && !focused { continue }
                let color: NSColor = s.irrelevant
                    ? NSColor.systemGray.withAlphaComponent(0.22)
                    : s.segment != nil
                        ? NSColor.protocolSegment.withAlphaComponent(0.18)
                        : model.selectionColour(s, in: layer).withAlphaComponent(focused ? min(0.8, strength + 0.3) : strength + 0.1)
                result.append(PDFHighlight(key: s.key, spans: s.spans, color: color))
            }
        }
        return result
    }
}

final class CodingPDFView: PDFView {
    var onKey: ((String) -> Bool)?
    /// A click without dragging: (page index, character index), or nil off text.
    var onClickAt: ((Int, Int)?) -> Void = { _ in }
    /// Context-menu items, given the page under the pointer.
    var extraMenuItems: ((Int?) -> [NSMenuItem])?

    override func keyDown(with event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if mods.isEmpty, let chars = event.charactersIgnoringModifiers?.lowercased(), !chars.isEmpty,
           let onKey, onKey(chars) {
            return
        }
        super.keyDown(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        guard event.clickCount == 1 else { return }
        let hasSelection = (currentSelection?.string ?? "").isEmpty == false
        guard !hasSelection, let doc = document else { return }
        let point = convert(event.locationInWindow, from: nil)
        guard let page = page(for: point, nearest: false) else {
            onClickAt(nil)
            return
        }
        let index = page.characterIndex(at: convert(point, to: page))
        onClickAt(index >= 0 ? (doc.index(for: page), index) : nil)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = super.menu(for: event) ?? NSMenu()
        Platform.stripOutsideServices(menu)
        let point = convert(event.locationInWindow, from: nil)
        let pageIndex = page(for: point, nearest: true).flatMap { p in document.map { $0.index(for: p) } }
        if let extra = extraMenuItems?(pageIndex), !extra.isEmpty {
            menu.insertItem(.separator(), at: 0)
            for item in extra.reversed() { menu.insertItem(item, at: 0) }
        }
        return menu
    }

    override var acceptsFirstResponder: Bool { true }
}

struct PDFCodingRepresentable: NSViewRepresentable {
    var model: AppModel
    var fileKey: String
    var document: PDFDocument
    var highlights: [PDFHighlight]
    var stripes: [StripeSource]
    var segments: [SegmentSource]
    var showStripes: Bool
    /// Show the codes' names beside the stripes (when there is room).
    var showLabels: Bool
    /// Page turns from the workspace, and each page's own rotation.
    var rotations: [Int: Int]
    var baseRotations: [Int]
    var reveal: RevealRequest?
    var clearRevision: Int
    var position: Int?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> CodingPDFView {
        let view = CodingPDFView()
        view.displayMode = .singlePageContinuous
        view.displaysPageBreaks = true
        view.autoScales = true
        view.document = document
        view.delegate = context.coordinator
        let c = context.coordinator
        c.parent = self
        c.view = view
        view.onKey = { [weak c] key in c?.handleKey(key) ?? false }
        view.onClickAt = { [weak c] hit in c?.clicked(hit) }
        view.extraMenuItems = { [weak c] page in c?.menuItems(page: page) ?? [] }
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.selectionChanged(_:)),
                                               name: .PDFViewSelectionChanged, object: view)
        // The margins beside the pages follow zooming, new layouts and the
        // view's size (they scroll with the pages by themselves).
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.geometryChanged(_:)),
                                               name: .PDFViewScaleChanged, object: view)
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.geometryChanged(_:)),
                                               name: .PDFViewDocumentChanged, object: view)
        view.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.viewResized(_:)),
                                               name: NSView.frameDidChangeNotification, object: view)
        apply(view, c, initial: true)
        DispatchQueue.main.async { [weak c] in c?.layoutMargins() }
        model.documentView = view
        return view
    }

    static func dismantleNSView(_ view: CodingPDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        if let page = view.currentPage, let doc = view.document {
            coordinator.parent?.model.rememberPosition(file: coordinator.parent?.fileKey ?? "", doc.index(for: page))
        }
    }

    func updateNSView(_ view: CodingPDFView, context: Context) {
        context.coordinator.parent = self
        apply(view, context.coordinator, initial: false)
    }

    private func apply(_ view: CodingPDFView, _ c: Coordinator, initial: Bool) {
        if c.appliedRotations != rotations {
            c.appliedRotations = rotations
            for i in 0..<document.pageCount {
                guard let page = document.page(at: i) else { continue }
                let base = i < baseRotations.count ? baseRotations[i] : page.rotation
                let turned = ((base + (rotations[i] ?? 0)) % 360 + 360) % 360
                if page.rotation != turned { page.rotation = turned }
            }
            if !initial { view.layoutDocumentView() }
            c.marginsDirty = true
        }
        if c.appliedStripes != stripes || c.appliedSegments != segments || c.appliedShow != [showStripes, showLabels] {
            c.appliedStripes = stripes
            c.appliedSegments = segments
            c.appliedShow = [showStripes, showLabels]
            c.marginsDirty = true
        }
        if c.marginsDirty, !initial {
            // Not during the view update: it sets another hosting view's root.
            DispatchQueue.main.async { [weak c] in
                guard let c, c.marginsDirty else { return }
                c.layoutMargins()
            }
        }
        if c.applied != highlights {
            c.applied = highlights
            view.highlightedSelections = highlights.flatMap { h in
                h.spans.compactMap { span -> PDFSelection? in
                    guard let p = span.page, p < document.pageCount, let page = document.page(at: p),
                          span.end <= page.numberOfCharacters, let sel = page.selection(for: NSRange(location: span.start, length: span.length))
                    else { return nil }
                    sel.color = h.color
                    return sel
                }
            }
        }
        if clearRevision != c.clearRevision {
            c.clearRevision = clearRevision
            if !initial {
                c.programmatic = true
                view.clearSelection()
                c.programmatic = false
            }
        }
        if let reveal, reveal.revision != c.revealRevision {
            c.revealRevision = reveal.revision
            c.restored = true
            model.consumeReveal(reveal.revision)
            if let span = reveal.spans.first, let p = span.page, p < document.pageCount, let page = document.page(at: p),
               span.end <= page.numberOfCharacters, let sel = page.selection(for: NSRange(location: span.start, length: span.length)) {
                DispatchQueue.main.async { view.go(to: sel) }
            }
        } else if !c.restored {
            c.restored = true
            if let position, position > 0, position < document.pageCount, let page = document.page(at: position) {
                DispatchQueue.main.async { view.go(to: page) }
            }
        }
        if initial {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        }
    }

    @MainActor
    final class Coordinator: NSObject, PDFViewDelegate {
        var parent: PDFCodingRepresentable?
        weak var view: CodingPDFView?
        var applied: [PDFHighlight]?
        var clearRevision = -1
        var revealRevision = -1
        var restored = false
        var programmatic = false
        var appliedRotations: [Int: Int]?
        var appliedStripes: [StripeSource]?
        var appliedSegments: [SegmentSource]?
        var appliedShow: [Bool] = []
        var marginsDirty = true
        /// The margins beside the pages, in the PDF's document view.
        var host: PDFMarginsHostingView?
        /// Where selections' text is on its page (page space), by span.
        var spanRects: [TextSpan: NSRect] = [:]
        var lastWidth: CGFloat = 0

        /// Zooming, a new layout or document: the margins follow the pages.
        @objc func geometryChanged(_ note: Notification) {
            layoutMargins()
        }

        /// A new width may leave room for more, or less, beside the pages.
        @objc func viewResized(_ note: Notification) {
            guard let view, abs(view.bounds.width - lastWidth) > 0.5 else { return }
            layoutMargins()
        }

        /// How wide the margins beside the pages are, for the view's width:
        /// the protocol margin and code labels as beside text, narrower or
        /// left out when the view is narrow.
        func marginWidths(_ width: CGFloat) -> (segments: CGFloat, labels: CGFloat) {
            let p = parent
            let hasSegments = !(p?.segments.isEmpty ?? true)
            let wide = width >= 900
            let segments: CGFloat = hasSegments ? (wide ? ColumnLayout.protocolWidth : ColumnLayout.narrowProtocolWidth) : 0
            let labels: CGFloat = (p?.showLabels ?? false) && width >= 760 ? min(ColumnLayout.maxLabelWidth, max(ColumnLayout.minLabelWidth, width * 0.18)) : 0
            return (segments, labels)
        }

        /// Places the margins beside the pages: room for them (the PDF
        /// view's page margins), then every stripe, label and segment level
        /// with its text, in the document view's coordinates.
        func layoutMargins() {
            guard let view, let parent, let doc = view.document else { return }
            marginsDirty = false
            lastWidth = view.bounds.width
            let widths = marginWidths(view.bounds.width)
            let right: CGFloat = parent.showStripes ? ColumnLayout.stripeWidth + widths.labels + 6 : 6
            let left: CGFloat = widths.segments > 0 ? widths.segments + 8 : 6
            let margins = view.pageBreakMargins
            if abs(margins.left - left) > 0.5 || abs(margins.right - right) > 0.5 {
                view.pageBreakMargins = NSEdgeInsets(top: 6, left: left, bottom: 6, right: right)
                view.layoutDocumentView()
            }
            guard let docView = view.documentView else { return }
            if host == nil || host?.superview !== docView {
                host?.removeFromSuperview()
                let h = PDFMarginsHostingView(rootView: PDFMarginsView(model: parent.model, fileKey: parent.fileKey,
                                                                       layout: PDFMarginLayout()))
                h.sizingOptions = []
                h.autoresizingMask = [.width, .height]
                docView.addSubview(h)
                host = h
            }
            guard let host else { return }
            host.frame = docView.bounds
            var pageRects: [Int: NSRect] = [:]
            for i in 0..<doc.pageCount {
                guard let page = doc.page(at: i) else { continue }
                pageRects[i] = host.convert(view.convert(page.bounds(for: view.displayBox), from: page), from: view)
            }
            let leftEdge = pageRects.values.map(\.minX).min() ?? 0
            let rightEdge = pageRects.values.map(\.maxX).max() ?? host.bounds.width
            // Each selection's text, per page, in the host's coordinates.
            func pieces(_ spans: [TextSpan]) -> [(page: Int, rect: NSRect)] {
                var byPage: [Int: NSRect] = [:]
                for span in spans {
                    guard let p = span.page, p < doc.pageCount, let page = doc.page(at: p) else { continue }
                    let r: NSRect
                    if let cached = spanRects[span] {
                        r = cached
                    } else {
                        guard span.start >= 0, span.end <= page.numberOfCharacters,
                              let sel = page.selection(for: NSRange(location: span.start, length: span.length)) else { continue }
                        r = sel.bounds(for: page)
                        spanRects[span] = r
                    }
                    let inHost = host.convert(view.convert(r, from: page), from: view)
                    byPage[p] = byPage[p].map { $0.union(inHost) } ?? inHost
                }
                return byPage.keys.sorted().map { (page: $0, rect: byPage[$0]!) }
            }
            // Stripes in lanes, as beside text; a selection across pages has
            // a stripe on each, and its label on the first.
            var stripes: [PlacedMark] = []
            var laneEnds: [CGFloat] = []
            var stripeInputs: [(rect: NSRect, page: Int, first: Bool, source: StripeSource)] = []
            for st in parent.showStripes ? parent.stripes : [] {
                for (i, piece) in pieces(st.spans).enumerated() { stripeInputs.append((piece.rect, piece.page, i == 0, st)) }
            }
            for input in stripeInputs.sorted(by: { $0.rect.minY < $1.rect.minY }) {
                let y0 = input.rect.minY, y1 = input.rect.maxY
                var lane = laneEnds.firstIndex { $0 < y0 - 2 } ?? laneEnds.count
                if lane >= 5 { lane = 4 }
                if lane == laneEnds.count { laneEnds.append(y1) } else { laneEnds[lane] = max(laneEnds[lane], y1) }
                let st = input.source
                stripes.append(PlacedMark(id: st.key + "#\(input.page)", y: y0 + 1, height: max(6, y1 - y0 - 2), lane: lane,
                                          color: st.color, text: st.help, focused: st.focused,
                                          label: input.first ? st.label : "", badges: input.first ? st.badges : [],
                                          dashed: st.dashed, selection: st.key))
            }
            var segments: [PlacedMark] = []
            var segmentEnds: [CGFloat] = []
            var segmentInputs: [(rect: NSRect, page: Int, first: Bool, source: SegmentSource)] = []
            for g in widths.segments > 0 ? parent.segments : [] {
                for (i, piece) in pieces(g.spans).enumerated() { segmentInputs.append((piece.rect, piece.page, i == 0, g)) }
            }
            for input in segmentInputs.sorted(by: { $0.rect.minY < $1.rect.minY }) {
                let y0 = input.rect.minY, y1 = input.rect.maxY
                var lane = segmentEnds.firstIndex { $0 < y0 - 2 } ?? segmentEnds.count
                if lane >= 3 { lane = 2 }
                if lane == segmentEnds.count { segmentEnds.append(y1) } else { segmentEnds[lane] = max(segmentEnds[lane], y1) }
                let g = input.source
                segments.append(PlacedMark(id: g.key + "#\(input.page)", y: y0, height: max(10, y1 - y0), lane: lane,
                                           color: .protocolSegment, text: g.help, focused: g.focused, label: g.label,
                                           dashed: g.prompt, caption: g.caption, layer: g.layer,
                                           item: input.first ? g.item : "", reference: g.reference, selection: g.key))
            }
            var layout = PDFMarginLayout()
            layout.size = host.bounds.size
            layout.stripes = stripes
            layout.segments = segments
            layout.segmentWidth = widths.segments
            layout.segmentX = leftEdge - widths.segments - 2
            layout.stripeX = rightEdge + 2
            layout.labelWidth = parent.showStripes ? widths.labels : 0
            layout.labelX = layout.stripeX + ColumnLayout.stripeWidth
            var interactive: [NSRect] = []
            if !segments.isEmpty {
                interactive.append(NSRect(x: layout.segmentX, y: 0, width: layout.segmentWidth, height: layout.size.height))
            }
            if !stripes.isEmpty {
                interactive.append(NSRect(x: layout.stripeX, y: 0, width: ColumnLayout.stripeWidth + layout.labelWidth,
                                          height: layout.size.height))
            }
            host.interactive = interactive
            host.rootView = PDFMarginsView(model: parent.model, fileKey: parent.fileKey, layout: layout)
        }

        /// Links in PDFs are never followed: nothing opens a browser.
        nonisolated func pdfViewWillClick(onLink sender: PDFView, with url: URL) {}

        @objc func selectionChanged(_ note: Notification) {
            guard !programmatic, let view, let parent, let doc = view.document else { return }
            var spans: [TextSpan] = []
            if let sel = view.currentSelection, !(sel.string ?? "").isEmpty {
                for page in sel.pages {
                    let pi = doc.index(for: page)
                    for i in 0..<sel.numberOfTextRanges(on: page) {
                        let r = sel.range(at: i, on: page)
                        if r.location != NSNotFound, r.length > 0 {
                            spans.append(TextSpan(page: pi, start: r.location, length: r.length))
                        }
                    }
                }
            }
            let normalised = TextSpan.normalised(spans)
            DispatchQueue.main.async {
                parent.model.documentSelectionChanged(file: parent.fileKey, spans: normalised)
            }
        }

        func clicked(_ hit: (Int, Int)?) {
            guard let parent else { return }
            if let hit {
                parent.model.documentClicked(file: parent.fileKey, page: hit.0, offset: hit.1)
                parent.model.rememberPosition(file: parent.fileKey, hit.0)
            } else {
                parent.model.documentClicked(file: parent.fileKey, page: -1, offset: -1)
            }
        }

        func handleKey(_ key: String) -> Bool {
            guard let model = parent?.model else { return false }
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
            case "]":
                model.stepSelection(1)
            case "[":
                model.stepSelection(-1)
            case "\u{7f}", "\u{f728}":
                guard !model.hasTextSelection, model.focusedSelection != nil else { return false }
                model.deleteFocusedSelection()
            case "q", "a":
                return model.handleProtocolKey(key)
            case "\u{1b}":
                model.paletteVisible = false
                model.protocolPalette = nil
                model.focusedSelection = nil
                view?.clearSelection()
            default:
                return false
            }
            return true
        }

        func menuItems(page: Int?) -> [NSMenuItem] {
            parent?.model.documentMenuItems(page: page) ?? []
        }
    }
}


/// The margins beside a PDF's pages, placed in its document view's
/// coordinates: where the protocol, stripe and label columns are, and the
/// marks in them.
struct PDFMarginLayout: Equatable {
    var size: CGSize = .zero
    var stripes: [PlacedMark] = []
    var segments: [PlacedMark] = []
    var stripeX: CGFloat = 0
    var labelX: CGFloat = 0
    /// 0: no code labels.
    var labelWidth: CGFloat = 0
    var segmentX: CGFloat = 0
    /// 0: no protocol margin.
    var segmentWidth: CGFloat = 0
}

/// The same margins as beside a text file (SegmentMargin, StripeMargin,
/// CodeNameMargin), beside a PDF's pages. (Takes the model directly, and
/// passes it on: it is hosted apart from the window's views.)
struct PDFMarginsView: View {
    let model: AppModel
    var fileKey: String
    var layout: PDFMarginLayout

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            if layout.segmentWidth > 0, !layout.segments.isEmpty {
                SegmentMargin(fileKey: fileKey, marks: layout.segments, width: layout.segmentWidth)
                    .frame(width: layout.segmentWidth, height: layout.size.height)
                    .offset(x: layout.segmentX)
            }
            if !layout.stripes.isEmpty {
                StripeMargin(marks: layout.stripes)
                    .frame(width: ColumnLayout.stripeWidth, height: layout.size.height)
                    .offset(x: layout.stripeX)
                if layout.labelWidth > 0 {
                    CodeNameMargin(marks: layout.stripes, width: layout.labelWidth)
                        .frame(width: layout.labelWidth, height: layout.size.height)
                        .offset(x: layout.labelX)
                }
            }
        }
        .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
        .environment(model)
    }
}

/// Hosts the margins in the PDF's document view (so they scroll with the
/// pages), taking clicks only in the margin columns: everything else goes
/// to the PDF.
final class PDFMarginsHostingView: NSHostingView<PDFMarginsView> {
    /// Where the margins take clicks, in this view's coordinates.
    var interactive: [NSRect] = []

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let superview else { return nil }
        let p = convert(point, from: superview)
        guard interactive.contains(where: { $0.contains(p) }) else { return nil }
        return super.hitTest(point)
    }
}

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

/// A coding stripe beside a PDF's pages (one per selection of the active
/// layer, as beside a text file).
struct PDFStripe: Equatable {
    var key: String
    var spans: [TextSpan]
    var color: NSColor
    var help: String
    var focused: Bool
    /// Irrelevant text: dashed grey.
    var dashed: Bool
}

/// A PDF, coded on its own pages: drag to select text, then code it as in
/// a text file. Highlights are drawn by the view (`highlightedSelections`),
/// coding stripes in the margin beside the pages (`PDFStripeOverlay`); the
/// document itself is never changed, and it was loaded from memory, so
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
                stripes: model.showStripes ? stripes() : [],
                stripeMargin: model.showStripes,
                rotations: model.project.files[fileKey]?.rotations ?? [:],
                baseRotations: model.documents.pageRotations[fileKey] ?? [],
                reveal: model.reveal?.file == fileKey ? model.reveal : nil,
                clearRevision: model.clearTextSelectionRevision,
                position: model.positions[fileKey]
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
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
                // Protocol segments (no margin here): a light wash, stronger
                // while focused.
                let color: NSColor = s.irrelevant
                    ? NSColor.systemGray.withAlphaComponent(0.22)
                    : s.segment != nil
                        ? NSColor.protocolSegment.withAlphaComponent(focused ? 0.28 : 0.1)
                        : model.selectionColour(s, in: layer).withAlphaComponent(focused ? min(0.8, strength + 0.3) : strength + 0.1)
                result.append(PDFHighlight(key: s.key, spans: s.spans, color: color))
            }
        }
        return result
    }

    /// Coding stripes for the active layer's selections (protocol segments
    /// have their wash instead), as beside a text file.
    func stripes() -> [PDFStripe] {
        guard let layer = model.activeLayer else { return [] }
        return (layer.selections[fileKey] ?? []).filter { $0.segment == nil }.map { s in
            let focused = s.key == model.focusedSelection
            if s.irrelevant {
                return PDFStripe(key: s.key, spans: s.spans, color: .systemGray,
                                 help: "Irrelevant: can never be evidence in this layer", focused: focused, dashed: true)
            }
            let codes = model.tags(of: s.key, in: layer)
            let none = layer.isDeductive ? "No a priori code yet" : "No open code yet"
            let help = codes.isEmpty ? "Highlighted, " + none.lowercased() : codes.map { model.itemLabel($0.key) }.joined(separator: "\n")
            return PDFStripe(key: s.key, spans: s.spans, color: model.selectionColour(s, in: layer), help: help,
                             focused: focused, dashed: false)
        }
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
    var stripes: [PDFStripe]
    /// Leave room beside the pages for stripes.
    var stripeMargin: Bool
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
        // Coding stripes in the margin beside the pages.
        let overlay = PDFStripeOverlay(frame: view.bounds)
        overlay.autoresizingMask = [.width, .height]
        overlay.pdfView = view
        overlay.onClick = { [weak c] key in c?.parent?.model.focusSelection(key) }
        view.addSubview(overlay)
        c.overlay = overlay
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.geometryChanged(_:)),
                                               name: .PDFViewScaleChanged, object: view)
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.geometryChanged(_:)),
                                               name: .PDFViewDocumentChanged, object: view)
        DispatchQueue.main.async { [weak c, weak view] in
            // The scroll view inside the PDF view exists once it shows the
            // document: follow its scrolling.
            guard let c, let clip = view?.documentView?.enclosingScrollView?.contentView else { return }
            clip.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.geometryChanged(_:)),
                                                   name: NSView.boundsDidChangeNotification, object: clip)
            c.overlay?.relayout()
        }
        apply(view, c, initial: true)
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
            c.overlay?.relayout()
        }
        // Room beside the pages for the coding stripes.
        let margin: CGFloat = stripeMargin ? 60 : 5
        if abs(view.pageBreakMargins.right - margin) > 0.5 {
            view.pageBreakMargins = NSEdgeInsets(top: 5, left: margin, bottom: 5, right: margin)
            if !initial { view.layoutDocumentView() }
        }
        c.overlay?.stripes = stripes
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
        weak var overlay: PDFStripeOverlay?

        /// Scrolling, zooming or a new document: the stripes follow the pages.
        @objc func geometryChanged(_ note: Notification) {
            overlay?.relayout()
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

/// Coding stripes in the margin beside a PDF's pages: one per selection, in
/// lanes where they overlap, level with the selection's lines; dashed grey
/// for irrelevant text. Click one to focus its selection; hover for its
/// codes. A transparent view over the PDF view that takes only clicks on
/// stripes; laid out again as the PDF scrolls or zooms.
final class PDFStripeOverlay: NSView, NSViewToolTipOwner {
    weak var pdfView: PDFView?
    var onClick: (String) -> Void = { _ in }
    var stripes: [PDFStripe] = [] {
        didSet {
            guard stripes != oldValue else { return }
            spanRects = nil
            relayout()
        }
    }

    private struct Placed {
        var rect: NSRect
        var stripe: PDFStripe
    }

    /// Each stripe's text, per page, in page space (worked out once per
    /// change of stripes).
    private var spanRects: [[(page: Int, rect: NSRect)]]?
    private var placed: [Placed] = []

    override var isFlipped: Bool { true }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        relayout()
    }

    /// Only stripes take clicks; everything else goes to the PDF.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let p = convert(point, from: superview)
        return placed.contains { $0.rect.insetBy(dx: -3, dy: 0).contains(p) } ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        if let hit = placed.last(where: { $0.rect.insetBy(dx: -3, dy: 0).contains(p) }) { onClick(hit.stripe.key) }
    }

    /// Where each stripe goes for the pages in view.
    func relayout() {
        removeAllToolTips()
        placed = []
        defer { needsDisplay = true }
        guard let pdfView, let doc = pdfView.document, !stripes.isEmpty else { return }
        if spanRects == nil {
            spanRects = stripes.map { stripe in
                var byPage: [Int: NSRect] = [:]
                for span in stripe.spans {
                    guard let p = span.page, p < doc.pageCount, let page = doc.page(at: p),
                          span.end <= page.numberOfCharacters,
                          let sel = page.selection(for: NSRange(location: span.start, length: span.length)) else { continue }
                    let r = sel.bounds(for: page)
                    byPage[p] = byPage[p].map { $0.union(r) } ?? r
                }
                return byPage.keys.sorted().map { (page: $0, rect: byPage[$0]!) }
            }
        }
        let visible = Set(pdfView.visiblePages.map { doc.index(for: $0) })
        var pieces: [(rect: NSRect, pageMaxX: CGFloat, stripe: PDFStripe)] = []
        for (i, stripe) in stripes.enumerated() {
            for (p, r) in spanRects?[i] ?? [] where visible.contains(p) {
                guard let page = doc.page(at: p) else { continue }
                let rect = convert(pdfView.convert(r, from: page), from: pdfView)
                let pageRect = convert(pdfView.convert(page.bounds(for: pdfView.displayBox), from: page), from: pdfView)
                pieces.append((rect, pageRect.maxX, stripe))
            }
        }
        // Lanes, as beside text: each piece takes the first lane free at its top.
        var laneEnds: [CGFloat] = []
        for piece in pieces.sorted(by: { $0.rect.minY < $1.rect.minY }) {
            let y0 = piece.rect.minY, y1 = piece.rect.maxY
            var lane = laneEnds.firstIndex { $0 < y0 - 2 } ?? laneEnds.count
            if lane >= 5 { lane = 4 }
            if lane == laneEnds.count { laneEnds.append(y1) } else { laneEnds[lane] = max(laneEnds[lane], y1) }
            let width: CGFloat = piece.stripe.focused ? 6 : 4
            let rect = NSRect(x: piece.pageMaxX + 10 + CGFloat(lane) * 9, y: y0 + 1, width: width, height: max(6, y1 - y0 - 2))
            placed.append(Placed(rect: rect, stripe: piece.stripe))
            _ = addToolTip(rect.insetBy(dx: -3, dy: 0), owner: self, userData: nil)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        for p in placed where p.rect.intersects(dirtyRect.insetBy(dx: -4, dy: -4)) {
            let s = p.stripe
            if s.dashed {
                let path = NSBezierPath()
                path.move(to: NSPoint(x: p.rect.midX, y: p.rect.minY))
                path.line(to: NSPoint(x: p.rect.midX, y: p.rect.maxY))
                path.lineWidth = p.rect.width
                path.setLineDash([5, 3], count: 2, phase: 0)
                s.color.withAlphaComponent(s.focused ? 0.9 : 0.6).setStroke()
                path.stroke()
            } else {
                let path = NSBezierPath(roundedRect: p.rect, xRadius: 2, yRadius: 2)
                s.color.withAlphaComponent(s.focused ? 1 : 0.8).setFill()
                path.fill()
            }
            if s.focused {
                let ring = NSBezierPath(roundedRect: p.rect.insetBy(dx: -0.5, dy: -0.5), xRadius: 2, yRadius: 2)
                ring.lineWidth = 1
                NSColor.labelColor.withAlphaComponent(0.6).setStroke()
                ring.stroke()
            }
        }
    }

    func view(_ view: NSView, stringForToolTip tag: NSView.ToolTipTag, point: NSPoint,
              userData data: UnsafeMutableRawPointer?) -> String {
        placed.last { $0.rect.insetBy(dx: -3, dy: 0).contains(point) }?.stripe.help ?? ""
    }
}

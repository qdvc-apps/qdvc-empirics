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
/// the document itself is never changed, and it was loaded from memory, so
/// nothing could be written back to the file anyway.
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
                for s in layer.selections[fileKey] ?? [] where !s.irrelevant {
                    result.append(PDFHighlight(key: s.key, spans: s.spans, color: colour(of: s, in: layer).withAlphaComponent(0.12)))
                }
            }
        }
        if let layer = model.activeLayer {
            for s in (layer.selections[fileKey] ?? []).sorted(by: { $0.totalLength > $1.totalLength }) {
                let focused = s.key == model.focusedSelection
                let color: NSColor = s.irrelevant
                    ? NSColor.systemGray.withAlphaComponent(0.22)
                    : colour(of: s, in: layer).withAlphaComponent(focused ? min(0.8, strength + 0.3) : strength + 0.1)
                result.append(PDFHighlight(key: s.key, spans: s.spans, color: color))
            }
        }
        return result
    }

    func colour(of s: CodeSelection, in layer: CodingLayer) -> NSColor {
        let codes = (model.index.codesForSelection[s.key] ?? []).compactMap { layer.codes[$0] }
        return codes.min { $0.name.localizedCompare($1.name) == .orderedAscending }?.nsColor ?? .systemGray
    }
}

final class CodingPDFView: PDFView {
    var onKey: ((String) -> Bool)?
    /// A click without dragging: (page index, character index), or nil off text.
    var onClickAt: ((Int, Int)?) -> Void = { _ in }
    var extraMenuItems: (() -> [NSMenuItem])?

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
        if let extra = extraMenuItems?(), !extra.isEmpty {
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
        view.extraMenuItems = { [weak c] in c?.menuItems() ?? [] }
        NotificationCenter.default.addObserver(c, selector: #selector(Coordinator.selectionChanged(_:)),
                                               name: .PDFViewSelectionChanged, object: view)
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
            case "\u{1b}":
                model.paletteVisible = false
                model.focusedSelection = nil
                view?.clearSelection()
            default:
                return false
            }
            return true
        }

        func menuItems() -> [NSMenuItem] {
            guard let model = parent?.model else { return [] }
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
    }
}

import AppKit
import EmpiricsCore
import SwiftUI

/// What a coding stripe shows, wherever it is drawn (beside a text file's
/// lines or a PDF's pages): one per selection of the active layer, except
/// protocol segments.
struct StripeSource: Equatable {
    var key: String
    var spans: [TextSpan]
    var color: NSColor
    var help: String
    var focused: Bool
    /// Shown beside the stripe when there is room: the codes' names, or
    /// "Irrelevant".
    var label: String
    /// The codes' working identifiers, on the label's first line.
    var badges: [LabelBadge]
    /// Irrelevant text: dashed grey.
    var dashed: Bool
}

/// What a protocol segment shows in the far-left margin, wherever it is
/// drawn.
struct SegmentSource: Equatable {
    var key: String
    var spans: [TextSpan]
    /// "2 · Prompt".
    var label: String
    /// The item's label ("Long sessions").
    var caption: String
    var help: String
    var focused: Bool
    var prompt: Bool
    /// The deductive layer it is in, and its protocol item.
    var layer: String
    var item: String
    /// In another layer than the active one (shown for reference).
    var reference: Bool
}

extension AppModel {
    /// The coding stripes of a file, in the active layer.
    func stripeSources(file: String) -> [StripeSource] {
        guard let layer = activeLayer else { return [] }
        return (layer.selections[file] ?? []).filter { $0.segment == nil }.map { s in
            let focused = s.key == focusedSelection
            if s.irrelevant {
                return StripeSource(key: s.key, spans: s.spans, color: .systemGray,
                                    help: "Irrelevant: can never be evidence in this layer", focused: focused,
                                    label: "Irrelevant", badges: [], dashed: true)
            }
            let codes = tags(of: s.key, in: layer)
            let none = layer.isDeductive ? "No a priori code yet" : "No open code yet"
            let help = codes.isEmpty ? "Highlighted, " + none.lowercased() : codes.map { itemLabel($0.key) }.joined(separator: "\n")
            let label = codes.isEmpty ? none : codes.map(\.name).joined(separator: ", ")
            let badges = codes.map { LabelBadge(text: wid($0.key), color: $0.nsColor) }.filter { !$0.text.isEmpty }
            return StripeSource(key: s.key, spans: s.spans, color: selectionColour(s, in: layer), help: help,
                                focused: focused, label: label, badges: badges, dashed: false)
        }
    }

    /// The protocol segments of a file: the active layer's when it is
    /// deductive; while coding on an inductive layer, those of the visible
    /// deductive layers (for reference), so the protocol stays in view.
    func segmentSources(file: String) -> [SegmentSource] {
        let layers: [CodingLayer]
        if let active = activeLayer, active.isDeductive {
            layers = [active]
        } else {
            layers = project.deductiveLayers.filter { isLayerVisible($0.key) }
        }
        var result: [SegmentSource] = []
        for layer in layers {
            let reference = layer.key != activeLayerKey
            for s in layer.selections[file] ?? [] {
                guard let segment = s.segment else { continue }
                let item = project.protocolItem(segment.item)?.item
                let number = project.protocolItemNumber(segment.item).map { "\($0) · " } ?? ""
                var help = segmentTitle(segment) + (item.map { $0.text.isEmpty ? "" : "\n" + $0.text } ?? "")
                if reference { help += "\n\nIn \(layer.name) (switch to it to change the segment)." }
                result.append(SegmentSource(key: s.key, spans: s.spans, label: number + segment.part.label,
                                            caption: item.map { $0.label.isEmpty ? "Untitled" : $0.label } ?? "Deleted item",
                                            help: help, focused: !reference && s.key == focusedSelection,
                                            prompt: segment.part == .prompt, layer: layer.key, item: segment.item,
                                            reference: reference))
            }
        }
        return result
    }
}

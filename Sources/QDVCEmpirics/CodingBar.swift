import AppKit
import EmpiricsCore
import SwiftUI

/// The bar under a document: what you can do with what is selected, and
/// the quick codes (1–9). It changes with the selection, so the next action
/// is always one click (or one key) away.
struct CodingBar: View {
    @Environment(AppModel.self) private var model
    let fileKey: String
    @State private var showKeys = false

    /// The bar never asks for more width than it is given (a wide bar would
    /// push the window's columns and cut off the sidebar): it sits in an
    /// overlay of a flexible base, falls back to a compact and then a
    /// minimal variant, and anything still too wide is clipped.
    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .overlay(alignment: .leading) { bar }
            .clipped()
            .background(.bar)
    }

    static let height: CGFloat = 38

    var bar: some View {
        HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                content(compact: false)
                content(compact: true)
                minimal
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                showKeys.toggle()
            } label: {
                Image(systemName: "keyboard")
            }
            .buttonStyle(.borderless)
            .help("Keyboard shortcuts for coding")
            .popover(isPresented: $showKeys, arrowEdge: .top) { KeyboardHelp() }
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// For narrow windows: icon buttons only, no quick codes (the number
    /// keys still work).
    @ViewBuilder
    var minimal: some View {
        let noun = model.codeNoun
        HStack(spacing: 6) {
            if model.hasTextSelection, model.textSelectionFile == fileKey {
                Button { model.paletteVisible = true } label: { Image(systemName: "tag") }
                    .buttonStyle(.borderedProminent)
                    .help("Apply \(model.aCodeNoun) to the selected text (⌘K or Return)")
                if model.activeIsDeductive {
                    SegmentMenu(fileKey: fileKey, compact: true)
                }
                Button { model.highlightOnly() } label: { Image(systemName: "highlighter") }
                    .help("Highlight without \(model.aCodeNoun) (H)")
                Button { model.toggleIrrelevant() } label: { Image(systemName: "eye.slash") }
                    .help("Mark as irrelevant (0)")
            } else if let key = model.focusedSelection, let s = model.project.selection(key), s.fileKey == fileKey {
                if s.irrelevant {
                    Button { model.toggleIrrelevant() } label: { Image(systemName: "eye") }
                        .help("Mark relevant again")
                } else if let segment = s.segment {
                    Image(systemName: "list.bullet.rectangle").foregroundStyle(Color(nsColor: .protocolSegment))
                        .help(model.segmentTitle(segment))
                } else {
                    let n = model.tags(of: key).count
                    Text("\(n)").monospacedDigit().foregroundStyle(.secondary)
                        .help("\(n) \(noun)\(n == 1 ? "" : "s") on this selection")
                    Button { model.paletteVisible = true } label: { Image(systemName: "plus") }
                        .help("Add \(model.aCodeNoun) to this selection (⌘K)")
                }
                Button(role: .destructive) { model.deleteSelection(key) } label: { Image(systemName: "trash") }
                    .help("Delete this selection (Delete)")
            } else {
                Text("Select text").foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .fixedSize()
    }

    @ViewBuilder
    func content(compact: Bool) -> some View {
        let noun = model.codeNoun
        let title = model.codeNounTitle
        HStack(spacing: 8) {
            if model.hasTextSelection, model.textSelectionFile == fileKey {
                let count = model.textSelection.reduce(0) { $0 + $1.length }
                Text(compact ? "\(count)" : "\(count) characters").foregroundStyle(.secondary).monospacedDigit()
                Button {
                    model.paletteVisible = true
                } label: {
                    Label(compact ? title : title + "…", systemImage: "tag")
                }
                .buttonStyle(.borderedProminent)
                .help("Apply \(model.aCodeNoun) to the selected text (⌘K or Return)")
                if model.activeIsDeductive {
                    SegmentMenu(fileKey: fileKey, compact: compact)
                }
                Button(compact ? "Highlight" : "Highlight Only") { model.highlightOnly() }
                    .help("Make a selection without \(model.aCodeNoun) yet (H)")
                Button(compact ? "Irrelevant" : "Mark Irrelevant") { model.toggleIrrelevant() }
                    .help("Mark the text as irrelevant in this layer (0)")
                if let f = model.focusedSelection, model.project.selection(f) != nil {
                    Button(compact ? "Resize" : "Resize Focused Selection") { model.resizeFocusedToTextSelection() }
                        .help("Give the focused selection the text now selected")
                }
            } else if let key = model.focusedSelection, let s = model.project.selection(key), s.fileKey == fileKey {
                if s.irrelevant {
                    Label("Irrelevant", systemImage: "eye.slash").foregroundStyle(.secondary)
                    Button("Mark Relevant") { model.toggleIrrelevant() }
                } else if let segment = s.segment {
                    Label(model.segmentTitle(segment), systemImage: "list.bullet.rectangle")
                        .foregroundStyle(Color(nsColor: .protocolSegment))
                        .lineLimit(1)
                    SegmentMenu(fileKey: fileKey, compact: compact, title: "Change")
                    if !compact {
                        Button("Unmark") { model.clearSegment(key) }
                            .help("Make this a plain selection again")
                    }
                } else {
                    let tags = model.tags(of: key)
                    if tags.isEmpty {
                        Text("No \(noun) yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(tags.prefix(compact ? 1 : 3)) { t in
                            CodeChip(tag: t, compact: true)
                                .onTapGesture { model.showTag(t.key) }
                        }
                        if tags.count > (compact ? 1 : 3) {
                            Text("+\(tags.count - (compact ? 1 : 3))").foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        model.paletteVisible = true
                    } label: {
                        Label(compact ? "Add" : "Add \(title)…", systemImage: "plus")
                    }
                    .help("Add \(model.aCodeNoun) to this selection (⌘K)")
                }
                MergeButton(model: model, key: key, compact: compact)
                Button(role: .destructive) {
                    model.deleteSelection(key)
                } label: {
                    Label(compact ? "" : "Delete", systemImage: "trash")
                }
                .help("Delete this selection (Delete)")
            } else {
                Text(compact ? "Select text to code it"
                     : model.activeIsDeductive
                        ? "Select text, then press Return for an a priori code, 1–9 for a quick code, or Q / A for a protocol prompt / response."
                        : "Select text, then press Return to apply an open code, or 1–9 for a quick open code.")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            QuickCodeStrip(compact: compact)
        }
    }
}

/// On a deductive layer: mark the text (or change the focused segment) as
/// the prompt or the response of an item of the file's protocol.
struct SegmentMenu: View {
    @Environment(AppModel.self) private var model
    let fileKey: String
    var compact: Bool
    var title = "Protocol"

    var body: some View {
        let model = self.model
        let protocols = model.segmentProtocols(file: fileKey)
        Menu {
            if protocols.isEmpty {
                Text("No protocols yet")
                Button("Make a Protocol…") { model.sidebar = .protocols }
            }
            ForEach(ProtocolPart.allCases, id: \.self) { part in
                Section(part.label + (part == .prompt ? " (Q)" : " (A)")) {
                    ForEach(protocols) { pr in
                        if protocols.count > 1 {
                            Menu(pr.title) { items(pr, part, model) }
                        } else {
                            items(pr, part, model)
                        }
                    }
                }
            }
        } label: {
            Label(compact ? title : title + "…", systemImage: "list.bullet.rectangle")
        }
        .fixedSize()
        .help("Mark the text as a protocol prompt (Q) or response (A)")
    }

    @ViewBuilder
    func items(_ pr: StudyProtocol, _ part: ProtocolPart, _ model: AppModel) -> some View {
        if pr.items.isEmpty {
            Text("\(pr.title) has no items yet")
        }
        ForEach(pr.items) { item in
            Button(model.protocolItemTitle(item.key)) { model.markSegment(item: item.key, part: part) }
        }
    }
}

/// Quick codes 1–9: click (or press the number) to code the selection.
/// Each layer has its own nine: open codes on inductive layers, a priori
/// codes on deductive ones.
struct QuickCodeStrip: View {
    @Environment(AppModel.self) private var model
    var compact: Bool

    var body: some View {
        // Captured here, so the context menu (built apart from the view)
        // doesn't read the environment.
        let model = self.model
        let slots = model.quickCodes.enumerated().compactMap { i, key -> (Int, CodingTag)? in
            guard model.isCodeOfActiveLayer(key), let t = model.tag(key) else { return nil }
            return (i + 1, t)
        }
        if !slots.isEmpty {
            HStack(spacing: 4) {
                ForEach(slots, id: \.0) { slot, code in
                    Button {
                        model.applyQuickCode(slot)
                    } label: {
                        if compact {
                            HStack(spacing: 2) {
                                Text("\(slot)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                CodeDot(color: code.color)
                            }
                        } else {
                            CodeChip(tag: code, slot: slot, compact: true)
                                .frame(maxWidth: 150)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canCode)
                    .opacity(model.canCode ? 1 : 0.55)
                    .help("\(slot): \(code.name)")
                    .contextMenu {
                        Button("Remove from Quick Codes") { model.assignQuickCode(nil, slot: slot) }
                        Button(code.isApriori ? "Show A Priori Code" : "Show Open Code") { model.showTag(code.key) }
                    }
                }
            }
        }
    }
}

struct KeyboardHelp: View {
    let rows: [(String, String)] = [
        ("Return or K", "Apply a code to the selection (opens the palette): open codes on inductive layers, a priori codes on deductive ones"),
        ("1 … 9", "Apply quick code 1–9 (each layer has its own)"),
        ("Q / A", "Mark as a protocol prompt / response (deductive layers)"),
        ("0", "Mark irrelevant (or relevant again)"),
        ("H", "Highlight without a code"),
        ("T", "Select the speaker's turn (Interlocutor layer)"),
        ("P / S", "Select the paragraph / sentence"),
        ("] / [", "Next / previous selection"),
        ("Delete", "Delete the focused selection"),
        ("Esc", "Clear the selection"),
        ("⌘K", "Code palette (from anywhere)"),
        ("⌥⌘] / ⌥⌘[", "Next / previous file"),
        ("⌥⌘N", "Next file not yet coded"),
        ("⌘F", "Find in the document"),
        ("⌘+ / ⌘−", "Larger / smaller text"),
        ("⌘Z", "Undo any coding step"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Coding keys").font(.headline)
            Text("Single keys work while the document has the focus.").font(.caption).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                ForEach(rows, id: \.0) { key, what in
                    GridRow {
                        Text(key).font(.system(.body, design: .rounded).weight(.semibold))
                        Text(what).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 440)
    }
}

// MARK: - Quick-code palette

/// ⌘K: type to find a code (by name, description or working identifier) or
/// a new code's name; Return to apply. Codes in the quick-code slots come
/// first, then the rest by name. Open codes on an inductive layer, a priori
/// codes (with their definitions) on a deductive one.
struct QuickCodePalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var highlighted = 0

    struct Row: Identifiable, Equatable {
        var id: String
        var code: CodingTag?
        var createName: String?
    }

    var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let codes = model.activeTags
        var result: [Row]
        if q.isEmpty {
            let quick = model.quickCodes.compactMap { k in codes.first { $0.key == k } }
            let rest = codes.filter { !model.quickCodes.contains($0.key) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            result = (quick + rest).map { Row(id: $0.key, code: $0) }
        } else {
            // "oc 12" or "OC12" finds open code OC 12 by its working identifier.
            let squeezed = q.replacingOccurrences(of: " ", with: "").lowercased()
            func rank(_ c: CodingTag) -> Int? {
                if model.wid(c.key).replacingOccurrences(of: " ", with: "").lowercased() == squeezed { return 0 }
                let n = c.name
                if n.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil { return 0 }
                let words = n.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" })
                if words.contains(where: { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }) { return 1 }
                if n.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return 2 }
                if c.detail.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return 3 }
                return nil
            }
            var ranked: [(code: CodingTag, rank: Int)] = []
            for c in codes {
                if let r = rank(c) { ranked.append((code: c, rank: r)) }
            }
            ranked.sort { a, b in
                if a.rank != b.rank { return a.rank < b.rank }
                return a.code.name.localizedStandardCompare(b.code.name) == .orderedAscending
            }
            result = ranked.map { item in Row(id: item.code.key, code: item.code) }
            if !codes.contains(where: { $0.name.compare(q, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                result.append(Row(id: "create", createName: q))
            }
        }
        return result
    }

    var body: some View {
        let rows = self.rows
        let noun = model.codeNoun
        let applied = Set(model.focusedSelection.map { model.tags(of: $0).map(\.key) } ?? [])
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tag").foregroundStyle(.secondary)
                PaletteField(
                    text: $query,
                    placeholder: model.hasTextSelection ? "Apply \(noun) to the selection…" : "Add \(model.aCodeNoun) to the selection…",
                    onMove: { step in
                        guard !rows.isEmpty else { return }
                        highlighted = max(0, min(rows.count - 1, highlighted + step))
                    },
                    onSubmit: { createAnyway in
                        let q = query.trimmingCharacters(in: .whitespaces)
                        if createAnyway, !q.isEmpty {
                            model.applyNewCode(named: q)
                        } else if highlighted < rows.count {
                            choose(rows[highlighted])
                        }
                    },
                    onCancel: { model.paletteVisible = false }
                )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            if rows.isEmpty {
                Text(model.activeIsDeductive
                     ? "No a priori codes yet. Type a name to create the first one (it joins A Priori Codes, for the whole project)."
                     : "No open codes in this layer yet. Type a name to create the first one.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                rowView(row, highlighted: i == highlighted, applied: row.code.map { applied.contains($0.key) } ?? false)
                                    .id(row.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { choose(row) }
                                    .onHover { if $0 { highlighted = i } }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: highlighted) { _, new in
                        if new < rows.count { proxy.scrollTo(rows[new].id) }
                    }
                }
            }
            Divider()
            Text("↩ apply   ↑↓ choose   ⌘↩ new \(noun) with this name   esc close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: 480)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onDisappear { model.focusDocument() }
    }

    @ViewBuilder
    func rowView(_ row: Row, highlighted: Bool, applied: Bool) -> some View {
        HStack(spacing: 8) {
            if let code = row.code {
                CodeDot(color: code.color, size: 11)
                Text(code.name).lineLimit(1)
                if !code.detail.isEmpty {
                    Text(code.detail).foregroundStyle(.secondary).lineLimit(1).font(.callout)
                }
                Spacer(minLength: 8)
                if applied {
                    Image(systemName: "checkmark").foregroundStyle(.secondary).help("Already on this selection")
                }
                if let slot = model.quickSlot(of: code.key) {
                    Text("\(slot)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(width: 16, height: 16)
                        .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
                }
                WorkingBadge(text: model.wid(code.key), color: code.color)
            } else if let name = row.createName {
                Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                Text("New \(model.codeNoun) “\(name)”").lineLimit(1)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(highlighted ? Color.accentColor.opacity(0.18) : .clear))
        .padding(.horizontal, 4)
    }

    func choose(_ row: Row) {
        if let code = row.code {
            model.applyCode(code.key)
        } else if let name = row.createName {
            model.applyNewCode(named: name)
        }
    }
}

// MARK: - Protocol palette

/// Q or A on a deductive layer: choose the protocol item the text is the
/// prompt (Q) or the response (A) of; type to filter by number, label or
/// wording, Tab to switch between prompt and response, Return to mark.
/// Only the file's protocol is offered once it has one in this layer.
struct ProtocolPalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var highlighted = 0

    struct Row: Identifiable, Equatable {
        var id: String { item.key }
        var item: ProtocolItem
        var number: Int
        var protocolTitle: String
    }

    var file: String {
        model.textSelectionFile ?? model.focusedSelection.flatMap { model.index.fileOf[$0] } ?? model.openFileKey ?? ""
    }

    var rows: [Row] {
        let protocols = model.segmentProtocols(file: file)
        let all = protocols.flatMap { pr in
            pr.items.enumerated().map { i, item in Row(item: item, number: i + 1, protocolTitle: pr.title) }
        }
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return all }
        if let n = Int(q) { return all.filter { $0.number == n } }
        return all.filter { r in
            r.item.label.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
                || r.item.text.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    var body: some View {
        let rows = self.rows
        let part = model.protocolPalette ?? .response
        let current = model.focusedSelection.flatMap { model.project.selection($0)?.segment }
        let several = Set(rows.map(\.protocolTitle)).count > 1
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "list.bullet.rectangle").foregroundStyle(Color(nsColor: .protocolSegment))
                PaletteField(
                    text: $query,
                    placeholder: "Mark as the \(part.label.lowercased()) of item…",
                    onMove: { step in
                        guard !rows.isEmpty else { return }
                        highlighted = max(0, min(rows.count - 1, highlighted + step))
                    },
                    onSubmit: { _ in
                        if highlighted < rows.count { model.markSegment(item: rows[highlighted].item.key, part: part) }
                    },
                    onCancel: { model.protocolPalette = nil },
                    onTab: { model.protocolPalette = part == .prompt ? .response : .prompt }
                )
                Picker("Part", selection: Binding(get: { part }, set: { model.protocolPalette = $0 })) {
                    ForEach(ProtocolPart.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            Divider()
            if rows.isEmpty {
                Text(query.isEmpty ? "This protocol has no items yet. Add them on its page." : "No item matches.")
                    .foregroundStyle(.secondary)
                    .padding(12)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { i, row in
                                rowView(row, highlighted: i == highlighted, showProtocol: several,
                                        current: current?.item == row.item.key ? current?.part : nil)
                                    .id(row.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture { model.markSegment(item: row.item.key, part: part) }
                                    .onHover { if $0 { highlighted = i } }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .frame(maxHeight: 320)
                    .onChange(of: highlighted) { _, new in
                        if new < rows.count { proxy.scrollTo(rows[new].id) }
                    }
                }
            }
            Divider()
            Text("↩ mark   ↑↓ choose   ⇥ prompt / response   type a number or words to filter   esc close")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .frame(width: 520)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.12)))
        .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        .onChange(of: query) { _, _ in highlighted = 0 }
        .onDisappear { model.focusDocument() }
    }

    @ViewBuilder
    func rowView(_ row: Row, highlighted: Bool, showProtocol: Bool, current: ProtocolPart?) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(row.number)").font(.callout.monospacedDigit().weight(.semibold))
                .foregroundStyle(Color(nsColor: .protocolSegment))
                .frame(width: 22, alignment: .trailing)
            VStack(alignment: .leading, spacing: 1) {
                Text(row.item.label.isEmpty ? "Untitled" : row.item.label).lineLimit(1)
                if !row.item.text.isEmpty {
                    Text(row.item.text).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            if let current {
                Text(current.label).font(.caption).foregroundStyle(.secondary)
                Image(systemName: "checkmark").foregroundStyle(.secondary).help("This selection's item now")
            }
            if showProtocol {
                Text(row.protocolTitle).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(highlighted ? Color.accentColor.opacity(0.18) : .clear))
        .padding(.horizontal, 4)
    }
}

/// The palette's search field: an NSTextField, so arrow keys, Return and
/// Escape reach the palette rather than the field.
struct PaletteField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onMove: (Int) -> Void
    var onSubmit: (_ createAnyway: Bool) -> Void
    var onCancel: () -> Void
    /// Tab, if the palette uses it (else Tab moves the focus as usual).
    var onTab: (() -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        field.cell?.isScrollable = true
        field.cell?.wraps = false
        field.isAutomaticTextCompletionEnabled = false
        context.coordinator.parent = self
        DispatchQueue.main.async { field.window?.makeFirstResponder(field) }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: NSTextField, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? 400, height: 24)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteField?

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent?.text = field.stringValue
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)):
                parent?.onMove(-1)
            case #selector(NSResponder.moveDown(_:)):
                parent?.onMove(1)
            case #selector(NSResponder.insertNewline(_:)):
                let command = NSApp.currentEvent?.modifierFlags.contains(.command) ?? false
                parent?.onSubmit(command)
            case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
                parent?.onSubmit(true)
            case #selector(NSResponder.cancelOperation(_:)):
                parent?.onCancel()
            case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
                guard let onTab = parent?.onTab else { return false }
                onTab()
            default:
                return false
            }
            return true
        }
    }
}

/// Offered when the focused selection has a neighbour it could be merged
/// with (next to it, with only white space between, and coded the same
/// way): merges them into one. Never done without asking. (Takes the model
/// directly: it is built in the coding bar's and the inspector's menus.)
struct MergeButton: View {
    let model: AppModel
    let key: String
    var compact = false

    var body: some View {
        let candidates = model.mergeCandidates(for: key)
        if candidates.count == 1, let other = candidates.first {
            Button {
                model.mergeSelections(key, other)
            } label: {
                Label(compact ? "" : "Merge", systemImage: "arrow.triangle.merge")
            }
            .help(model.mergeTitle(key, other) + ": it is right next to this one and coded the same way. Their memos are kept, joined.")
        } else if candidates.count > 1 {
            Menu {
                ForEach(candidates, id: \.self) { other in
                    Button(model.mergeTitle(key, other)) { model.mergeSelections(key, other) }
                }
            } label: {
                Label(compact ? "" : "Merge", systemImage: "arrow.triangle.merge")
            }
            .fixedSize()
            .help("Merge with a selection right next to this one and coded the same way. Their memos are kept, joined.")
        }
    }
}

/// How far the open file's coding has come in the active layer: one stacked
/// bar, coded (green), irrelevant (grey) and still to do (the empty track),
/// with the figures on hover. Counted in characters that aren't white
/// space, leaving out speaker header lines and time indicators.
struct CodingProgressBar: View {
    @Environment(AppModel.self) private var model
    let fileKey: String
    var height: CGFloat = 5

    var body: some View {
        if let progress = model.codingProgress(fileKey), progress.total > 0 {
            GeometryReader { geo in
                let w = geo.size.width
                let coded = w * progress.fraction(progress.coded)
                let irrelevant = w * progress.fraction(progress.irrelevant)
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    HStack(spacing: 0) {
                        Rectangle().fill(Color.green.opacity(0.8)).frame(width: coded)
                        Rectangle().fill(Color.secondary.opacity(0.45)).frame(width: irrelevant)
                        Spacer(minLength: 0)
                    }
                    .clipShape(Capsule())
                }
            }
            .frame(height: height)
            .help(Self.summary(progress, layer: model.activeLayer?.name))
            .accessibilityElement()
            .accessibilityLabel("Coding progress")
            .accessibilityValue(Self.summary(progress, layer: nil))
            .padding(.horizontal, 10)
            .padding(.top, 6)
        }
    }

    static func percent(_ part: Int, of p: CodingProgress) -> String {
        "\(Int((p.fraction(part) * 100).rounded()))%"
    }

    static func summary(_ p: CodingProgress, layer: String?) -> String {
        "Coded \(percent(p.coded, of: p)) · irrelevant \(percent(p.irrelevant, of: p)) · still to do \(percent(p.pending, of: p))"
            + (layer.map { " (in \($0))" } ?? "")
    }
}

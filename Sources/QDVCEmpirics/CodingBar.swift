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

    var body: some View {
        HStack(spacing: 10) {
            ViewThatFits(in: .horizontal) {
                content(compact: false)
                content(compact: true)
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
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    func content(compact: Bool) -> some View {
        HStack(spacing: 8) {
            if model.hasTextSelection, model.textSelectionFile == fileKey {
                let count = model.textSelection.reduce(0) { $0 + $1.length }
                Text(compact ? "\(count)" : "\(count) characters").foregroundStyle(.secondary).monospacedDigit()
                Button {
                    model.paletteVisible = true
                } label: {
                    Label(compact ? "Code" : "Code…", systemImage: "tag")
                }
                .buttonStyle(.borderedProminent)
                .help("Code the selected text (⌘K or Return)")
                Button(compact ? "Highlight" : "Highlight Only") { model.highlightOnly() }
                    .help("Make a selection without a code yet (H)")
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
                } else {
                    let codes = (model.index.codesForSelection[key] ?? []).compactMap { model.project.code($0) }
                    if codes.isEmpty {
                        Text("No code yet").foregroundStyle(.secondary)
                    } else {
                        ForEach(codes.prefix(compact ? 1 : 3)) { c in
                            CodeChip(code: c, compact: true)
                                .onTapGesture { model.showCode(c.key) }
                        }
                        if codes.count > (compact ? 1 : 3) {
                            Text("+\(codes.count - (compact ? 1 : 3))").foregroundStyle(.secondary)
                        }
                    }
                    Button {
                        model.paletteVisible = true
                    } label: {
                        Label(compact ? "Add" : "Add Code…", systemImage: "plus")
                    }
                    .help("Add a code to this selection (⌘K)")
                }
                Button(role: .destructive) {
                    model.deleteSelection(key)
                } label: {
                    Label(compact ? "" : "Delete", systemImage: "trash")
                }
                .help("Delete this selection (Delete)")
            } else {
                Text(compact ? "Select text to code it" : "Select text, then press Return to code it, or 1–9 for a quick code.")
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 12)
            QuickCodeStrip(compact: compact)
        }
    }
}

/// Quick codes 1–9: click (or press the number) to code the selection.
struct QuickCodeStrip: View {
    @Environment(AppModel.self) private var model
    var compact: Bool

    var body: some View {
        // Captured here, so the context menu (built apart from the view)
        // doesn't read the environment.
        let model = self.model
        let slots = model.quickCodes.enumerated().compactMap { i, key -> (Int, QDACode)? in
            guard !key.isEmpty, let c = model.activeLayer?.codes[key] else { return nil }
            return (i + 1, c)
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
                            CodeChip(code: code, slot: slot, compact: true)
                                .frame(maxWidth: 150)
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(!model.canCode)
                    .opacity(model.canCode ? 1 : 0.55)
                    .help("\(slot): \(code.name)")
                    .contextMenu {
                        Button("Remove from Quick Codes") { model.assignQuickCode(nil, slot: slot) }
                        Button("Show Code") { model.showCode(code.key) }
                    }
                }
            }
        }
    }
}

struct KeyboardHelp: View {
    let rows: [(String, String)] = [
        ("Return or K", "Code the selection (opens the code palette)"),
        ("1 … 9", "Apply quick code 1–9"),
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
                        Text(what).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 400)
    }
}

// MARK: - Quick-code palette

/// ⌘K: type to find a code (or a new code's name), Return to apply.
/// Codes in the quick-code slots come first, then the rest by name.
struct QuickCodePalette: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var highlighted = 0

    struct Row: Identifiable, Equatable {
        var id: String
        var code: QDACode?
        var createName: String?
    }

    var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let codes = (model.activeLayer.map { Array($0.codes.values) } ?? []).filter { $0.kind == .open }
        var result: [Row]
        if q.isEmpty {
            let quick = model.quickCodes.compactMap { k in codes.first { $0.key == k } }
            let rest = codes.filter { !model.quickCodes.contains($0.key) }
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            result = (quick + rest).map { Row(id: $0.key, code: $0) }
        } else {
            func rank(_ c: QDACode) -> Int? {
                let n = c.name
                if n.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil { return 0 }
                let words = n.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "/" })
                if words.contains(where: { $0.range(of: q, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil }) { return 1 }
                if n.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return 2 }
                if c.description.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil { return 3 }
                return nil
            }
            var ranked: [(code: QDACode, rank: Int)] = []
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
        let applied = Set(model.focusedSelection.flatMap { model.index.codesForSelection[$0] } ?? [])
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "tag").foregroundStyle(.secondary)
                PaletteField(
                    text: $query,
                    placeholder: model.hasTextSelection ? "Code the selection as…" : "Add a code to the selection…",
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
                Text("No codes in this layer yet. Type a name to create the first one.")
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
            Text("↩ apply   ↑↓ choose   ⌘↩ new code with this name   esc close")
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
                if !code.description.isEmpty {
                    Text(code.description).foregroundStyle(.secondary).lineLimit(1).font(.callout)
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
            } else if let name = row.createName {
                Image(systemName: "plus.circle.fill").foregroundStyle(.tint)
                Text("New open code “\(name)”").lineLimit(1)
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

/// The palette's search field: an NSTextField, so arrow keys, Return and
/// Escape reach the palette rather than the field.
struct PaletteField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onMove: (Int) -> Void
    var onSubmit: (_ createAnyway: Bool) -> Void
    var onCancel: () -> Void

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
            default:
                return false
            }
            return true
        }
    }
}

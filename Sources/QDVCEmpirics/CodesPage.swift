import AppKit
import EmpiricsCore
import SwiftUI

/// A code in the outline: axial codes contain what they are built from.
/// A code built into several axial codes appears under each.
struct CodeNode: Identifiable {
    var id: String
    var code: QDACode
    var children: [CodeNode]?
}

/// The codes of the active layer, and the evidence for the one chosen:
/// every quote, grouped by file, with its interpretation memo.
struct CodesPage: View {
    @Environment(AppModel.self) private var model
    @State private var filter = ""

    var body: some View {
        HStack(spacing: 0) {
            codeList
                .frame(width: 300)
            Divider()
            Group {
                if let key = model.focusedCode, let code = model.project.code(key), model.index.layerOf[key] == model.activeLayerKey {
                    EvidencePane(code: code)
                } else {
                    ContentUnavailableView("Choose a Code", systemImage: "tag",
                                           description: Text("Its evidence (every quote, with your memos) appears here."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.focusedCode) { _, new in
            if new != nil {
                model.inspectorTab = .code
            }
        }
    }

    var codes: [QDACode] {
        (model.activeLayer.map { Array($0.codes.values) } ?? [])
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func tree() -> [CodeNode] {
        guard let layer = model.activeLayer else { return [] }
        func node(_ c: QDACode, path: String, depth: Int) -> CodeNode {
            let id = path + "/" + c.key
            guard c.kind == .axial, depth < 12 else { return CodeNode(id: id, code: c, children: nil) }
            var children: [QDACode] = c.evidence.compactMap { e in layer.codes[e.target] }
            children.sort { a, b in
                if a.kind != b.kind { return a.kind == .axial }
                return a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            let kids: [CodeNode] = children.map { child in node(child, path: id, depth: depth + 1) }
            return CodeNode(id: id, code: c, children: kids.isEmpty ? nil : kids)
        }
        return codes.filter { $0.kind == .axial && (model.index.parents[$0.key] ?? []).isEmpty }
            .map { node($0, path: "", depth: 0) }
    }

    var codeList: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all = codes
        let open = all.filter { $0.kind == .open }
        return VStack(spacing: 0) {
            List(selection: $model.focusedCode) {
                if !q.isEmpty {
                    Section("Matching “\(q)”") {
                        ForEach(all.filter { $0.name.localizedCaseInsensitiveContains(q) || $0.description.localizedCaseInsensitiveContains(q) }) { c in
                            CodeRow(code: c).tag(c.key)
                        }
                    }
                } else {
                    let roots = tree()
                    if !roots.isEmpty {
                        Section("Axial Codes") {
                            OutlineGroup(roots, children: \.children) { node in
                                CodeRow(code: node.code).tag(node.code.key)
                            }
                        }
                    }
                    Section("Open Codes") {
                        if open.isEmpty {
                            Text("None yet. Select text in a file and press Return to code it.")
                                .font(.callout).foregroundStyle(.secondary)
                        }
                        ForEach(open) { c in
                            CodeRow(code: c).tag(c.key)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            Divider()
            HStack(spacing: 6) {
                Menu {
                    Button("New Open Code…") { model.sheet = .newCode(kind: .open, parent: nil, child: nil) }
                    Button("New Axial Code…") { model.sheet = .newCode(kind: .axial, parent: nil, child: nil) }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .menuIndicator(.hidden)
                .fixedSize()
                TextField("Filter codes", text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                Text("\(all.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(8)
        }
    }
}

struct CodeRow: View {
    @Environment(AppModel.self) private var model
    var code: QDACode

    var body: some View {
        HStack(spacing: 7) {
            CodeDot(color: code.color)
            Image(systemName: code.kind.symbol).font(.caption).foregroundStyle(.secondary)
            Text(code.name).lineLimit(1)
            Spacer(minLength: 4)
            if !code.questions.isEmpty {
                Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(.orange)
                    .help("\(code.questions.count) open question\(code.questions.count == 1 ? "" : "s")")
            }
            if let slot = model.quickSlot(of: code.key) {
                Text("\(slot)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
            }
            Text("\(code.evidence.count)").font(.caption).foregroundStyle(.secondary).monospacedDigit()
        }
        .contextMenu {
            if code.kind == .open {
                Menu("Quick Code") {
                    ForEach(1...9, id: \.self) { n in
                        Button {
                            model.assignQuickCode(code.key, slot: n)
                        } label: {
                            let current = model.quickCodes[n - 1]
                            let name = model.project.code(current)?.name
                            Text("\(n)" + (name.map { "  (now \($0))" } ?? ""))
                        }
                    }
                    Divider()
                    Button("None") {
                        if let s = model.quickSlot(of: code.key) { model.assignQuickCode(nil, slot: s) }
                    }
                }
            }
            if model.project.layers.count > 1 {
                Button("Move to Layer…") { model.sheet = .moveToLayer(code.key) }
            }
            Divider()
            Button("Delete Code…") { model.deleteCode(code.key) }
        }
    }
}

/// Everything that evidences a code. For an open code, its quotes by file;
/// for an axial code, the codes it is built from and their quotes.
struct EvidencePane: View {
    @Environment(AppModel.self) private var model
    var code: QDACode

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                header
                if code.kind == .open {
                    quotes(for: code)
                } else {
                    axial
                }
            }
            .padding(20)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CodeDot(color: code.color, size: 14)
                Text(code.name).font(.title2.weight(.semibold))
                Text(code.kind.label).font(.callout).foregroundStyle(.secondary)
            }
            if !code.description.isEmpty {
                Text(code.description).foregroundStyle(.secondary).textSelection(.enabled)
            }
            let files = model.index.filesForCode[code.key]?.count ?? 0
            Text("\(code.evidence.count) piece\(code.evidence.count == 1 ? "" : "s") of evidence · \(files) file\(files == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.tertiary)
            if !code.questions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(code.questions.enumerated()), id: \.offset) { _, q in
                        Label(q, systemImage: "questionmark.circle").foregroundStyle(.orange).font(.callout)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    /// Quotes for an open code, grouped by file in the sidebar's order.
    @ViewBuilder
    func quotes(for open: QDACode) -> some View {
        let selections = open.evidence.compactMap { e in model.project.selection(e.target) }
        let byFile = Dictionary(grouping: selections, by: \.fileKey)
        let files = model.project.sortedFiles.filter { byFile[$0.key] != nil }
        if selections.isEmpty {
            Text("No evidence yet.").foregroundStyle(.secondary)
        }
        ForEach(files) { f in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: f.kind.symbol).foregroundStyle(.secondary)
                    Text(f.displayTitle).font(.headline)
                    if !f.customID.isEmpty { Text(f.customID).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    Spacer()
                    Text("\(byFile[f.key]?.count ?? 0)").font(.caption).foregroundStyle(.secondary)
                }
                ForEach((byFile[f.key] ?? []).sorted(by: { ($0.first ?? TextSpan(start: 0, length: 0)) < ($1.first ?? TextSpan(start: 0, length: 0)) })) { s in
                    QuoteCard(code: open, selection: s)
                }
            }
        }
    }

    @ViewBuilder
    var axial: some View {
        let layer = model.index.layerOf[code.key].flatMap { model.project.layer($0) }
        let children = code.evidence.compactMap { layer?.codes[$0.target] }
        if children.isEmpty {
            Text("Not built from any codes yet. Add codes from the inspector, or from a code's “Add to Axial Code” menu.")
                .foregroundStyle(.secondary)
        }
        ForEach(children) { child in
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    CodeChip(code: child)
                        .onTapGesture { model.focusedCode = child.key }
                    Spacer()
                }
                let memo = code.memo(for: child.key)
                if !memo.isEmpty {
                    Text(memo).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                }
                ForEach(underlyingOpenCodes(child, in: layer)) { open in
                    if open.key != child.key {
                        Text("via \(open.name)").font(.caption).foregroundStyle(.tertiary)
                    }
                    ForEach(open.evidence.compactMap { model.project.selection($0.target) }) { s in
                        QuoteCard(code: open, selection: s, compact: true)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(child.color.opacity(0.06)))
        }
    }

    /// The open codes under a code (itself, if open), without repeats.
    func underlyingOpenCodes(_ c: QDACode, in layer: CodingLayer?) -> [QDACode] {
        var seen = Set<String>()
        var result: [QDACode] = []
        func walk(_ c: QDACode, _ depth: Int) {
            guard depth < 12, seen.insert(c.key).inserted else { return }
            if c.kind == .open {
                result.append(c)
            } else {
                for e in c.evidence { if let k = layer?.codes[e.target] { walk(k, depth + 1) } }
            }
        }
        walk(c, 0)
        return result
    }
}

/// One quote as evidence for a code: the text, the speaker, the memo, and
/// the way back to it in its file.
struct QuoteCard: View {
    @Environment(AppModel.self) private var model
    var code: QDACode
    var selection: CodeSelection
    var compact = false

    var body: some View {
        let s = selection
        VStack(alignment: .leading, spacing: 6) {
            QuoteBlock(text: model.quoteText(s) ?? "(text not available)", color: code.color, lineLimit: compact ? 6 : nil)
            HStack(spacing: 8) {
                if model.project.settings.interlocutorLayer, let first = s.first, first.page == nil,
                   let turn = TurnDetector.turn(at: first.start, in: model.turns(s.fileKey)) {
                    Label(model.speakerName(turn.label, in: s.fileKey), systemImage: "person.wave.2")
                        .foregroundStyle(Color(nsColor: model.speakerColor(turn.label, in: s.fileKey)))
                }
                if let page = s.first?.page {
                    Text("p. \(page + 1)").foregroundStyle(.secondary)
                }
                let others = (model.index.codesForSelection[s.key] ?? []).filter { $0 != code.key }.compactMap { model.project.code($0) }
                ForEach(others.prefix(4)) { o in
                    CodeChip(code: o, compact: true).onTapGesture { model.focusedCode = o.key }
                }
                Spacer()
                if model.isLost(s.key) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        .help("Couldn't be found after the file changed")
                }
                Button("Show in File") { model.showSelection(s.key) }
                    .buttonStyle(.link)
            }
            .font(.caption)
            if !compact {
                TextField("Why is this evidence for “\(code.name)”?", text: Binding(
                    get: { model.project.code(code.key)?.memo(for: s.key) ?? "" },
                    set: { model.setMemo(code: code.key, target: s.key, $0) }
                ), axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            } else if !code.memo(for: s.key).isEmpty {
                Text(code.memo(for: s.key)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
    }
}

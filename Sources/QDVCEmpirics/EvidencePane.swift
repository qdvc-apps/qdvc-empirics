import AppKit
import EmpiricsCore
import SwiftUI

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
                WorkingBadge(text: model.wid(code.key), color: code.color)
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
                    QuoteCard(code: open.tag, selection: s)
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
                    CodeChip(code: child, badge: model.wid(child.key))
                        .onTapGesture { model.showCode(child.key) }
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
                        QuoteCard(code: open.tag, selection: s, compact: true)
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

/// One quote as evidence for a code (open or a priori): the text, the
/// speaker, the memo, and the way back to it in its file.
struct QuoteCard: View {
    @Environment(AppModel.self) private var model
    var code: CodingTag
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
                let others = model.tags(of: s.key).filter { $0.key != code.key }
                ForEach(others.prefix(4)) { o in
                    CodeChip(tag: o, compact: true, badge: model.wid(o.key)).onTapGesture { model.showTag(o.key) }
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
                    get: { model.evidenceMemo(code: code.key, selection: s.key) },
                    set: { model.setEvidenceMemo(code: code.key, selection: s.key, $0) }
                ), axis: .vertical)
                .lineLimit(1...6)
                .textFieldStyle(.roundedBorder)
                .font(.callout)
            } else if !model.evidenceMemo(code: code.key, selection: s.key).isEmpty {
                Text(model.evidenceMemo(code: code.key, selection: s.key)).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
    }
}

import AppKit
import EmpiricsCore
import SwiftUI

// The Protocols and A Priori Codes pages (sidebar › Deductive): their
// tables, the pages of single protocols and a priori codes, and their
// inspectors. Both are defined for the whole project and applied on
// deductive layers.

extension StudyProtocol {
    var itemCount: Int { items.count }
}

extension AppModel {
    /// Segments per protocol item, all layers.
    func segmentCounts() -> [String: Int] {
        var result: [String: Int] = [:]
        for l in project.layers {
            for s in l.allSelections {
                if let item = s.segment?.item { result[item, default: 0] += 1 }
            }
        }
        return result
    }

    /// Files following each protocol, in any deductive layer.
    func protocolFileCounts() -> [String: Int] {
        var files: [String: Set<String>] = [:]
        for l in project.deductiveLayers {
            for (file, pr) in l.protocols { files[pr, default: []].insert(file) }
        }
        return files.mapValues(\.count)
    }
}

// MARK: - Protocols table

struct ProtocolsTable: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\StudyProtocol.title)]
    @State private var filter = ""

    var body: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all: [StudyProtocol] = Array(model.project.protocols.values)
        let shown: [StudyProtocol] = q.isEmpty ? all : all.filter {
            $0.title.localizedCaseInsensitiveContains(q) || $0.description.localizedCaseInsensitiveContains(q)
        }
        let rows: [StudyProtocol] = shown.sorted(using: sortOrder)
        let segments = model.segmentCounts()
        let files = model.protocolFileCounts()
        VStack(spacing: 0) {
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("No.", value: \StudyProtocol.title) { (pr: StudyProtocol) in
                    WorkingIDCell(model: model, key: pr.key)
                }
                .width(min: 50, ideal: 62, max: 80)
                TableColumn("Title", value: \StudyProtocol.title) { (pr: StudyProtocol) in
                    Label(pr.title, systemImage: "list.bullet.rectangle")
                }
                .width(min: 160, ideal: 240)
                TableColumn("Items", value: \StudyProtocol.itemCount) { (pr: StudyProtocol) in
                    Text("\(pr.items.count)").monospacedDigit()
                }
                .width(min: 50, ideal: 60, max: 80)
                TableColumn("Description", value: \StudyProtocol.description) { (pr: StudyProtocol) in
                    Text(pr.description).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 120, ideal: 260)
                TableColumn("Files") { (pr: StudyProtocol) in
                    Text("\(files[pr.key] ?? 0)").monospacedDigit()
                }
                .width(min: 40, ideal: 50, max: 70)
                TableColumn("Segments") { (pr: StudyProtocol) in
                    Text("\(pr.items.reduce(0) { $0 + (segments[$1.key] ?? 0) })").monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 90)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                ProtocolTableMenu(model: model, keys: keys)
            } primaryAction: { keys in
                if let key = keys.first { model.show(.studyProtocol(key)) }
            }
            TableFooter(count: "\(all.count) protocol\(all.count == 1 ? "" : "s")", filter: $filter) {
                Button {
                    model.newProtocol()
                } label: {
                    Label("New Protocol", systemImage: "plus")
                }
                Text("The structure files follow (an interview protocol, an article's sections). Double-click one to edit its items.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct ProtocolTableMenu: View {
    let model: AppModel
    let keys: Set<String>

    var body: some View {
        if let key = keys.first {
            Button("Open") { model.show(.studyProtocol(key)) }
            Button("Add to Working Area") { model.addToWorkingArea(.studyProtocol(key)) }
                .disabled(model.workingArea.contains(.studyProtocol(key)))
            Divider()
            Button("Delete Protocol…") { model.deleteProtocol(key) }
        }
    }
}

// MARK: - Protocol page

struct ProtocolPage: View {
    @Environment(AppModel.self) private var model
    let protocolKey: String

    var body: some View {
        if let pr = model.project.protocols[protocolKey] {
            ProtocolEditor(studyProtocol: pr)
        } else {
            ContentUnavailableView("Protocol Deleted", systemImage: "list.bullet.rectangle")
        }
    }
}

/// A protocol's own page: its title, description and items. Each item has
/// a short label (for margins and column headings) and its full wording.
struct ProtocolEditor: View {
    @Environment(AppModel.self) private var model
    var studyProtocol: StudyProtocol

    var body: some View {
        let key = studyProtocol.key
        let segments = model.segmentCounts()
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 8) {
                    TextField("Title", text: Binding(get: { model.project.protocols[key]?.title ?? "" },
                                                     set: { v in model.editProtocol(key) { $0.title = v } }))
                        .textFieldStyle(.roundedBorder)
                        .font(.title2)
                    WorkingBadge(text: model.wid(key), color: nil)
                }
                TextField("Description (what this protocol structures, where it comes from)", text: Binding(
                    get: { model.project.protocols[key]?.description ?? "" },
                    set: { v in model.editProtocol(key) { $0.description = v } }
                ), axis: .vertical)
                .lineLimit(2...6)
                .textFieldStyle(.roundedBorder)
                usage(segments)
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Items").font(.headline)
                    Text("In a file, on a deductive layer, mark the text that is an item's prompt (the question asked, the heading) with Q, and its response with A. Both are optional.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if studyProtocol.items.isEmpty {
                    Text("No items yet.").foregroundStyle(.secondary)
                }
                ForEach(Array(studyProtocol.items.enumerated()), id: \.element.key) { i, item in
                    ProtocolItemEditor(protocolKey: key, item: item, index: i, count: studyProtocol.items.count,
                                       segments: segments[item.key] ?? 0)
                }
                Button {
                    model.addProtocolItem(to: key)
                } label: {
                    Label("Add Item", systemImage: "plus")
                }
                Divider()
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        model.deleteProtocol(key)
                    } label: {
                        Label("Delete Protocol…", systemImage: "trash")
                    }
                    .controlSize(.small)
                }
            }
            .padding(20)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    func usage(_ segments: [String: Int]) -> some View {
        let files = model.filesFollowing(studyProtocol.key).count
        let count = studyProtocol.items.reduce(0) { $0 + (segments[$1.key] ?? 0) }
        return Text("Followed by \(files) file\(files == 1 ? "" : "s") · \(count) segment\(count == 1 ? "" : "s") marked")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

struct ProtocolItemEditor: View {
    @Environment(AppModel.self) private var model
    var protocolKey: String
    var item: ProtocolItem
    var index: Int
    var count: Int
    var segments: Int

    private func update(_ change: @escaping (inout ProtocolItem) -> Void) {
        let ik = item.key
        model.editProtocol(protocolKey) { pr in
            guard let i = pr.items.firstIndex(where: { $0.key == ik }) else { return }
            change(&pr.items[i])
        }
    }

    private func move(by step: Int) {
        let pk = protocolKey
        let i = index
        model.perform("Move Item") { p in
            guard var pr = p.protocols[pk], pr.items.indices.contains(i), pr.items.indices.contains(i + step) else { return }
            pr.items.swapAt(i, i + step)
            try p.updateProtocol(pr)
        }
    }

    var body: some View {
        let it = item
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("\(index + 1).").font(.headline).monospacedDigit()
                    .foregroundStyle(Color(nsColor: .protocolSegment))
                TextField("Label", text: Binding(get: { it.label }, set: { v in update { $0.label = v } }))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 220)
                Text(segments == 0 ? "not marked yet" : "\(segments) segment\(segments == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    move(by: -1)
                } label: { Image(systemName: "arrow.up") }
                .disabled(index == 0)
                .help("Move up")
                Button {
                    move(by: 1)
                } label: { Image(systemName: "arrow.down") }
                .disabled(index >= count - 1)
                .help("Move down")
                Button {
                    model.deleteProtocolItem(it.key)
                } label: { Image(systemName: "trash") }
                .help("Delete the item (and its segments)")
            }
            .buttonStyle(.borderless)
            TextField("The full wording: the question as asked, or what the section covers", text: Binding(
                get: { it.text }, set: { v in update { $0.text = v } }
            ), axis: .vertical)
            .lineLimit(1...6)
            .textFieldStyle(.roundedBorder)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// The inspector for a protocol chosen in the table: its title, description
/// and items at a glance, and where it is used.
struct ProtocolSummary: View {
    @Environment(AppModel.self) private var model
    let protocolKey: String

    var body: some View {
        if let pr = model.project.protocols[protocolKey] {
            VStack(alignment: .leading, spacing: 12) {
                InspectorTitle(model: model, title: "Protocol", key: protocolKey)
                TextField("Title", text: Binding(get: { model.project.protocols[protocolKey]?.title ?? "" },
                                                 set: { v in model.editProtocol(protocolKey) { $0.title = v } }))
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                TextField("Description", text: Binding(get: { model.project.protocols[protocolKey]?.description ?? "" },
                                                       set: { v in model.editProtocol(protocolKey) { $0.description = v } }),
                          axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                SectionHeader(title: "Items", trailing: "\(pr.items.count)")
                ForEach(Array(pr.items.enumerated()), id: \.element.key) { i, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(i + 1).").foregroundStyle(.secondary).monospacedDigit()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.label.isEmpty ? "Untitled" : item.label).fontWeight(.medium)
                            if !item.text.isEmpty {
                                Text(item.text).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            }
                        }
                    }
                }
                HStack {
                    Button("Edit Items…") { model.show(.studyProtocol(protocolKey)) }
                    if model.sidebar != .protocolReport {
                        Button("Show Report") {
                            model.reportProtocol = protocolKey
                            model.sidebar = .protocolReport
                        }
                    }
                }
                .controlSize(.small)
                Divider()
                ProtocolUsage(protocolKey: protocolKey)
            }
        }
    }
}

/// Which files follow a protocol (and in which deductive layers), and how
/// many segments each item has.
struct ProtocolUsage: View {
    @Environment(AppModel.self) private var model
    let protocolKey: String

    var body: some View {
        let following = model.filesFollowing(protocolKey)
        let segments = model.segmentCounts()
        let several = model.project.deductiveLayers.count > 1
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Followed By", trailing: following.isEmpty ? nil : "\(following.count)")
            if following.isEmpty {
                Text("No file follows it yet. Choose it in a file's inspector, or mark a prompt or response (Q or A) in a file on a deductive layer.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(following, id: \.file.key) { entry in
                VStack(alignment: .leading, spacing: 1) {
                    Button {
                        model.show(.file(entry.file.key))
                    } label: {
                        ItemLine(model: model, key: entry.file.key, iconWidth: 16)
                    }
                    .buttonStyle(.plain)
                    if several {
                        Text(entry.layers.map(\.name).joined(separator: ", "))
                            .font(.caption).foregroundStyle(.tertiary)
                            .padding(.leading, 22)
                    }
                }
            }
            if let pr = model.project.protocols[protocolKey], !pr.items.isEmpty {
                SectionHeader(title: "Segments by Item")
                ForEach(Array(pr.items.enumerated()), id: \.element.key) { i, item in
                    HStack {
                        Text("\(i + 1). " + (item.label.isEmpty ? "Untitled" : item.label)).lineLimit(1)
                        Spacer()
                        Text("\(segments[item.key] ?? 0)").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            }
        }
    }
}

// MARK: - A priori codes table

struct AprioriCodesTable: View {
    @Environment(AppModel.self) private var model
    @State private var sortOrder = [KeyPathComparator(\AprioriCode.name)]
    @State private var filter = ""

    var body: some View {
        @Bindable var model = model
        let q = filter.trimmingCharacters(in: .whitespaces)
        let all: [AprioriCode] = Array(model.project.aprioriCodes.values)
        let shown: [AprioriCode] = q.isEmpty ? all : all.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.definition.localizedCaseInsensitiveContains(q)
                || $0.source.localizedCaseInsensitiveContains(q)
        }
        let rows: [AprioriCode] = shown.sorted(using: sortOrder)
        VStack(spacing: 0) {
            Table(rows, selection: $model.tableSelection, sortOrder: $sortOrder) {
                TableColumn("No.", value: \AprioriCode.name) { (c: AprioriCode) in
                    WorkingIDCell(model: model, key: c.key)
                }
                .width(min: 56, ideal: 68, max: 86)
                TableColumn("Name", value: \AprioriCode.name) { (c: AprioriCode) in
                    HStack(spacing: 6) {
                        CodeDot(color: c.color)
                        Text(c.name)
                    }
                }
                .width(min: 140, ideal: 220)
                TableColumn("Definition", value: \AprioriCode.definition) { (c: AprioriCode) in
                    Text(c.definition).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 120, ideal: 280)
                TableColumn("Evidence") { (c: AprioriCode) in
                    Text("\(model.index.aprioriEvidenceCount[c.key] ?? 0)").monospacedDigit()
                }
                .width(min: 60, ideal: 70, max: 90)
                TableColumn("Files") { (c: AprioriCode) in
                    Text("\(model.index.filesForApriori[c.key]?.count ?? 0)").monospacedDigit()
                }
                .width(min: 40, ideal: 50, max: 70)
                TableColumn("Source", value: \AprioriCode.source) { (c: AprioriCode) in
                    Text(c.source).foregroundStyle(.secondary).lineLimit(1)
                }
                .width(min: 80, ideal: 160)
                TableColumn("Quick") { (c: AprioriCode) in
                    Text(model.quickSlot(of: c.key).map { "\($0)" } ?? "").monospacedDigit()
                }
                .width(min: 40, ideal: 44, max: 60)
            }
            .contextMenu(forSelectionType: String.self) { keys in
                AprioriCodeTableMenu(model: model, keys: keys)
            } primaryAction: { keys in
                if let key = keys.first { model.show(.aprioriCode(key)) }
            }
            TableFooter(count: "\(all.count) a priori code\(all.count == 1 ? "" : "s")", filter: $filter) {
                Button {
                    model.newAprioriCode()
                } label: {
                    Label("New A Priori Code", systemImage: "plus")
                }
                Text("Defined beforehand, from theory or earlier work; applied on deductive layers.")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

struct AprioriCodeTableMenu: View {
    let model: AppModel
    let keys: Set<String>

    var body: some View {
        if let key = keys.first {
            Button("Open") { model.show(.aprioriCode(key)) }
            Button("Add to Working Area") { model.addToWorkingArea(.aprioriCode(key)) }
                .disabled(model.workingArea.contains(.aprioriCode(key)))
            if model.activeIsDeductive {
                Menu("Quick Code") {
                    ForEach(1...9, id: \.self) { n in
                        Button("\(n)") { model.assignQuickCode(key, slot: n) }
                    }
                    Divider()
                    Button("None") {
                        if let s = model.quickSlot(of: key) { model.assignQuickCode(nil, slot: s) }
                    }
                }
            }
            Divider()
            Button("Delete A Priori Code…") { model.deleteAprioriCode(key) }
        }
    }
}

// MARK: - A priori code page

/// An a priori code's page: its codebook entry at a glance, the open and
/// theorising codes linked to it, and its evidence by file. The inspector edits
/// the entry.
struct AprioriCodePage: View {
    @Environment(AppModel.self) private var model
    let codeKey: String

    var body: some View {
        if let code = model.project.aprioriCodes[codeKey] {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    header(code)
                    codebook(code)
                    links(code)
                    evidence(code)
                }
                .padding(20)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .background(Color(nsColor: .textBackgroundColor))
        } else {
            ContentUnavailableView("A Priori Code Deleted", systemImage: "character.book.closed")
        }
    }

    func header(_ code: AprioriCode) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                CodeDot(color: code.color, size: 14)
                Text(code.name.isEmpty ? "Untitled" : code.name).font(.title2.weight(.semibold))
                Text("A Priori Code").font(.callout).foregroundStyle(.secondary)
                WorkingBadge(text: model.wid(code.key), color: code.color)
            }
            if !code.definition.isEmpty {
                Text(code.definition).textSelection(.enabled)
            }
            let n = model.index.aprioriEvidenceCount[code.key] ?? 0
            let files = model.index.filesForApriori[code.key]?.count ?? 0
            Text("\(n) piece\(n == 1 ? "" : "s") of evidence · \(files) file\(files == 1 ? "" : "s")")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    func codebook(_ code: AprioriCode) -> some View {
        let fields: [(String, String)] = [
            ("Included", code.included), ("Excluded", code.excluded), ("Ideal example", code.example),
            ("Counter-example", code.counterExample), ("Source", code.source),
        ].filter { !$0.1.isEmpty }
        if !fields.isEmpty {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                ForEach(fields, id: \.0) { title, text in
                    GridRow {
                        Text(title).font(.callout).foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        Text(text).font(.callout).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 10).fill(code.color.opacity(0.06)))
        }
    }

    @ViewBuilder
    func links(_ code: AprioriCode) -> some View {
        let links = model.links(to: code.key)
        if !links.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Linked From").font(.headline)
                ForEach(links, id: \.link.key) { entry in
                    HStack(spacing: 8) {
                        CodeChip(code: entry.code, compact: true, badge: model.wid(entry.code.key))
                            .onTapGesture { model.showCode(entry.code.key) }
                        Text(entry.link.type.label.lowercased()).foregroundStyle(.secondary)
                        if !entry.link.memo.isEmpty {
                            Text(entry.link.memo).font(.callout).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                }
            }
        }
    }

    /// Quotes by file, in the sidebar's order (all deductive layers).
    @ViewBuilder
    func evidence(_ code: AprioriCode) -> some View {
        let selections = model.project.aprioriEvidence(of: code.key).compactMap { model.project.selection($0.evidence.target) }
        let byFile = Dictionary(grouping: selections, by: \.fileKey)
        let files = model.project.sortedFiles.filter { byFile[$0.key] != nil }
        if selections.isEmpty {
            Text("No evidence yet. On a deductive layer, select text and press Return (or a quick-code number) to apply it.")
                .foregroundStyle(.secondary)
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
                    QuoteCard(code: code.tag, selection: s)
                }
            }
        }
    }
}

// MARK: - A priori code inspector

/// An a priori code's codebook entry: name, colour, definition, what is
/// included and excluded, an ideal example and a counter-example, and
/// where it comes from.
struct AprioriCodeEditor: View {
    @Environment(AppModel.self) private var model
    let codeKey: String

    func field(_ title: String, _ placeholder: String, _ path: WritableKeyPath<AprioriCode, String>) -> some View {
        LabeledField(title) {
            TextField(placeholder, text: Binding(
                get: { model.project.aprioriCodes[codeKey]?[keyPath: path] ?? "" },
                set: { v in model.editAprioriCode(codeKey) { $0[keyPath: path] = v } }
            ), axis: .vertical)
            .lineLimit(1...10)
            .textFieldStyle(.roundedBorder)
        }
    }

    var body: some View {
        if let code = model.project.aprioriCodes[codeKey] {
            let key = codeKey
            VStack(alignment: .leading, spacing: 12) {
                InspectorTitle(model: model, title: "A Priori Code", key: key, trailing: "all deductive layers")
                TextField("Name", text: Binding(get: { model.project.aprioriCodes[key]?.name ?? "" },
                                                set: { v in model.editAprioriCode(key) { $0.name = v } }))
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                if code.name.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("A code needs a name.").font(.caption).foregroundStyle(.red)
                }
                if model.activeIsDeductive {
                    Picker("Quick", selection: Binding(get: { model.quickSlot(of: key) ?? 0 }, set: { n in
                        if n == 0 {
                            if let s = model.quickSlot(of: key) { model.assignQuickCode(nil, slot: s) }
                        } else {
                            model.assignQuickCode(key, slot: n)
                        }
                    })) {
                        Text("None").tag(0)
                        ForEach(1...9, id: \.self) { Text("\($0)").tag($0) }
                    }
                    .frame(width: 110)
                    .help("Quick code number in \(model.activeLayer?.name ?? "this layer"): press it in the document to apply this code")
                }
                ColourSwatches(selected: code.colour) { c in model.editAprioriCode(key) { $0.colour = c } }
                field("Definition", "What the code means", \.definition)
                field("What is included", "When to use it", \.included)
                field("What is excluded", "When not to use it (and what to use instead)", \.excluded)
                field("Ideal example", "Text that fits it exactly", \.example)
                field("Counter-example", "A near miss: text that looks as if it fits, but doesn't", \.counterExample)
                field("Source", "Theory, literature or earlier study it comes from", \.source)

                let n = model.index.aprioriEvidenceCount[key] ?? 0
                let files = model.index.filesForApriori[key]?.count ?? 0
                HStack {
                    Text("\(n) selection\(n == 1 ? "" : "s") in \(files) file\(files == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if model.sidebar != .aprioriCode(key) {
                        Button("Show Evidence") { model.show(.aprioriCode(key)) }
                            .controlSize(.small)
                    }
                }
                let links = model.links(to: key)
                SectionHeader(title: "Linked From", trailing: links.isEmpty ? nil : "\(links.count)")
                if links.isEmpty {
                    Text("No open or theorising code is linked to it yet.").font(.callout).foregroundStyle(.secondary)
                }
                ForEach(links, id: \.link.key) { entry in
                    HStack(spacing: 6) {
                        CodeChip(code: entry.code, compact: true, badge: model.wid(entry.code.key))
                            .onTapGesture { model.showCode(entry.code.key) }
                        Text(entry.link.type.label.lowercased()).font(.callout).foregroundStyle(.secondary)
                    }
                }
                if !code.by.isEmpty || !code.created.isEmpty {
                    Text([code.by.isEmpty ? nil : model.personName(code.by).map { "By " + $0 },
                          code.created.isEmpty ? nil : String(code.created.prefix(10))]
                            .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.tertiary)
                }
                Divider()
                HStack {
                    Spacer()
                    Button(role: .destructive) {
                        model.deleteAprioriCode(key)
                    } label: {
                        Label("Delete A Priori Code…", systemImage: "trash")
                    }
                }
                .controlSize(.small)
            }
        }
    }
}

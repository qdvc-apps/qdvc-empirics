import AppKit
import EmpiricsCore
import SwiftUI

// MARK: - Layers

/// Layers of interpretation, like the layers of an image editor: code in
/// one at a time, show others beside it.
struct LayersPage: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""
    @State private var newKind: LayerKind = .inductive

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Layers").font(.title2.weight(.semibold))
                Text("Each layer is deductive or inductive. Deductive layers apply what was defined beforehand: protocols and a priori codes. Inductive layers hold what emerges from the data: open and axial codes. Every selection lives in exactly one layer. Add layers for other theoretical lenses or other researchers; a layer's kind can change only while nothing is coded in it. You code in the active layer; other layers can show beside it as underlines.")
                    .foregroundStyle(.secondary)
                ForEach(Array(model.project.layers.enumerated()), id: \.element.key) { i, layer in
                    row(layer, index: i)
                }
                HStack {
                    TextField("New layer name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit(add)
                    Picker("Kind", selection: $newKind) {
                        ForEach(LayerKind.allCases, id: \.self) { k in Text(k.label).tag(k) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                    Button("Add Layer", action: add)
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Divider()
                interlocutor
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        model.addLayer(named: name, kind: newKind)
        newName = ""
    }

    @ViewBuilder
    func row(_ layer: CodingLayer, index: Int) -> some View {
        let active = layer.key == model.activeLayerKey
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    model.setActiveLayer(layer.key)
                } label: {
                    Image(systemName: active ? "pencil.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(active ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(active ? "You are coding in this layer" : "Code in this layer")
                Button {
                    model.setLayerVisible(layer.key, !model.isLayerVisible(layer.key))
                } label: {
                    Image(systemName: model.isLayerVisible(layer.key) ? "eye" : "eye.slash")
                        .foregroundStyle(active ? .tertiary : .secondary)
                }
                .buttonStyle(.plain)
                .disabled(active)
                .help("Show this layer's selections as underlines while coding in another")
                TextField("Name", text: Binding(get: { layer.name }, set: { v in
                    model.edit { p in if let i = p.layerIndex(layer.key) { p.layers[i].name = v } }
                }))
                .textFieldStyle(.roundedBorder)
                .font(.headline)
                Picker("Kind", selection: Binding(get: { layer.kind }, set: { k in
                    model.perform("Change Layer Kind") { p in try p.setLayerKind(layer.key, k) }
                })) {
                    ForEach(LayerKind.allCases, id: \.self) { k in Text(k.label).tag(k) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .disabled(!layer.isEmpty)
                .help(layer.isEmpty ? "Deductive or inductive" : "A layer's kind can't change once something is coded in it")
                Text(summary(layer))
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
                Button { model.perform("Move Layer") { p in p.moveLayer(layer.key, to: index - 1) } } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless).disabled(index == 0)
                Button { model.perform("Move Layer") { p in p.moveLayer(layer.key, to: index + 1) } } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.borderless).disabled(index == model.project.layers.count - 1)
                Button { model.deleteLayer(layer.key) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(model.project.layers.filter { $0.kind == layer.kind }.count < 2)
                    .help("Delete this layer and everything in it (a project keeps at least one layer of each kind)")
            }
            HStack {
                TextField("Description (the lens, or whose reading this is)", text: Binding(get: { layer.description }, set: { v in
                    model.edit { p in if let i = p.layerIndex(layer.key) { p.layers[i].description = v } }
                }), axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.roundedBorder)
                Picker("Researcher", selection: Binding(get: { layer.researcher }, set: { v in
                    model.perform("Set Layer Researcher") { p in if let i = p.layerIndex(layer.key) { p.layers[i].researcher = v } }
                })) {
                    Text("Anyone").tag("")
                    ForEach(model.project.researchers) { r in Text(model.personName(r.key) ?? "").tag(r.key) }
                }
                .fixedSize()
            }
            .padding(.leading, 56)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.03)))
    }

    func summary(_ layer: CodingLayer) -> String {
        if layer.isDeductive {
            let applied = layer.aprioriEvidence.values.reduce(0) { $0 + $1.count }
            return "\(layer.selectionCount) selections · \(applied) a priori coding\(applied == 1 ? "" : "s") · \(layer.protocols.count) file\(layer.protocols.count == 1 ? "" : "s") with a protocol"
        }
        let open = layer.codes.values.filter { $0.kind == .open }.count
        let axial = layer.codes.values.filter { $0.kind == .axial }.count
        return "\(layer.selectionCount) selections · \(open) open · \(axial) axial codes"
    }

    var interlocutor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(get: { model.project.settings.interlocutorLayer }, set: { v in
                model.perform(v ? "Enable Interlocutor Layer" : "Disable Interlocutor Layer") { p in p.settings.interlocutorLayer = v }
            })) {
                Text("Interlocutor layer").font(.headline)
            }
            .toggleStyle(.switch)
            Text("Finds the conversational turns in transcripts from their speaker header lines (“John Smith:”, “ALICE BOB”, a name alone on its line…), and maps each speaker to a researcher or interviewee. Speakers show in the margin, and T selects the turn under the cursor. Assign speakers per file in the File inspector.")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Project

struct ProjectPage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Project Settings").font(.title2.weight(.semibold))
                LabeledField("Title") {
                    TextField("Title", text: Binding(get: { model.project.settings.title }, set: { v in
                        model.edit { $0.settings.title = v }
                    }))
                    .textFieldStyle(.roundedBorder)
                }
                LabeledField("Description") {
                    TextField("What the project is about", text: Binding(get: { model.project.settings.description }, set: { v in
                        model.edit { $0.settings.description = v }
                    }), axis: .vertical)
                    .lineLimit(2...8)
                    .textFieldStyle(.roundedBorder)
                }
                Divider()
                Text("Folders").font(.headline)
                LabeledField("Workspace (tracked in Git)") {
                    HStack {
                        Text(model.workspaceURL?.path ?? "").font(.callout.monospaced()).textSelection(.enabled).lineLimit(2)
                        Spacer()
                        Button("Show in Finder") { model.revealInFinder() }.controlSize(.small)
                    }
                }
                LabeledField("Full-texts (read only; remembered on this Mac only)") {
                    HStack {
                        Text(model.fullTextsURL?.path ?? "Not set on this Mac")
                            .font(.callout.monospaced())
                            .foregroundStyle(model.fullTextsURL == nil ? Color.orange : Color.primary)
                            .textSelection(.enabled)
                            .lineLimit(2)
                        Spacer()
                        Button("Choose…") { model.chooseFullTextsFolder() }.controlSize(.small)
                        if model.fullTextsURL != nil {
                            Button("Forget") { model.forgetFullTextsFolder() }.controlSize(.small)
                        }
                    }
                }
                Divider()
                RealNamesSettings()
                Divider()
                Text("Data").font(.headline)
                Toggle(isOn: Binding(get: { model.project.settings.storeQuotes }, set: { v in
                    model.perform(v ? "Store Quotes" : "Stop Storing Quotes") { p in
                        p.settings.storeQuotes = v
                        if !v {
                            for li in p.layers.indices {
                                for f in p.layers[li].selections.keys {
                                    for si in p.layers[li].selections[f]!.indices { p.layers[li].selections[f]![si].quote = "" }
                                }
                            }
                        }
                    }
                })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Store quotes in the workspace")
                        Text("Each selection's text is written into its YAML file, so the workspace reads well in Git and selections can be found again if a full-text is corrected. Turn off to keep every word of the full-texts out of the workspace (positions and a checksum only); turning it off removes the quotes already stored.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
                LabeledField("Interrelation types") {
                    StringListEditor(items: model.project.settings.interrelationTypes, placeholder: "Type", addTitle: "Add Type", multiline: false) { list in
                        model.edit { $0.settings.interrelationTypes = list }
                    }
                    .frame(maxWidth: 320, alignment: .leading)
                }
                Divider()
                stats
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    var stats: some View {
        let p = model.project
        let selections = p.layers.reduce(0) { $0 + $1.selectionCount }
        let codes = p.layers.reduce(0) { $0 + $1.codes.count }
        return Text("\(p.files.count) files · \(p.layers.count) layer\(p.layers.count == 1 ? "" : "s") · \(selections) selections · \(codes) codes · \(p.attributeSheets.count) attribute sheets · \(p.responses.count) response sheets")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// Real-name mapping files: CSVs in the full-texts folder that map
/// researchers' and interviewees' keys to their real names.
struct RealNamesSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Real Names").font(.headline)
            Text("Researchers and interviewees are known in the workspace only by pseudonyms. To see real names, keep a mapping file (CSV) for each in the full-texts folder: one row per person with their key, pseudonym and real first and last names. The app only reads it, keeps the names in memory, and shows them only while View › Show Real Names is on (it is off at every launch).")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            row("Researchers", path: model.project.settings.researcherNamesFile, kind: .researchers)
            row("Interviewees", path: model.project.settings.intervieweeNamesFile, kind: .interviewees)
            if let problem = model.realNamesProblem {
                Label(problem, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if model.hasRealNameFiles {
                HStack {
                    Text("\(model.realNames.count) real name\(model.realNames.count == 1 ? "" : "s") loaded.")
                        .font(.callout).foregroundStyle(.secondary)
                    Toggle("Show real names", isOn: Binding(get: { model.showRealNames }, set: { model.showRealNames = $0 }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                    Button("Reload") { model.loadRealNames() }
                        .controlSize(.small)
                }
            }
        }
    }

    func row(_ title: String, path: String, kind: AppModel.PeopleKind) -> some View {
        LabeledField(title) {
            HStack {
                Text(path.isEmpty ? "No mapping file" : path)
                    .font(.callout.monospaced())
                    .foregroundStyle(path.isEmpty ? Color.secondary : Color.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Choose…") { model.chooseNamesFile(kind) }
                Button("Save Template…") { model.saveNamesTemplate(kind) }
                    .help("Save a CSV listing everyone's key and pseudonym, to fill in with real names")
                if !path.isEmpty {
                    Button("Clear") { model.setNamesFile(kind, "") }
                }
            }
            .controlSize(.small)
        }
    }
}

// MARK: - Pages still to come

/// A page whose feature arrives in a later update.
struct ComingSoonPage: View {
    var title: String
    var systemImage: String
    var text: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(text))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

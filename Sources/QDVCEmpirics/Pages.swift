import AppKit
import EmpiricsCore
import SwiftUI

// MARK: - People

/// Researchers (real names) and interviewees (pseudonyms, with consent
/// forms kept in the full-texts folder).
struct PeoplePage: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                researchers
                Divider()
                interviewees
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    var researchers: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Researchers").font(.title2.weight(.semibold))
            Text("The people doing the analysis, by their real names. Layers, selections and codebook answers can be attributed to them.")
                .foregroundStyle(.secondary)
            HStack {
                Text("This Mac's researcher:")
                Picker("This Mac's researcher", selection: Binding(
                    get: { model.currentResearcher ?? "" },
                    set: { model.setCurrentResearcher($0.isEmpty ? nil : $0) }
                )) {
                    Text("Not chosen").tag("")
                    ForEach(model.project.researchers) { r in Text(r.fullName.isEmpty ? "Unnamed" : r.fullName).tag(r.key) }
                }
                .labelsHidden()
                .fixedSize()
                Text("Remembered on this Mac only; your codebook answers are filed under this name.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            ForEach(model.project.researchers) { r in
                HStack {
                    TextField("First name", text: Binding(get: { r.firstName }, set: { v in
                        model.edit { p in if let i = p.researchers.firstIndex(where: { $0.key == r.key }) { p.researchers[i].firstName = v } }
                    }))
                    TextField("Last name", text: Binding(get: { r.lastName }, set: { v in
                        model.edit { p in if let i = p.researchers.firstIndex(where: { $0.key == r.key }) { p.researchers[i].lastName = v } }
                    }))
                    if r.key == model.currentResearcher {
                        Text("This Mac").font(.caption).foregroundStyle(.secondary)
                    }
                    Button {
                        model.perform("Delete Researcher") { p in p.deleteResearcher(r.key) }
                    } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Remove this researcher")
                }
                .textFieldStyle(.roundedBorder)
            }
            Button {
                model.perform("Add Researcher") { p in
                    p.researchers.append(Researcher(key: p.newKey(Keys.researcher), firstName: "", lastName: ""))
                }
            } label: { Label("Add Researcher", systemImage: "plus") }
        }
    }

    var interviewees: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Interviewees").font(.title2.weight(.semibold))
            Label {
                Text("Names here are **pseudonyms**. Never enter an interviewee's real name: this list is saved in the workspace, which is meant to be shared through Git. Signed consent forms stay in the full-texts folder; only their location is recorded.")
            } icon: {
                Image(systemName: "theatermasks.fill").foregroundStyle(.purple)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.purple.opacity(0.08)))
            ForEach(model.project.interviewees) { i in
                HStack {
                    TextField("First name (pseudonym)", text: Binding(get: { i.firstName }, set: { v in
                        model.edit { p in if let x = p.interviewees.firstIndex(where: { $0.key == i.key }) { p.interviewees[x].firstName = v } }
                    }))
                    TextField("Last name (pseudonym)", text: Binding(get: { i.lastName }, set: { v in
                        model.edit { p in if let x = p.interviewees.firstIndex(where: { $0.key == i.key }) { p.interviewees[x].lastName = v } }
                    }))
                    consent(i)
                    Button {
                        model.perform("Delete Interviewee") { p in p.deleteInterviewee(i.key) }
                    } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain)
                    .help("Remove this interviewee (the consent form itself is untouched)")
                }
                .textFieldStyle(.roundedBorder)
            }
            Button {
                model.perform("Add Interviewee") { p in
                    p.interviewees.append(Interviewee(key: p.newKey(Keys.interviewee), firstName: "", lastName: ""))
                }
            } label: { Label("Add Interviewee", systemImage: "plus") }
        }
    }

    @ViewBuilder
    func consent(_ i: Interviewee) -> some View {
        if i.consentForm.isEmpty {
            Button("Consent Form…") { model.chooseConsentForm(for: i.key) }
                .controlSize(.small)
                .help("Choose the signed consent form (a PDF in the full-texts folder)")
        } else {
            Menu {
                Button("View") { model.sheet = .consent(i.key) }
                Button("Choose Another…") { model.chooseConsentForm(for: i.key) }
                Button("Remove Link") {
                    model.perform("Remove Consent Form") { p in
                        if let x = p.interviewees.firstIndex(where: { $0.key == i.key }) { p.interviewees[x].consentForm = "" }
                    }
                }
            } label: {
                Label("Consent", systemImage: model.fullTexts?.exists(i.consentForm) == true ? "checkmark.seal.fill" : "exclamationmark.triangle")
            }
            .fixedSize()
            .controlSize(.small)
            .help(i.consentForm)
        }
    }
}

// MARK: - Layers

/// Layers of interpretation, like the layers of an image editor: code in
/// one at a time, show others beside it.
struct LayersPage: View {
    @Environment(AppModel.self) private var model
    @State private var newName = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Layers").font(.title2.weight(.semibold))
                Text("Each selection and code lives in exactly one layer. Most projects need only one; add layers for different theoretical lenses or researchers. You code in the active layer; other layers can show beside it as underlines.")
                    .foregroundStyle(.secondary)
                ForEach(Array(model.project.layers.enumerated()), id: \.element.key) { i, layer in
                    row(layer, index: i)
                }
                HStack {
                    TextField("New layer name", text: $newName)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 260)
                        .onSubmit(add)
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
        model.addLayer(named: name)
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
                Text("\(layer.selectionCount) selections · \(layer.codes.count) codes")
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
                Button { model.perform("Move Layer") { p in p.moveLayer(layer.key, to: index - 1) } } label: { Image(systemName: "arrow.up") }
                    .buttonStyle(.borderless).disabled(index == 0)
                Button { model.perform("Move Layer") { p in p.moveLayer(layer.key, to: index + 1) } } label: { Image(systemName: "arrow.down") }
                    .buttonStyle(.borderless).disabled(index == model.project.layers.count - 1)
                Button { model.deleteLayer(layer.key) } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .disabled(model.project.layers.count < 2)
                    .help("Delete this layer and everything in it")
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
                    ForEach(model.project.researchers) { r in Text(r.fullName).tag(r.key) }
                }
                .fixedSize()
            }
            .padding(.leading, 56)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10).fill(active ? Color.accentColor.opacity(0.07) : Color.primary.opacity(0.03)))
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
                Text("Project").font(.title2.weight(.semibold))
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
        return Text("\(p.files.count) files · \(p.layers.count) layer\(p.layers.count == 1 ? "" : "s") · \(selections) selections · \(codes) codes · \(p.codebooks.count) codebooks · \(p.responses.count) response sheets")
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

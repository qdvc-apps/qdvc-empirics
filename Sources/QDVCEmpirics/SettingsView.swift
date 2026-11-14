import AppKit
import EmpiricsCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            ReadingSettings()
                .tabItem { Label("Reading", systemImage: "textformat.size") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
        }
        .frame(width: 600)
    }
}

/// How full-texts look while coding. Saved on this Mac only.
struct ReadingSettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        Form {
            Picker("Font", selection: $model.readingFont) {
                ForEach(ReadingFont.allCases) { Text($0.label).tag($0) }
            }
            LabeledContent("Size") {
                HStack {
                    Slider(value: $model.readingSize, in: 11...28, step: 1)
                    Text("\(Int(model.readingSize)) pt").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            LabeledContent("Line spacing") {
                HStack {
                    Slider(value: $model.lineSpacing, in: 1.0...2.0, step: 0.05)
                    Text(String(format: "%.2f", model.lineSpacing)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Picker("Margins", selection: $model.margins) {
                ForEach(MarginPreset.allCases) { Text($0.label).tag($0) }
            }
            LabeledContent("Highlight strength") {
                Slider(value: $model.highlightStrength, in: 0.12...0.5)
            }
            Toggle("Show coding stripes beside the text", isOn: $model.showStripes)
            Toggle("Show open code names beside the stripes (when the window is wide enough)", isOn: $model.showCodeNames)
                .disabled(!model.showStripes)
            Toggle("Show other visible layers as underlines", isOn: $model.showOtherLayers)
            Toggle("Show the welcome window at launch", isOn: $model.showWelcomeAtLaunch)
            Text("A long session is easier on the eyes with a serif font, generous line spacing and a column of about 60–80 characters.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
    }
}

/// What this Mac remembers about projects, outside their workspaces, and a
/// way to forget it.
struct PrivacySettings: View {
    @Environment(AppModel.self) private var model
    @State private var remembered: [DeviceStore.Remembered] = []

    var body: some View {
        Form {
            Section {
                Text("Each project's full-texts folder, who you are in it, and your Working Area are remembered on this Mac only (never in the workspace or Git). Real names from mapping files are never stored anywhere: they are read from the full-texts folder each time. Forgetting doesn't touch any files.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Section("Remembered on this Mac") {
                if remembered.isEmpty {
                    Text("Nothing remembered.").foregroundStyle(.secondary)
                }
                ForEach(remembered) { r in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(r.title).fontWeight(.medium)
                            if let path = r.fullTextsPath {
                                Text("Full-texts: " + (path as NSString).abbreviatingWithTildeInPath)
                                    .font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                            if r.researcher != nil {
                                Text("Researcher identity remembered").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("Forget") { forget(r.project) }
                    }
                }
            }
            Section {
                HStack {
                    Button("Forget All", role: .destructive) {
                        for r in remembered { forget(r.project) }
                    }
                    .disabled(remembered.isEmpty)
                    Spacer()
                    Button("Clear Recent Projects") { model.clearRecent() }
                        .disabled(model.recentWorkspaces.isEmpty)
                }
            }
            Section("Network") {
                Label("QDVC Empirics never connects to the network. It is sandboxed without network access, so macOS itself blocks any attempt, and it has no dependencies.",
                      systemImage: "network.slash")
                    .font(.callout)
            }
        }
        .formStyle(.grouped)
        .padding(.vertical, 8)
        .onAppear { remembered = DeviceStore.remembered }
    }

    func forget(_ project: String) {
        if model.isOpen && model.project.settings.key == project {
            model.forgetFullTextsFolder()
            model.setCurrentResearcher(nil)
        }
        DeviceStore.forgetAll(project: project)
        remembered = DeviceStore.remembered
    }
}

import AppKit
import EmpiricsCore
import SwiftUI

/// The main window: the project's files and pages in the sidebar, the
/// document (or page) in the middle, the inspector on the right.
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var columns: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columns) {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            VStack(spacing: 0) {
                if let notice = model.notice {
                    NoticeBanner(notice: notice) { model.notice = nil }
                }
                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
        }
        .inspector(isPresented: $model.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 280, ideal: 340, max: 520)
        }
        .toolbar { toolbar }
        .navigationTitle(model.isOpen ? model.project.settings.title : "QDVC Empirics")
        .navigationSubtitle(subtitle)
        .sheet(item: $model.sheet) { kind in
            SheetHost(kind: kind).environment(model)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.isOpen && model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in model.undoManager = new }
        .onChange(of: model.sidebar) { _, _ in model.sidebarChanged() }
        .task(id: model.notice?.id) {
            // Information goes away by itself; warnings stay until dismissed.
            guard let notice = model.notice, !notice.isWarning, notice.action == nil else { return }
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if model.notice?.id == notice.id { model.notice = nil }
        }
        .modifier(NoWritingTools())
    }

    private var subtitle: String {
        switch model.sidebar {
        case .file(let k): return model.project.files[k]?.displayTitle ?? ""
        case .codes: return "Codes"
        case .codebooks: return "Codebooks"
        case .people: return "People"
        case .layers: return "Layers"
        case .project: return "Project"
        case nil: return ""
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebar {
        case .file(let k): DocumentPage(fileKey: k)
        case .codes: CodesPage()
        case .codebooks: CodebooksPage()
        case .people: PeoplePage()
        case .layers: LayersPage()
        case .project: ProjectPage()
        case nil:
            ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left",
                                   description: Text("Choose a file or a page in the sidebar."))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            LayerMenu()
            if model.project.settings.interlocutorLayer {
                Toggle(isOn: Binding(get: { model.showSpeakers }, set: { model.setShowSpeakers($0) })) {
                    Label("Interlocutors", systemImage: "person.wave.2")
                }
                .help("Show the Interlocutor layer: who is speaking in each turn")
            }
            if let key = model.openFileKey, let file = model.project.files[key] {
                Menu {
                    ForEach(CodingStatus.allCases, id: \.self) { s in
                        Button {
                            model.setStatus(s, file: key)
                        } label: {
                            if s == file.status { Label(s.label, systemImage: "checkmark") } else { Text(s.label) }
                        }
                    }
                    Divider()
                    Button("Next File Not Yet Coded") { model.nextUncodedFile() }
                } label: {
                    Label(file.status.label, systemImage: file.status.symbol)
                }
                .help("This file's coding status")
            }
            Button {
                model.showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the inspector (⌥⌘I)")
        }
    }
}

/// The toolbar's layer menu: the active layer (where new coding goes), and
/// which other layers show (as underlines).
struct LayerMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Menu {
            Section("Code in") {
                ForEach(model.project.layers) { layer in
                    Button {
                        model.setActiveLayer(layer.key)
                    } label: {
                        if layer.key == model.activeLayerKey {
                            Label(layer.name, systemImage: "checkmark")
                        } else {
                            Text(layer.name)
                        }
                    }
                }
            }
            if model.project.layers.count > 1 {
                Section("Also show") {
                    ForEach(model.project.layers.filter { $0.key != model.activeLayerKey }) { layer in
                        Toggle(layer.name, isOn: Binding(get: { model.isLayerVisible(layer.key) },
                                                         set: { model.setLayerVisible(layer.key, $0) }))
                    }
                }
            }
            Divider()
            Button("Manage Layers…") { model.sidebar = .layers }
        } label: {
            Label(model.activeLayer?.name ?? "Layer", systemImage: "square.3.layers.3d")
                .labelStyle(.titleAndIcon)
        }
        .help("The layer you are coding in")
    }
}

/// A file's document: text or PDF, or why it can't be shown; the code
/// palette floats over it.
struct DocumentPage: View {
    @Environment(AppModel.self) private var model
    let fileKey: String

    var body: some View {
        let _ = model.documentsRevision
        Group {
            switch model.documentState(fileKey) {
            case .noFullTexts:
                ContentUnavailableView {
                    Label("Full-Texts Folder Not Set", systemImage: "folder.badge.questionmark")
                } description: {
                    Text("This Mac doesn't know where this project's full-texts are. They live outside the workspace, so each Mac remembers their folder for itself.")
                } actions: {
                    Button("Choose Full-Texts Folder…") { model.chooseFullTextsFolder() }
                }
            case .missing(let path):
                ContentUnavailableView {
                    Label("File Not Found", systemImage: "doc.questionmark")
                } description: {
                    Text("“\(path)” isn't in the full-texts folder on this Mac. If it was moved or renamed, put it back, or change the file's path in the File inspector.")
                } actions: {
                    Button("Choose Full-Texts Folder…") { model.chooseFullTextsFolder() }
                }
            case .failed(let message):
                ContentUnavailableView("Can't Show This File", systemImage: "exclamationmark.triangle",
                                       description: Text(message))
            case .text(let text):
                TextCodingView(fileKey: fileKey, text: text).id(fileKey)
            case .pdf(let document):
                PDFCodingView(fileKey: fileKey, document: document).id(fileKey)
            }
        }
        .overlay(alignment: .top) {
            if model.paletteVisible, model.canCode {
                QuickCodePalette()
                    .padding(.top, 48)
                    .transition(.opacity)
            }
        }
        .task(id: fileKey) { model.prepareDocument(fileKey) }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        let files = model.visibleFiles
        let all = model.project.files.count
        let coded = model.project.files.values.filter { $0.status == .coded }.count
        List(selection: $model.sidebar) {
            Section("Analysis") {
                Label("Codes", systemImage: "tag").tag(SidebarItem.codes)
                Label("Codebooks", systemImage: "list.bullet.clipboard").tag(SidebarItem.codebooks)
                Label("People", systemImage: "person.2").tag(SidebarItem.people)
                Label("Layers", systemImage: "square.3.layers.3d").tag(SidebarItem.layers)
                Label("Project", systemImage: "gearshape").tag(SidebarItem.project)
            }
            Section {
                ForEach(files) { f in
                    FileRow(file: f, count: model.index.selectionCount[f.key] ?? 0)
                        .tag(SidebarItem.file(f.key))
                        .contextMenu { fileMenu(f) }
                }
                if all == 0 {
                    Text("No files yet. Add files from the full-texts folder with the + below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else if files.isEmpty {
                    Text("No files match “\(model.fileFilter)”.").font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                HStack {
                    Text("Empirical Files")
                    Spacer()
                    if all > 0 { Text("\(coded) of \(all) coded").monospacedDigit() }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 6) {
                if all > 0 {
                    ProgressView(value: Double(coded), total: Double(max(all, 1)))
                        .progressViewStyle(.linear)
                        .tint(.green)
                        .help("\(coded) of \(all) files marked Coded")
                }
                HStack(spacing: 6) {
                    Menu {
                        Button("Add Files…") { model.addFilesPanel() }
                        Button("Add New Files from Full-Texts Folder…") { model.scanForNewFiles() }
                        Divider()
                        Button("Choose Full-Texts Folder…") { model.chooseFullTextsFolder() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .menuStyle(.button)
                    .buttonStyle(.borderless)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Add empirical files from the full-texts folder")
                    TextField("Filter", text: $model.fileFilter)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)
                }
            }
            .padding(10)
        }
    }

    @ViewBuilder
    func fileMenu(_ f: EmpiricalFile) -> some View {
        ForEach(CodingStatus.allCases, id: \.self) { s in
            Button("Mark as \(s.label)") { model.setStatus(s, file: f.key) }
                .disabled(f.status == s)
        }
        Divider()
        Button("Remove from Project…") { model.removeFile(f.key) }
    }
}

struct FileRow: View {
    var file: EmpiricalFile
    var count: Int

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: file.status.symbol)
                .foregroundStyle(file.status.tint)
                .frame(width: 14)
                .padding(.top, 2)
                .help(file.status.label)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.displayTitle).lineLimit(2)
                HStack(spacing: 6) {
                    if !file.customID.isEmpty {
                        Text(file.customID).font(.caption.monospaced())
                    }
                    if !file.date.isEmpty {
                        Text(file.date).font(.caption).monospacedDigit()
                    }
                    Image(systemName: file.kind.symbol).font(.caption2)
                    if count > 0 {
                        Text("\(count)").font(.caption).monospacedDigit()
                            .help("\(count) selection\(count == 1 ? "" : "s") (all layers)")
                    }
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

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
        .onChange(of: model.sidebar) { old, _ in model.sidebarChanged(from: old) }
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
        case .files: return "Empirical Files"
        case .researchers: return "Researchers"
        case .interviewees: return "Interviewees"
        case .settings: return "Project Settings"
        case .codebooks: return "Codebooks"
        case .openCodes: return "Open Codes"
        case .axialCodes: return "Axial Codes"
        case .layers: return "Layers"
        case .file(let k): return model.project.files[k]?.displayTitle ?? ""
        case .code(let k): return model.project.code(k)?.name ?? ""
        case .codebook(let k): return model.project.codebooks[k]?.title ?? ""
        case .researcher(let k), .interviewee(let k): return model.personName(k) ?? ""
        case nil: return ""
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebar {
        case .files: FilesTable()
        case .researchers: ResearchersTable()
        case .interviewees: IntervieweesTable()
        case .settings: ProjectPage()
        case .codebooks: CodebooksTable()
        case .openCodes: CodesTable(kind: .open).id("open")
        case .axialCodes: CodesTable(kind: .axial).id("axial")
        case .layers: LayersPage()
        case .file(let k): DocumentPage(fileKey: k)
        case .code(let k): CodePage(codeKey: k)
        case .codebook(let k): CodebookPage(codebookKey: k).id(k)
        case .researcher(let k), .interviewee(let k): PersonPage(key: k).id(k)
        case nil:
            ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left",
                                   description: Text("Choose a page in the sidebar."))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                model.goBack()
            } label: {
                Label("Back", systemImage: "chevron.left")
            }
            .disabled(!model.canGoBack)
            .help("Back (⌃⌘←)")
            Button {
                model.goForward()
            } label: {
                Label("Forward", systemImage: "chevron.right")
            }
            .disabled(!model.canGoForward)
            .help("Forward (⌃⌘→)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            LayerMenu()
            if model.hasRealNameFiles {
                Toggle(isOn: Binding(get: { model.showRealNames }, set: { model.showRealNames = $0 })) {
                    Label("Real Names", systemImage: model.showRealNames ? "eye" : "eye.slash")
                }
                .help(model.showRealNames ? "Showing real names (from the mapping files). Click to show pseudonyms."
                                          : "Showing pseudonyms. Click to show real names from the mapping files.")
            }
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
        let all = model.project.files.count
        let coded = model.project.files.values.filter { $0.status == .coded }.count
        List(selection: $model.sidebar) {
            Section("Project") {
                Label("Empirical Files", systemImage: "doc.on.doc")
                    .badge(all)
                    .tag(SidebarItem.files)
                Label("Researchers", systemImage: "graduationcap")
                    .badge(model.project.researchers.count)
                    .tag(SidebarItem.researchers)
                Label("Interviewees", systemImage: "person.bubble")
                    .badge(model.project.interviewees.count)
                    .tag(SidebarItem.interviewees)
                Label("Project Settings", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
            Section("Analysis") {
                Label("Codebooks", systemImage: "text.book.closed")
                    .badge(model.project.codebooks.count)
                    .tag(SidebarItem.codebooks)
                Label("Open Codes", systemImage: "tag")
                    .badge(model.activeLayer?.codes.values.filter { $0.kind == .open }.count ?? 0)
                    .tag(SidebarItem.openCodes)
                Label("Axial Codes", systemImage: "tray.full")
                    .badge(model.activeLayer?.codes.values.filter { $0.kind == .axial }.count ?? 0)
                    .tag(SidebarItem.axialCodes)
                Label("Layers", systemImage: "square.3.layers.3d")
                    .badge(model.project.layers.count)
                    .tag(SidebarItem.layers)
            }
            Section("Working Area") {
                ForEach(model.workingArea, id: \.self) { item in
                    WorkingAreaRow(item: item)
                        .tag(item)
                        .contextMenu { workingAreaMenu(item) }
                }
                .onMove { from, to in model.moveWorkingArea(from: from, to: to) }
                if model.workingArea.isEmpty {
                    Text("Double-click a file, code, codebook or person in a table to work on it here.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if all > 0 {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: Double(coded), total: Double(max(all, 1)))
                        .progressViewStyle(.linear)
                        .tint(.green)
                    Text("\(coded) of \(all) files coded").font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(10)
            }
        }
    }

    @ViewBuilder
    func workingAreaMenu(_ item: SidebarItem) -> some View {
        Button("Open") { model.show(item) }
        if case .file(let k) = item, let f = model.project.files[k] {
            Divider()
            ForEach(CodingStatus.allCases, id: \.self) { s in
                Button("Mark as \(s.label)") { model.setStatus(s, file: k) }
                    .disabled(f.status == s)
            }
        }
        Divider()
        Button("Remove from Working Area") { model.removeFromWorkingArea(item) }
        Button("Remove Others from Working Area") { model.clearWorkingArea(except: item) }
            .disabled(model.workingArea.count < 2)
        Button("Clear Working Area") { model.clearWorkingArea() }
    }
}

/// A Working Area row: files as in the Empirical Files list; codes,
/// codebooks and people with their icon.
struct WorkingAreaRow: View {
    @Environment(AppModel.self) private var model
    var item: SidebarItem

    var body: some View {
        switch item {
        case .file(let k):
            if let f = model.project.files[k] {
                FileRow(file: f, count: model.index.selectionCount[k] ?? 0)
            }
        case .code(let k):
            if let c = model.project.code(k) {
                HStack(spacing: 6) {
                    Image(systemName: c.kind.symbol).foregroundStyle(c.color)
                    Text(c.name).lineLimit(1)
                    Spacer(minLength: 0)
                    if model.index.layerOf[k] != model.activeLayerKey {
                        Text(model.index.layerOf[k].flatMap { model.project.layer($0)?.name } ?? "")
                            .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                    }
                }
            }
        case .codebook(let k):
            Label(model.project.codebooks[k]?.title ?? "", systemImage: "text.book.closed")
        case .researcher(let k):
            Label(model.personName(k) ?? "", systemImage: "graduationcap")
        case .interviewee(let k):
            Label(model.personName(k) ?? "", systemImage: "person.bubble")
        default:
            EmptyView()
        }
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

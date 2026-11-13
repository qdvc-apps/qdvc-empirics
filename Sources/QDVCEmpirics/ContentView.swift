import AppKit
import EmpiricsCore
import SwiftUI

/// The main window, built the same way as QDVC Response Letter's: a
/// NavigationSplitView (sidebar and detail) with an inspector and a toolbar
/// of trailing items on the split view; the title, sheets and alerts on an
/// outer view. Every page starts with its scrolling content at the top (no
/// fixed header above it), and the notice banner is a top safe-area inset
/// over the page (docs/MAINTENANCE.md §Layout).
struct ContentView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        @Bindable var model = model
        Group {
            if model.isOpen {
                MainView()
            } else {
                ContentUnavailableView("No Project Open", systemImage: "folder",
                                       description: Text("Open a project from the File menu or the welcome window (⇧⌘1)."))
            }
        }
        .navigationTitle(model.isOpen ? model.project.settings.title : "QDVC Empirics")
        .navigationSubtitle(subtitle)
        .onAppear { model.undoManager = undoManager }
        .onChange(of: undoManager) { _, new in model.undoManager = new }
        .onChange(of: model.sidebar) { old, _ in model.sidebarChanged(from: old) }
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
        .task(id: model.notice?.id) {
            // Information goes away by itself; warnings stay until dismissed.
            guard let notice = model.notice, !notice.isWarning, notice.action == nil else { return }
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            if model.notice?.id == notice.id { model.notice = nil }
        }
    }

    private var subtitle: String {
        switch model.sidebar {
        case .files: return "Empirical Files"
        case .researchers: return "Researchers"
        case .interviewees: return "Interviewees"
        case .settings: return "Project Settings"
        case .protocols: return "Protocols"
        case .aprioriCodes: return "A Priori Codes"
        case .attributeSheets: return "Attribute Sheets"
        case .openCodes: return "Open Codes"
        case .theorisingCodes: return "Theorising Codes"
        case .layers: return "Layers"
        case .codingChart: return "Coding Chart"
        case .attributeSheetReport: return "Attribute Sheet Report"
        case .protocolReport: return "Protocol Report"
        case .file(let k), .code(let k), .studyProtocol(let k), .aprioriCode(let k), .attributeSheet(let k),
             .researcher(let k), .interviewee(let k):
            return model.itemLabel(k)
        case nil: return ""
        }
    }
}

struct MainView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 220, ideal: 280, max: 420)
        } detail: {
            DetailView()
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let notice = model.notice {
                        NoticeBanner(notice: notice) { model.notice = nil }
                    }
                }
        }
        .inspector(isPresented: $model.showInspector) {
            InspectorView()
                .inspectorColumnWidth(min: 280, ideal: 340, max: 520)
                .modifier(NoWritingTools())
        }
        .toolbar { MainToolbar(model: model) }
    }
}

struct DetailView: View {
    @Environment(AppModel.self) private var model

    /// The page is an overlay on a flexible base, so it can never be wider
    /// (or taller) than the detail column gives it: a page that asked for
    /// more would push the window's columns and cut off the sidebar on the
    /// left. Pages adapt to the width they get instead (the file page gives
    /// up its wide margins first), and anything left over is clipped.
    var body: some View {
        Color.clear
            .frame(minWidth: 300, maxWidth: .infinity, minHeight: 300, maxHeight: .infinity)
            .overlay { page }
            .clipped()
            .modifier(NoWritingTools())
    }

    @ViewBuilder
    private var page: some View {
        switch model.sidebar {
        case .files: FilesTable()
        case .researchers: ResearchersTable()
        case .interviewees: IntervieweesTable()
        case .settings: ProjectPage()
        case .protocols: ProtocolsTable()
        case .aprioriCodes: AprioriCodesTable()
        case .attributeSheets: AttributeSheetsTable()
        case .openCodes: CodesTable(kind: .open).id("open")
        case .theorisingCodes: CodesTable(kind: .theorising).id("theorising")
        case .layers: LayersPage()
        case .codingChart: CodingChartPage()
        case .attributeSheetReport: AttributeSheetReportPage()
        case .protocolReport: ProtocolReportPage()
        case .file(let k): DocumentPage(fileKey: k)
        case .code(let k): CodePage(codeKey: k)
        case .studyProtocol(let k): ProtocolPage(protocolKey: k).id(k)
        case .aprioriCode(let k): AprioriCodePage(codeKey: k).id(k)
        case .attributeSheet(let k): AttributeSheetPage(attributeSheetKey: k).id(k)
        case .researcher(let k), .interviewee(let k): PersonPage(key: k).id(k)
        case nil:
            ContentUnavailableView("Nothing Selected", systemImage: "sidebar.left",
                                   description: Text("Choose a page in the sidebar."))
        }
    }
}

/// The main window's toolbar: trailing items only, on the split view (as
/// in QDVC Response Letter). It holds the model directly. Back and Forward
/// are in the Go menu (⌃⌘← / ⌃⌘→).
struct MainToolbar: ToolbarContent {
    let model: AppModel

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            LayerMenu(model: model)
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
///
/// Takes the model directly rather than from the environment: toolbar items
/// are hosted apart from the window's views, and must not depend on it.
struct LayerMenu: View {
    let model: AppModel

    var body: some View {
        Menu {
            ForEach(LayerKind.allCases, id: \.self) { kind in
                Section("Code in (\(kind.label.lowercased()))") {
                    ForEach(model.project.layers.filter { $0.kind == kind }) { layer in
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
            } else if model.protocolPalette != nil, model.canCode {
                ProtocolPalette()
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
        // No .badge() on these rows: with badges, clicking a row left the
        // sidebar's rows laid out wrongly (pushed up under the window
        // buttons, not repaired by resizing). Counts are in each table's
        // footer instead.
        List(selection: $model.sidebar) {
            Section("Project") {
                Label("Empirical Files", systemImage: "doc.on.doc")
                    .tag(SidebarItem.files)
                Label("Researchers", systemImage: "graduationcap")
                    .tag(SidebarItem.researchers)
                Label("Layers", systemImage: "square.3.layers.3d")
                    .tag(SidebarItem.layers)
                Label("Project Settings", systemImage: "gearshape")
                    .tag(SidebarItem.settings)
            }
            Section("Deductive") {
                Label("Protocols", systemImage: "list.bullet.rectangle")
                    .tag(SidebarItem.protocols)
                Label("Interviewees", systemImage: "person.bubble")
                    .tag(SidebarItem.interviewees)
                Label("Attribute Sheets", systemImage: "text.book.closed")
                    .tag(SidebarItem.attributeSheets)
                Label("A Priori Codes", systemImage: "character.book.closed")
                    .tag(SidebarItem.aprioriCodes)
            }
            Section("Inductive") {
                Label("Open Codes", systemImage: "tag")
                    .tag(SidebarItem.openCodes)
                Label("Theorising Codes", systemImage: "tray.full")
                    .tag(SidebarItem.theorisingCodes)
            }
            Section("Reports") {
                Label("Coding Chart", systemImage: "point.3.connected.trianglepath.dotted")
                    .tag(SidebarItem.codingChart)
                Label("Attribute Sheet Report", systemImage: "tablecells")
                    .tag(SidebarItem.attributeSheetReport)
                Label("Protocol Report", systemImage: "list.bullet.rectangle.portrait")
                    .tag(SidebarItem.protocolReport)
            }
            // Every sidebar row is a single line of fixed height. A wrapping
            // hint row here ("Double-click a file…") was measured at the wrong
            // width when the selection changed, grew hundreds of points tall
            // and pushed the rows above it up under the window buttons. Rows
            // aren't draggable either (reorder from the context menu).
            Section("Working Area") {
                ForEach(model.workingArea, id: \.self) { item in
                    WorkingAreaRow(model: model, item: item)
                        .tag(item)
                        .contextMenu { workingAreaMenu(item, model) }
                }
            }
        }
        .listStyle(.sidebar)
        // Always present (never conditional), so the list's insets don't
        // change under it.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ProgressView(value: Double(coded), total: Double(max(all, 1)))
                    .progressViewStyle(.linear)
                    .tint(.green)
                Text(all == 0 ? "No files yet" : "\(coded) of \(all) files coded")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    .lineLimit(1)
            }
            .padding(10)
        }
    }

    /// (Takes the model directly: menu content is built apart from the row.)
    @ViewBuilder
    func workingAreaMenu(_ item: SidebarItem, _ model: AppModel) -> some View {
        Button("Open") { model.show(item) }
        if case .file(let k) = item, let f = model.project.files[k] {
            Divider()
            ForEach(CodingStatus.allCases, id: \.self) { s in
                Button("Mark as \(s.label)") { model.setStatus(s, file: k) }
                    .disabled(f.status == s)
            }
            Divider()
            Button("Update from New Version…") { model.updateFile(k) }
        }
        Divider()
        Button("Move Up") { model.moveInWorkingArea(item, by: -1) }
            .disabled(model.workingArea.first == item)
        Button("Move Down") { model.moveInWorkingArea(item, by: 1) }
            .disabled(model.workingArea.last == item)
        Divider()
        Button("Remove from Working Area") { model.removeFromWorkingArea(item) }
        Button("Remove Others from Working Area") { model.clearWorkingArea(except: item) }
            .disabled(model.workingArea.count < 2)
        Button("Clear Working Area") { model.clearWorkingArea() }
    }
}

/// A Working Area row: exactly one line, with the icon column, the title
/// and the working-identifier badge aligned the same way for every kind of
/// item (see ItemLine). Icons are all one neutral colour; only the badge
/// carries colour (a code's colour, a file's coding status).
struct WorkingAreaRow: View {
    let model: AppModel
    var item: SidebarItem

    var body: some View {
        if let key = item.key {
            ItemLine(model: model, key: key)
        }
    }
}

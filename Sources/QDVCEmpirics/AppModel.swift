import AppKit
import EmpiricsCore
import Observation
import PDFKit
import SwiftUI

/// What the sidebar shows in the detail area.
enum SidebarItem: Hashable {
    case codes
    case codebooks
    case people
    case layers
    case project
    case file(String)
}

enum InspectorTab: String, CaseIterable, Identifiable {
    case selection = "Selection"
    case code = "Code"
    case file = "File"

    var id: String { rawValue }
}

enum SheetKind: Identifiable {
    case newProject(URL?)
    case addFiles([String])
    case speakers(String)
    case response(ResponseID)
    case interrelation(code: String, key: String?)
    case consent(String)
    case moveToLayer(String)
    /// A new code; `parent` gets it as evidence, `child` becomes its evidence.
    case newCode(kind: CodeKind, parent: String?, child: String?)

    var id: String {
        switch self {
        case .newProject: return "newProject"
        case .addFiles: return "addFiles"
        case .speakers(let f): return "speakers-\(f)"
        case .response(let r): return "response-\(r.path)"
        case .interrelation(let c, let k): return "interrelation-\(c)-\(k ?? "new")"
        case .consent(let k): return "consent-\(k)"
        case .moveToLayer(let k): return "move-\(k)"
        case .newCode(let kind, let p, let c): return "newCode-\(kind.rawValue)-\(p ?? "")-\(c ?? "")"
        }
    }
}

/// A request for the document view to scroll to and flash some text.
struct RevealRequest: Equatable {
    var file: String
    var spans: [TextSpan]
    var revision: Int
}

enum ReadingFont: String, CaseIterable, Identifiable {
    case system, serif, mono

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System (San Francisco)"
        case .serif: return "Serif (New York)"
        case .mono: return "Monospaced (SF Mono)"
        }
    }

    func font(size: CGFloat) -> NSFont {
        switch self {
        case .system: return .systemFont(ofSize: size)
        case .mono: return .monospacedSystemFont(ofSize: size, weight: .regular)
        case .serif:
            let base = NSFont.systemFont(ofSize: size)
            if let d = base.fontDescriptor.withDesign(.serif), let f = NSFont(descriptor: d, size: size) { return f }
            return base
        }
    }
}

/// Full-texts as read from the full-texts folder, kept for the session.
/// Not observed: views refresh through `AppModel.documentsRevision`.
final class DocumentStore {
    /// Text of each page (one "page" for text files).
    var pages: [String: [String]] = [:]
    var pdfs: [String: PDFDocument] = [:]
    var fingerprints: [String: String] = [:]
    var errors: [String: String] = [:]
    /// Turns per file, with the speakers they were found for.
    var turns: [String: (speakers: Set<String>, turns: [Turn])] = [:]
    var candidates: [String: [SpeakerCandidate]] = [:]

    func clear() {
        pages = [:]
        pdfs = [:]
        fingerprints = [:]
        errors = [:]
        turns = [:]
        candidates = [:]
    }

    func forget(_ file: String) {
        pages[file] = nil
        pdfs[file] = nil
        fingerprints[file] = nil
        errors[file] = nil
        turns[file] = nil
        candidates[file] = nil
    }
}

@MainActor
@Observable
final class AppModel {
    // MARK: Project

    private(set) var workspaceURL: URL?
    private(set) var project = Project.new(title: "")
    private(set) var index = ProjectIndex()
    private(set) var fullTextsURL: URL?
    private(set) var recentWorkspaces: [DeviceStore.Recent] = []

    var isOpen: Bool { workspaceURL != nil }
    var fullTexts: FullTexts? { fullTextsURL.map { FullTexts(root: $0) } }

    // MARK: Interface state

    var sidebar: SidebarItem?
    var inspectorTab: InspectorTab = .file
    var showInspector = true
    var sheet: SheetKind?
    var notice: Notice?
    var errorMessage: String?
    var welcomeRequested = false
    var fileFilter = ""

    var showWelcomeAtLaunch: Bool = UserDefaults.standard.object(forKey: "showWelcome") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showWelcomeAtLaunch, forKey: "showWelcome") }
    }

    // MARK: Coding state

    private(set) var activeLayerKey = ""
    private(set) var hiddenLayers: Set<String> = []
    /// Show the Interlocutor layer (speaker names and header lines).
    var showSpeakers = true
    private(set) var currentResearcher: String?
    var focusedSelection: String?
    var focusedCode: String?
    /// The text selected in the document but not yet made a selection.
    var textSelection: [TextSpan] = []
    var textSelectionFile: String?
    var paletteVisible = false
    var reveal: RevealRequest?
    /// Bumped to ask the document view to clear its text selection.
    var clearTextSelectionRevision = 0
    /// Code keys for quick codes 1–9 in the active layer ("" = empty slot).
    private(set) var quickCodes: [String] = Array(repeating: "", count: 9)
    /// Selections that could not be found again after their file changed.
    private(set) var lostSelections: Set<String> = []
    /// Bumped whenever a document is (re)loaded.
    private(set) var documentsRevision = 0

    // MARK: Reading preferences (this Mac)

    var readingSize: Double = UserDefaults.standard.object(forKey: "readingSize") as? Double ?? 15 {
        didSet { UserDefaults.standard.set(readingSize, forKey: "readingSize") }
    }
    var readingFont: ReadingFont = ReadingFont(rawValue: UserDefaults.standard.string(forKey: "readingFont") ?? "") ?? .serif {
        didSet { UserDefaults.standard.set(readingFont.rawValue, forKey: "readingFont") }
    }
    var readingWidth: Double = UserDefaults.standard.object(forKey: "readingWidth") as? Double ?? 720 {
        didSet { UserDefaults.standard.set(readingWidth, forKey: "readingWidth") }
    }
    var lineSpacing: Double = UserDefaults.standard.object(forKey: "lineSpacing") as? Double ?? 1.35 {
        didSet { UserDefaults.standard.set(lineSpacing, forKey: "lineSpacing") }
    }
    var highlightStrength: Double = UserDefaults.standard.object(forKey: "highlightStrength") as? Double ?? 0.28 {
        didSet { UserDefaults.standard.set(highlightStrength, forKey: "highlightStrength") }
    }
    /// Show other visible layers' selections as underlines.
    var showOtherLayers: Bool = UserDefaults.standard.object(forKey: "showOtherLayers") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showOtherLayers, forKey: "showOtherLayers") }
    }
    var showStripes: Bool = UserDefaults.standard.object(forKey: "showStripes") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showStripes, forKey: "showStripes") }
    }

    // MARK: Internals

    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored let documents = DocumentStore()
    @ObservationIgnored private var dirty = Set<WorkspacePart>()
    @ObservationIgnored private var saveWork: DispatchWorkItem?
    @ObservationIgnored private var signature = ""
    @ObservationIgnored private var accessed: [URL] = []
    @ObservationIgnored private var verified = Set<String>()
    @ObservationIgnored var positions: [String: Int] = [:]
    @ObservationIgnored private var didStartUp = false
    @ObservationIgnored private var revealCounter = 0
    /// The document view (text or PDF), to give it the focus back.
    @ObservationIgnored weak var documentView: NSView?

    func focusDocument() {
        guard let view = documentView else { return }
        DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
    }

    init() {
        recentWorkspaces = DeviceStore.recents
    }

    // MARK: - Start up, open, close

    /// At launch: reopen the last project if the welcome window is off.
    func startUp() {
        guard !didStartUp else { return }
        didStartUp = true
        if !showWelcomeAtLaunch, let recent = recentWorkspaces.first {
            openRecent(recent)
        }
    }

    func refreshRecents() { recentWorkspaces = DeviceStore.recents }

    func openRecent(_ recent: DeviceStore.Recent) {
        // Close first: closing ends access to the old project's folders,
        // which must not include the one about to open.
        if isOpen { closeProject() }
        guard let url = DeviceStore.resolve(recent.bookmark) else {
            errorMessage = "“\((recent.path as NSString).lastPathComponent)” can't be found. It may have been moved or deleted."
            return
        }
        accessed.append(url)
        open(url)
    }

    func removeRecent(path: String) {
        DeviceStore.removeRecent(path: path)
        refreshRecents()
    }

    func clearRecent() {
        DeviceStore.setRecents([])
        refreshRecents()
    }

    /// Asks for a folder: a project opens; an empty folder offers to start one.
    func chooseWorkspace() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a QDVC Empirics project folder (its workspace), or an empty folder to start a new project."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if Workspace.isWorkspace(url) {
            open(url)
        } else if Workspace.isEmptyFolder(url) {
            sheet = .newProject(url)
        } else {
            errorMessage = "“\(url.lastPathComponent)” isn't a QDVC Empirics project (it has no project.yml), and it isn't empty. Choose a project folder, or an empty folder for a new project."
        }
    }

    func open(_ url: URL) {
        if isOpen { closeProject() }
        do {
            let loaded = try Workspace.load(url)
            workspaceURL = url
            project = loaded.project
            index = ProjectIndex(project)
            signature = Workspace.signature(url)
            DeviceStore.addRecent(url)
            refreshRecents()
            restoreDeviceState()
            var notes = loaded.notes
            if fullTextsURL == nil {
                notes.insert("This Mac doesn't know where this project's full-texts folder is yet.", at: 0)
            }
            if !notes.isEmpty {
                notice = Notice(text: notes.joined(separator: " "), isWarning: true,
                                action: fullTextsURL == nil ? NoticeAction(title: "Choose Full-Texts Folder…") { [weak self] in
                                    self?.chooseFullTextsFolder()
                                } : nil)
            }
            let last = DeviceStore.string("lastFile", project: project.settings.key)
            if let last, project.files[last] != nil {
                sidebar = .file(last)
            } else if let first = project.sortedFiles.first {
                sidebar = .file(first.key)
            } else {
                sidebar = .project
            }
            sidebarChanged()
        } catch {
            errorMessage = "Couldn't open “\(url.lastPathComponent)”.\n\n\(error.localizedDescription)"
        }
    }

    private func restoreDeviceState() {
        let key = project.settings.key
        if let url = DeviceStore.fullTexts(project: key) {
            fullTextsURL = url
            accessed.append(url)
        } else {
            fullTextsURL = nil
        }
        let r = DeviceStore.researcher(project: key)
        currentResearcher = r.flatMap { project.researcher($0) != nil ? $0 : nil }
        let active = DeviceStore.string("activeLayer", project: key)
        activeLayerKey = active.flatMap { project.layer($0) != nil ? $0 : nil } ?? project.layers.first?.key ?? ""
        hiddenLayers = Set(DeviceStore.strings("hiddenLayers", project: key))
        showSpeakers = DeviceStore.string("showSpeakers", project: key) != "no"
        positions = DeviceStore.positions(project: key)
        loadQuickCodes()
    }

    func closeProject() {
        flushSaves()
        savePositions()
        workspaceURL = nil
        project = Project.new(title: "")
        index = ProjectIndex()
        fullTextsURL = nil
        documents.clear()
        verified = []
        lostSelections = []
        sidebar = nil
        focusedSelection = nil
        focusedCode = nil
        textSelection = []
        textSelectionFile = nil
        paletteVisible = false
        notice = nil
        undoManager?.removeAllActions()
        for url in accessed { url.stopAccessingSecurityScopedResource() }
        accessed = []
    }

    func revealInFinder() {
        guard let url = workspaceURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - New project

    /// Creates a project in `folder`, remembering `fullTexts` for this Mac.
    func createProject(at folder: URL, title: String, fullTexts: URL, firstName: String, lastName: String) {
        if let problem = Self.nestingProblem(workspace: folder, fullTexts: fullTexts) {
            errorMessage = problem
            return
        }
        var p = Project.new(title: title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? folder.lastPathComponent : title)
        var me: String?
        if !(firstName + lastName).trimmingCharacters(in: .whitespaces).isEmpty {
            let key = p.newKey(Keys.researcher)
            p.researchers.append(Researcher(key: key, firstName: firstName.trimmingCharacters(in: .whitespaces),
                                            lastName: lastName.trimmingCharacters(in: .whitespaces)))
            p.layers[0].researcher = key
            me = key
        }
        do {
            try Workspace.create(at: folder, project: p)
        } catch {
            errorMessage = "Couldn't create the project.\n\n\(error.localizedDescription)"
            return
        }
        DeviceStore.setFullTexts(fullTexts, project: p.settings.key, title: p.settings.title)
        DeviceStore.setResearcher(me, project: p.settings.key, title: p.settings.title)
        open(folder)
    }

    /// The full-texts must never be inside the workspace (it is tracked in
    /// Git), and the workspace must not be inside the full-texts folder.
    static func nestingProblem(workspace: URL, fullTexts: URL) -> String? {
        let w = workspace.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let f = fullTexts.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        if w == f { return "The workspace and the full-texts folder must be different folders." }
        if f.count > w.count, Array(f.prefix(w.count)) == w {
            return "The full-texts folder is inside the workspace. The workspace is meant for Git, so full-texts (and consent forms) must be kept elsewhere."
        }
        if w.count > f.count, Array(w.prefix(f.count)) == f {
            return "The workspace is inside the full-texts folder. Keep them apart: the workspace goes into Git, the full-texts never do."
        }
        return nil
    }

    // MARK: - Full-texts folder

    func chooseFullTextsFolder() {
        guard isOpen else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use This Folder"
        panel.message = "Choose the full-texts folder for “\(project.settings.title)” on this Mac. QDVC Empirics only ever reads from it."
        if let current = fullTextsURL { panel.directoryURL = current }
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if let workspaceURL, let problem = Self.nestingProblem(workspace: workspaceURL, fullTexts: url) {
            errorMessage = problem
            return
        }
        DeviceStore.setFullTexts(url, project: project.settings.key, title: project.settings.title)
        fullTextsURL = url
        documents.clear()
        verified = []
        documentsRevision += 1
        let missing = project.files.values.filter { !FullTexts(root: url).exists($0.path) }.count
        notice = missing == 0
            ? Notice(text: "Full-texts folder set for this Mac.")
            : Notice(text: "Full-texts folder set, but \(missing) catalogued file\(missing == 1 ? " isn't" : "s aren't") in it.", isWarning: true)
        if case .file(let k) = sidebar { prepareDocument(k) }
    }

    func forgetFullTextsFolder() {
        DeviceStore.forgetFullTexts(project: project.settings.key)
        fullTextsURL = nil
        documents.clear()
        verified = []
        documentsRevision += 1
    }

    // MARK: - Changes, undo, saving

    /// Applies an undoable change. Rule errors are shown, not thrown.
    @discardableResult
    func perform(_ name: String, _ change: (inout Project) throws -> Void) -> Bool {
        var p = project
        do {
            try change(&p)
        } catch {
            showProblem(error)
            return false
        }
        commit(p, undo: name)
        return true
    }

    /// For typing (names, memos, descriptions): saved, but not on Edit ›
    /// Undo; text fields have their own undo while you type.
    func edit(_ change: (inout Project) -> Void) {
        var p = project
        change(&p)
        commit(p, undo: nil)
    }

    private func commit(_ new: Project, undo name: String?) {
        let old = project
        guard new != old else { return }
        project = new
        index = ProjectIndex(new)
        markDirty(Workspace.changedParts(from: old, to: new))
        validateState()
        if let name, let um = undoManager {
            um.registerUndo(withTarget: self) { target in
                MainActor.assumeIsolated { target.commit(old, undo: name) }
            }
            um.setActionName(name)
        }
    }

    func showProblem(_ error: Error) {
        let text = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        notice = Notice(text: text, isWarning: true)
        NSSound.beep()
    }

    /// Drops focus on things that no longer exist (after undo, delete, move).
    private func validateState() {
        if let s = focusedSelection, project.selection(s) == nil { focusedSelection = nil }
        if let c = focusedCode, project.code(c) == nil { focusedCode = nil }
        if project.layer(activeLayerKey) == nil { activeLayerKey = project.layers.first?.key ?? "" }
        if case .file(let k) = sidebar, project.files[k] == nil { sidebar = .project }
        if let r = currentResearcher, project.researcher(r) == nil { currentResearcher = nil }
    }

    private func markDirty(_ parts: Set<WorkspacePart>) {
        guard !parts.isEmpty else { return }
        dirty.formUnion(parts)
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flushSaves() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    /// Writes pending changes now (also on leaving the app and on quit).
    func flushSaves() {
        saveWork?.cancel()
        saveWork = nil
        guard let url = workspaceURL, !dirty.isEmpty else { return }
        let parts = dirty
        dirty = []
        do {
            try Workspace.save(project, parts: parts, to: url)
            signature = Workspace.signature(url)
        } catch {
            dirty.formUnion(parts)
            errorMessage = "Couldn't save changes to the workspace.\n\n\(error.localizedDescription)"
        }
    }

    /// Reloads if files in the workspace were changed by Git or an editor.
    func checkForOutsideChanges(force: Bool = false) {
        guard let url = workspaceURL else { return }
        flushSaves()
        let now = Workspace.signature(url)
        guard force || now != signature else { return }
        do {
            let loaded = try Workspace.load(url)
            let changed = loaded.project != project
            project = loaded.project
            index = ProjectIndex(project)
            signature = now
            if changed {
                undoManager?.removeAllActions()
                validateState()
                loadQuickCodes()
                notice = Notice(text: "Reloaded the workspace: its files were changed outside the app." +
                                (loaded.notes.isEmpty ? "" : " " + loaded.notes.joined(separator: " ")),
                                isWarning: !loaded.notes.isEmpty)
            }
        } catch {
            errorMessage = "The workspace was changed outside the app and can't be read now.\n\n\(error.localizedDescription)\n\nFix the file, then choose View › Reload from Disk."
        }
    }

    // MARK: - Device state

    func setActiveLayer(_ key: String) {
        guard project.layer(key) != nil else { return }
        activeLayerKey = key
        hiddenLayers.remove(key)
        DeviceStore.setString(key, "activeLayer", project: project.settings.key)
        DeviceStore.setStrings(Array(hiddenLayers), "hiddenLayers", project: project.settings.key)
        focusedSelection = nil
        focusedCode = nil
        loadQuickCodes()
    }

    func setLayerVisible(_ key: String, _ visible: Bool) {
        if visible { hiddenLayers.remove(key) } else if key != activeLayerKey { hiddenLayers.insert(key) }
        DeviceStore.setStrings(Array(hiddenLayers), "hiddenLayers", project: project.settings.key)
    }

    func isLayerVisible(_ key: String) -> Bool { key == activeLayerKey || !hiddenLayers.contains(key) }

    func setShowSpeakers(_ show: Bool) {
        showSpeakers = show
        DeviceStore.setString(show ? "yes" : "no", "showSpeakers", project: project.settings.key)
    }

    func setCurrentResearcher(_ key: String?) {
        currentResearcher = key
        DeviceStore.setResearcher(key, project: project.settings.key, title: project.settings.title)
    }

    var activeLayer: CodingLayer? { project.layer(activeLayerKey) }

    // MARK: Quick codes

    private func loadQuickCodes() {
        var slots = DeviceStore.strings("quick.\(activeLayerKey)", project: project.settings.key)
        slots = (slots + Array(repeating: "", count: 9)).prefix(9).map { project.layer(activeLayerKey)?.codes[$0] != nil ? $0 : "" }
        quickCodes = Array(slots)
    }

    private func saveQuickCodes() {
        DeviceStore.setStrings(quickCodes, "quick.\(activeLayerKey)", project: project.settings.key)
    }

    /// The quick-code number (1–9) of a code, if it has one.
    func quickSlot(of code: String) -> Int? {
        quickCodes.firstIndex(of: code).map { $0 + 1 }
    }

    func assignQuickCode(_ code: String?, slot: Int) {
        guard (1...9).contains(slot) else { return }
        if let code, let old = quickCodes.firstIndex(of: code) { quickCodes[old] = "" }
        quickCodes[slot - 1] = code ?? ""
        saveQuickCodes()
    }

    /// A code just used takes the first empty slot, so the first nine codes
    /// used get 1–9 and keep them (numbers never shift under your fingers).
    func noteUsed(_ code: String) {
        guard project.code(code)?.kind == .open, !quickCodes.contains(code),
              let empty = quickCodes.firstIndex(of: "") else { return }
        quickCodes[empty] = code
        saveQuickCodes()
    }

    // MARK: Reading positions

    func rememberPosition(file: String, _ value: Int) {
        positions[file] = value
    }

    func savePositions() {
        guard isOpen else { return }
        DeviceStore.setPositions(positions, project: project.settings.key)
    }

    // MARK: - Navigation

    var openFileKey: String? {
        if case .file(let k) = sidebar { return k }
        return nil
    }

    /// Called when the sidebar selection changes.
    func sidebarChanged() {
        textSelection = []
        textSelectionFile = nil
        paletteVisible = false
        savePositions()
        if case .file(let k) = sidebar {
            DeviceStore.setString(k, "lastFile", project: project.settings.key)
            if let s = focusedSelection, index.fileOf[s] != k { focusedSelection = nil }
            if focusedSelection == nil, inspectorTab == .selection { inspectorTab = .file }
            prepareDocument(k)
        }
    }

    /// Opens a selection's file, focuses the selection and scrolls to it.
    func showSelection(_ key: String) {
        guard let s = project.selection(key) else { return }
        if let layer = index.layerOf[key], layer != activeLayerKey { setActiveLayer(layer) }
        if sidebar != .file(s.fileKey) {
            sidebar = .file(s.fileKey)
            sidebarChanged()
        }
        focusedSelection = key
        inspectorTab = .selection
        revealCounter += 1
        reveal = RevealRequest(file: s.fileKey, spans: s.spans, revision: revealCounter)
    }

    /// Focuses a selection without scrolling (it is already in view).
    func focusSelection(_ key: String) {
        focusedSelection = key
        inspectorTab = .selection
    }

    /// The document view has scrolled to the reveal request.
    func consumeReveal(_ revision: Int) {
        DispatchQueue.main.async { [weak self] in
            if self?.reveal?.revision == revision { self?.reveal = nil }
        }
    }

    func showCode(_ key: String) {
        guard project.code(key) != nil else { return }
        if let layer = index.layerOf[key], layer != activeLayerKey { setActiveLayer(layer) }
        focusedCode = key
        inspectorTab = .code
        showInspector = true
    }

    /// Previous or next file in the sidebar's order.
    func stepFile(_ step: Int) {
        let files = visibleFiles
        guard !files.isEmpty else { return }
        let current = openFileKey.flatMap { k in files.firstIndex { $0.key == k } }
        let next = current.map { max(0, min(files.count - 1, $0 + step)) } ?? 0
        sidebar = .file(files[next].key)
        sidebarChanged()
    }

    /// Files in the sidebar, after the filter.
    var visibleFiles: [EmpiricalFile] {
        let q = fileFilter.trimmingCharacters(in: .whitespaces)
        let all = project.sortedFiles
        guard !q.isEmpty else { return all }
        return all.filter { f in
            [f.displayTitle, f.customID, f.path, f.date].contains { $0.localizedCaseInsensitiveContains(q) }
        }
    }

    // MARK: - Documents

    enum DocumentState {
        case noFullTexts
        case missing(String)
        case failed(String)
        case text(String)
        case pdf(PDFDocument)
    }

    /// The loaded document for a file (load with `prepareDocument` first).
    func documentState(_ key: String) -> DocumentState {
        guard let file = project.files[key] else { return .failed("This file is no longer in the project.") }
        guard let ft = fullTexts else { return .noFullTexts }
        if let e = documents.errors[key] { return .failed(e) }
        if file.kind == .pdf, let pdf = documents.pdfs[key] { return .pdf(pdf) }
        if file.kind != .pdf, let text = documents.pages[key]?.first { return .text(text) }
        if !ft.exists(file.path) { return .missing(file.path) }
        return .failed("Loading…")
    }

    /// Text of each page (one for text files), loading the file if needed.
    /// Doesn't touch the project, so it is safe while views are drawn.
    func pages(_ key: String) -> [String]? {
        if let p = documents.pages[key] { return p }
        guard let file = project.files[key], let ft = fullTexts, ft.exists(file.path) else { return nil }
        do {
            let data = try ft.data(file.path)
            documents.fingerprints[key] = "sha256:" + SHA256.hex(data)
            if file.kind == .pdf {
                guard let doc = PDFDocument(data: data) else {
                    documents.errors[key] = "“\(file.fileName)” can't be read as a PDF."
                    return nil
                }
                documents.pdfs[key] = doc
                documents.pages[key] = (0..<doc.pageCount).map { doc.page(at: $0)?.string ?? "" }
            } else {
                documents.pages[key] = [TextNormaliser.text(from: data)]
            }
            return documents.pages[key]
        } catch {
            documents.errors[key] = "Couldn't read “\(file.path)” from the full-texts folder: \(error.localizedDescription)"
            return nil
        }
    }

    /// Loads a file for coding, and checks it against its fingerprint: if
    /// it changed since it was coded, selections are found again by their
    /// quotes.
    func prepareDocument(_ key: String) {
        guard fullTexts != nil, let file = project.files[key] else { return }
        let pages = self.pages(key)
        documentsRevision += 1
        guard let pages, !verified.contains(key), let fp = documents.fingerprints[key] else { return }
        verified.insert(key)
        if file.fingerprint.isEmpty {
            edit { $0.files[key]?.fingerprint = fp }
            return
        }
        guard file.fingerprint != fp else { return }
        var p = project
        let result = Anchoring.reanchor(&p, file: key, pages: pages)
        p.files[key]?.fingerprint = fp
        commit(p, undo: nil)
        lostSelections.formUnion(result.lost)
        var text = "“\(file.displayTitle)” has changed since it was last coded."
        if result.moved > 0 { text += " \(result.moved) selection\(result.moved == 1 ? " was" : "s were") found again and moved with the text." }
        if !result.lost.isEmpty {
            text += project.settings.storeQuotes
                ? " \(result.lost.count) selection\(result.lost.count == 1 ? "" : "s") could not be found; \(result.lost.count == 1 ? "it is" : "they are") marked with a warning in the inspector."
                : " Quotes aren't stored in this project, so \(result.lost.count) selection\(result.lost.count == 1 ? "" : "s") may now point at the wrong text."
        }
        if result.moved == 0 && result.lost.isEmpty { text += " All selections are still in place." }
        notice = Notice(text: text, isWarning: !result.lost.isEmpty)
    }

    func isLost(_ selection: String) -> Bool { lostSelections.contains(selection) }

    /// The text of a selection: its stored quote, or from the full-text.
    func quoteText(_ s: CodeSelection) -> String? {
        if !s.quote.isEmpty { return s.quote }
        guard let pages = pages(s.fileKey) else { return nil }
        let q = TextNormaliser.quote(s.spans, pages: pages)
        return q.isEmpty ? nil : q
    }

    // MARK: Interlocutors

    /// Header-like labels found in a text file.
    func speakerCandidates(_ file: String) -> [SpeakerCandidate] {
        if let c = documents.candidates[file] { return c }
        guard project.files[file]?.kind.isText == true, let text = pages(file)?.first else { return [] }
        let c = TurnDetector.candidates(in: text)
        documents.candidates[file] = c
        return c
    }

    /// The turns in a text file, for its speakers.
    func turns(_ file: String) -> [Turn] {
        guard project.settings.interlocutorLayer, project.files[file]?.kind.isText == true,
              let text = pages(file)?.first else { return [] }
        let map = project.speakerMaps[file] ?? SpeakerMap(fileKey: file)
        let speakers = map.speakers(candidates: speakerCandidates(file))
        if let cached = documents.turns[file], cached.speakers == speakers { return cached.turns }
        let t = TurnDetector.turns(in: text, speakers: speakers)
        documents.turns[file] = (speakers, t)
        return t
    }

    /// The person for a turn's speaker label in a file, if assigned (or
    /// suggested by name).
    func person(forSpeaker label: String, in file: String) -> String? {
        if let p = project.speakerMaps[file]?.person(for: label) { return p }
        return TurnDetector.suggest(label, researchers: project.researchers, interviewees: project.interviewees)
    }

    func speakerName(_ label: String, in file: String) -> String {
        person(forSpeaker: label, in: file).flatMap { project.personName($0) } ?? label
    }

    /// Researchers in blue, interviewees in green, unknown speakers grey.
    func speakerColor(_ label: String, in file: String) -> NSColor {
        guard let p = person(forSpeaker: label, in: file) else { return .secondaryLabelColor }
        return project.researcher(p) != nil ? .systemBlue : .systemGreen
    }

    // MARK: - Response sheets

    /// The response sheet this Mac's researcher fills in, or nil if the
    /// project lists researchers and none is chosen here yet.
    func responseID(codebook: String, target: String) -> ResponseID? {
        if project.researchers.isEmpty { return ResponseID(codebook: codebook, target: target) }
        guard let r = currentResearcher else { return nil }
        return ResponseID(codebook: codebook, target: target, researcher: r)
    }

    func openResponseSheet(codebook: String, target: String) {
        guard let id = responseID(codebook: codebook, target: target) else {
            notice = Notice(text: "Choose who you are on this Mac first (People › This Mac's Researcher), so your answers are filed under your name.",
                            isWarning: true, action: NoticeAction(title: "Go to People") { [weak self] in self?.sidebar = .people })
            return
        }
        sheet = .response(id)
    }

    /// Every response sheet for a codebook and target (all researchers).
    func sheets(codebook: String, target: String) -> [ResponseSheet] {
        project.responses.values.filter { $0.id.codebook == codebook && $0.id.target == target }.sorted { $0.id < $1.id }
    }
}

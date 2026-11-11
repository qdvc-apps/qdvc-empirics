import AppKit
import EmpiricsCore
import Observation
import PDFKit
import SwiftUI
import UniformTypeIdentifiers

/// What the sidebar shows in the detail area: a list page, or one item's
/// page (an empirical file, code, codebook or person).
enum SidebarItem: Hashable {
    // Project
    case files
    case researchers
    case interviewees
    case settings
    // Analysis
    case codebooks
    case openCodes
    case axialCodes
    case layers
    // Reporting
    case codingChart
    case codebookReport
    // Pages of single items (in the Working Area)
    case file(String)
    case code(String)
    case codebook(String)
    case researcher(String)
    case interviewee(String)

    /// The item's key, for the pages of single items.
    var key: String? {
        switch self {
        case .file(let k), .code(let k), .codebook(let k), .researcher(let k), .interviewee(let k): return k
        default: return nil
        }
    }

    /// As stored on this Mac ("files", "file:f-1a2b3c4d").
    var encoded: String {
        switch self {
        case .files: return "files"
        case .researchers: return "researchers"
        case .interviewees: return "interviewees"
        case .settings: return "settings"
        case .codebooks: return "codebooks"
        case .openCodes: return "openCodes"
        case .axialCodes: return "axialCodes"
        case .layers: return "layers"
        case .codingChart: return "codingChart"
        case .codebookReport: return "codebookReport"
        case .file(let k): return "file:" + k
        case .code(let k): return "code:" + k
        case .codebook(let k): return "codebook:" + k
        case .researcher(let k): return "researcher:" + k
        case .interviewee(let k): return "interviewee:" + k
        }
    }

    init?(encoded: String) {
        let parts = encoded.split(separator: ":", maxSplits: 1).map(String.init)
        switch (parts.first ?? "", parts.count > 1 ? parts[1] : "") {
        case ("files", _): self = .files
        case ("researchers", _): self = .researchers
        case ("interviewees", _): self = .interviewees
        case ("settings", _): self = .settings
        case ("codebooks", _): self = .codebooks
        case ("openCodes", _): self = .openCodes
        case ("axialCodes", _): self = .axialCodes
        case ("layers", _): self = .layers
        case ("codingChart", _): self = .codingChart
        case ("codebookReport", _): self = .codebookReport
        case ("file", let k) where !k.isEmpty: self = .file(k)
        case ("code", let k) where !k.isEmpty: self = .code(k)
        case ("codebook", let k) where !k.isEmpty: self = .codebook(k)
        case ("researcher", let k) where !k.isEmpty: self = .researcher(k)
        case ("interviewee", let k) where !k.isEmpty: self = .interviewee(k)
        default: return nil
        }
    }
}

/// The inspector's tabs on an empirical file's page.
enum InspectorTab: String, CaseIterable, Identifiable {
    case selection = "Selection"
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
    /// The row selected in the table of the current list page (also the
    /// item selected in the Coding Chart and the Codebook Report).
    var tableSelection: String?
    /// The codebook shown in the Codebook Report.
    var reportCodebook: String?
    /// Items being worked on, in the sidebar's Working Area (this Mac).
    private(set) var workingArea: [SidebarItem] = []
    @ObservationIgnored private var backStack: [SidebarItem] = []
    @ObservationIgnored private var forwardStack: [SidebarItem] = []
    @ObservationIgnored private var navigatingHistory = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// Real names by person key, from the mapping files (never saved).
    private(set) var realNames: [String: String] = [:]
    private(set) var realNamesProblem: String?
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
    var lostSelections: Set<String> = []
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
    /// Show open code names beside the coding stripes, when the window is
    /// wide enough for them.
    var showCodeNames: Bool = UserDefaults.standard.object(forKey: "showCodeNames") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showCodeNames, forKey: "showCodeNames") }
    }
    /// Show real names (from the mapping files) instead of pseudonyms. Off
    /// at every launch, so a shared screen never shows them by surprise.
    var showRealNames = false

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
            let last = DeviceStore.string("lastItem", project: project.settings.key).flatMap(SidebarItem.init(encoded:))
            if let last, exists(last) {
                sidebar = last
            } else {
                sidebar = .files
            }
            backStack = []
            forwardStack = []
            updateHistoryFlags()
            sidebarChanged(from: nil)
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
        workingArea = DeviceStore.strings("workingArea", project: key).compactMap(SidebarItem.init(encoded:)).filter(exists)
        loadQuickCodes()
        loadRealNames()
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
        tableSelection = nil
        reportCodebook = nil
        workingArea = []
        backStack = []
        forwardStack = []
        updateHistoryFlags()
        realNames = [:]
        realNamesProblem = nil
        showRealNames = false
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
        loadRealNames()
    }

    func forgetFullTextsFolder() {
        DeviceStore.forgetFullTexts(project: project.settings.key)
        fullTextsURL = nil
        documents.clear()
        verified = []
        documentsRevision += 1
        loadRealNames()
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
        if let t = tableSelection, !keyExists(t) { tableSelection = nil }
        if let c = reportCodebook, project.codebooks[c] == nil { reportCodebook = nil }
        if project.layer(activeLayerKey) == nil { activeLayerKey = project.layers.first?.key ?? "" }
        if let item = sidebar, !exists(item) { sidebar = listPage(for: item) }
        if let r = currentResearcher, project.researcher(r) == nil { currentResearcher = nil }
        let kept = workingArea.filter(exists)
        if kept != workingArea {
            workingArea = kept
            saveWorkingArea()
        }
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
                loadRealNames()
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

    /// Whether a sidebar item still exists (its file, code… wasn't deleted).
    func exists(_ item: SidebarItem) -> Bool {
        switch item {
        case .file(let k): return project.files[k] != nil
        case .code(let k): return project.code(k) != nil
        case .codebook(let k): return project.codebooks[k] != nil
        case .researcher(let k): return project.researcher(k) != nil
        case .interviewee(let k): return project.interviewee(k) != nil
        default: return true
        }
    }

    /// The working identifier of a file, codebook, code or person ("EF 3",
    /// "OC 12"…): alphabetical, so it changes as items come and go.
    func wid(_ key: String) -> String { index.workingID[key] ?? "" }

    func keyExists(_ key: String) -> Bool { item(forKey: key).map(exists) ?? false }

    /// The page of a file, code, codebook or person, by key.
    func item(forKey key: String) -> SidebarItem? {
        if project.files[key] != nil { return .file(key) }
        if project.code(key) != nil { return .code(key) }
        if project.codebooks[key] != nil { return .codebook(key) }
        if project.researcher(key) != nil { return .researcher(key) }
        if project.interviewee(key) != nil { return .interviewee(key) }
        return nil
    }

    /// The list page an item's page belongs to.
    func listPage(for item: SidebarItem) -> SidebarItem {
        switch item {
        case .file: return .files
        case .code(let k): return project.code(k)?.kind == .axial ? .axialCodes : .openCodes
        case .codebook: return .codebooks
        case .researcher: return .researchers
        case .interviewee: return .interviewees
        default: return item
        }
    }

    /// Opens an item's page, putting it in the Working Area.
    func show(_ item: SidebarItem) {
        guard exists(item) else { return }
        if item.key != nil { addToWorkingArea(item) }
        sidebar = item
    }

    /// Opens the page of a file, code, codebook or person by key.
    func openKey(_ key: String) {
        if let item = item(forKey: key) { show(item) }
    }

    func addToWorkingArea(_ item: SidebarItem) {
        guard item.key != nil, !workingArea.contains(item) else { return }
        workingArea.append(item)
        saveWorkingArea()
    }

    func removeFromWorkingArea(_ item: SidebarItem) {
        workingArea.removeAll { $0 == item }
        saveWorkingArea()
        if sidebar == item { sidebar = listPage(for: item) }
    }

    func clearWorkingArea(except keep: SidebarItem? = nil) {
        workingArea = workingArea.filter { $0 == keep }
        saveWorkingArea()
        if let s = sidebar, s.key != nil, s != keep { sidebar = listPage(for: s) }
    }

    func moveInWorkingArea(_ item: SidebarItem, by step: Int) {
        guard let i = workingArea.firstIndex(of: item) else { return }
        let j = i + step
        guard workingArea.indices.contains(j) else { return }
        workingArea.swapAt(i, j)
        saveWorkingArea()
    }

    private func saveWorkingArea() {
        guard isOpen else { return }
        DeviceStore.setStrings(workingArea.map(\.encoded), "workingArea", project: project.settings.key)
    }

    /// Called when the sidebar selection changes (with the previous one).
    func sidebarChanged(from old: SidebarItem?) {
        textSelection = []
        textSelectionFile = nil
        paletteVisible = false
        savePositions()
        if let old, old != sidebar, !navigatingHistory {
            backStack.append(old)
            if backStack.count > 50 { backStack.removeFirst() }
            forwardStack = []
        }
        navigatingHistory = false
        updateHistoryFlags()
        if sidebar.map({ $0.key == nil }) ?? false { tableSelection = nil }
        if let item = sidebar {
            DeviceStore.setString(item.encoded, "lastItem", project: project.settings.key)
        }
        if case .file(let k) = sidebar {
            if let s = focusedSelection, index.fileOf[s] != k { focusedSelection = nil }
            if focusedSelection == nil, inspectorTab == .selection { inspectorTab = .file }
            prepareDocument(k)
        }
    }

    func goBack() {
        while let item = backStack.popLast() {
            guard exists(item), item != sidebar else { continue }
            if let s = sidebar { forwardStack.append(s) }
            navigatingHistory = true
            sidebar = item
            break
        }
        updateHistoryFlags()
    }

    func goForward() {
        while let item = forwardStack.popLast() {
            guard exists(item), item != sidebar else { continue }
            if let s = sidebar { backStack.append(s) }
            navigatingHistory = true
            sidebar = item
            break
        }
        updateHistoryFlags()
    }

    private func updateHistoryFlags() {
        canGoBack = !backStack.isEmpty
        canGoForward = !forwardStack.isEmpty
    }

    /// Opens a selection's file, focuses the selection and scrolls to it.
    func showSelection(_ key: String) {
        guard let s = project.selection(key) else { return }
        if let layer = index.layerOf[key], layer != activeLayerKey { setActiveLayer(layer) }
        if sidebar != .file(s.fileKey) { show(.file(s.fileKey)) }
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

    /// Opens a code's page (switching to its layer).
    func showCode(_ key: String) {
        guard project.code(key) != nil else { return }
        if let layer = index.layerOf[key], layer != activeLayerKey { setActiveLayer(layer) }
        show(.code(key))
    }

    /// Previous or next file, in the Empirical Files order. The file you
    /// were on gives its place in the Working Area to the next one.
    func stepFile(_ step: Int) {
        let files = visibleFiles
        guard !files.isEmpty else { return }
        let current = openFileKey.flatMap { k in files.firstIndex { $0.key == k } }
        let next = current.map { max(0, min(files.count - 1, $0 + step)) } ?? 0
        moveOn(to: files[next].key)
    }

    /// Opens `file` in place of the open file in the Working Area.
    func moveOn(to file: String) {
        let target = SidebarItem.file(file)
        if let k = openFileKey, k != file, let i = workingArea.firstIndex(of: .file(k)), !workingArea.contains(target) {
            workingArea[i] = target
            saveWorkingArea()
        }
        show(target)
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
        person(forSpeaker: label, in: file).flatMap { personName($0) } ?? label
    }

    /// Greyscale, so speakers never compete with code colours: interviewees
    /// in the text colour, researchers (interviewers) in a lighter grey that
    /// is still easy to read, unknown speakers lighter again.
    func speakerColor(_ label: String, in file: String) -> NSColor {
        guard let p = person(forSpeaker: label, in: file) else { return .tertiaryLabelColor }
        return project.researcher(p) != nil ? .secondaryLabelColor : .labelColor
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
            notice = Notice(text: "Choose who you are on this Mac first (Researchers › This Mac's Researcher), so your answers are filed under your name.",
                            isWarning: true, action: NoticeAction(title: "Go to Researchers") { [weak self] in self?.sidebar = .researchers })
            return
        }
        sheet = .response(id)
    }

    /// Every response sheet for a codebook and target (all researchers).
    func sheets(codebook: String, target: String) -> [ResponseSheet] {
        project.responses.values.filter { $0.id.codebook == codebook && $0.id.target == target }.sorted { $0.id < $1.id }
    }

    // MARK: - Names

    /// A researcher's or interviewee's name as shown: the pseudonym, or the
    /// real name while Show Real Names is on (if the mapping files have one).
    func personName(_ key: String) -> String? {
        if showRealNames, let real = realNames[key] { return real }
        guard let name = project.personName(key) else { return nil }
        return name.isEmpty ? "Unnamed" : name
    }

    var hasRealNameFiles: Bool {
        !project.settings.researcherNamesFile.isEmpty || !project.settings.intervieweeNamesFile.isEmpty
    }

    /// Reads the real-name mapping files from the full-texts folder (only
    /// ever read; the names stay in memory).
    func loadRealNames() {
        realNames = [:]
        realNamesProblem = nil
        guard hasRealNameFiles else { return }
        guard let ft = fullTexts else {
            realNamesProblem = "The full-texts folder isn't set on this Mac, so real names can't be read."
            return
        }
        let people: [(key: String, pseudonym: String)] = project.researchers.map { ($0.key, $0.fullName) }
            + project.interviewees.map { ($0.key, $0.fullName) }
        var problems: [String] = []
        for path in [project.settings.researcherNamesFile, project.settings.intervieweeNamesFile] where !path.isEmpty {
            do {
                let text = TextNormaliser.text(from: try ft.data(path))
                realNames.merge(try RealNames.read(text, people: people)) { a, _ in a }
            } catch {
                problems.append("\(path): \((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)")
            }
        }
        if !problems.isEmpty { realNamesProblem = problems.joined(separator: "\n") }
    }

    enum PeopleKind { case researchers, interviewees }

    /// Chooses a mapping file (a CSV inside the full-texts folder).
    func chooseNamesFile(_ kind: PeopleKind) {
        guard let ft = fullTexts else {
            chooseFullTextsFolder()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.directoryURL = ft.root
        panel.prompt = "Use This File"
        panel.message = "Choose the CSV that maps \(kind == .researchers ? "researchers'" : "interviewees'") keys to real names. It must be inside the full-texts folder; it is only ever read."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let rel = ft.relativePath(of: url) else {
            errorMessage = "Mapping files must be inside the full-texts folder, so real names never reach the workspace or Git."
            return
        }
        setNamesFile(kind, rel)
    }

    func setNamesFile(_ kind: PeopleKind, _ path: String) {
        perform(path.isEmpty ? "Clear Mapping File" : "Set Mapping File") { p in
            if kind == .researchers { p.settings.researcherNamesFile = path } else { p.settings.intervieweeNamesFile = path }
        }
        loadRealNames()
    }

    /// Writes a mapping file to fill in (keys and pseudonyms, real-name
    /// columns empty) where the researcher chooses, by default in the
    /// full-texts folder. Never overwrites an existing file.
    func saveNamesTemplate(_ kind: PeopleKind) {
        let people: [(key: String, pseudonym: String)] = kind == .researchers
            ? project.researchers.map { ($0.key, $0.fullName) }
            : project.interviewees.map { ($0.key, $0.fullName) }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = kind == .researchers ? "researchers-real-names.csv" : "interviewees-real-names.csv"
        if let ft = fullTexts { panel.directoryURL = ft.root }
        panel.message = "Save a mapping file to fill in with real names (in a spreadsheet). Keep it in the full-texts folder, never in the workspace."
        panel.prompt = "Save Template"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if FileManager.default.fileExists(atPath: url.path) {
            errorMessage = "“\(url.lastPathComponent)” already exists. QDVC Empirics never overwrites files there; choose another name."
            return
        }
        if let workspaceURL, url.standardizedFileURL.path.hasPrefix(workspaceURL.standardizedFileURL.path + "/") {
            errorMessage = "Real names must not go into the workspace (it is tracked in Git). Save the template in the full-texts folder."
            return
        }
        do {
            try Data(RealNames.template(people: people).utf8).write(to: url, options: .withoutOverwriting)
        } catch {
            errorMessage = "Couldn't save the template.\n\n\(error.localizedDescription)"
            return
        }
        if let ft = fullTexts, let rel = ft.relativePath(of: url) {
            setNamesFile(kind, rel)
            notice = Notice(text: "Template saved as \(rel). Fill in the real names in a spreadsheet, then choose View › Reload Real Names.")
        } else {
            notice = Notice(text: "Template saved. Move it into the full-texts folder, then choose it in Project Settings.", isWarning: true)
        }
    }
}

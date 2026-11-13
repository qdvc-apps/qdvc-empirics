import AppKit
import EmpiricsCore
import SwiftUI

@main
struct EmpiricsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var model = AppModel()

    init() {
        // Don't reopen windows from the last session: the welcome window
        // (the first scene) decides what opens at launch.
        UserDefaults.standard.register(defaults: ["NSQuitAlwaysKeepsWindows": false])
    }

    var body: some Scene {
        Window("Welcome to QDVC Empirics", id: WelcomeWindow.id) {
            WelcomeWindow()
                .environment(model)
                .onAppear { appDelegate.model = model }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)

        // One window, one project at a time.
        Window("QDVC Empirics", id: MainWindowID.main) {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .onAppear { appDelegate.model = model }
        }
        .defaultSize(width: 1440, height: 900)
        .commands {
            EmpiricsCommands(model: model)
            InspectorCommands()
            TextEditingCommands()
        }

        Settings {
            SettingsView()
                .environment(model)
                .modifier(NoWritingTools())
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`) rather than
        // from the .app bundle, so the app gets a Dock icon and menu bar.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // No Services menu: nothing from a full-text is handed to other apps.
        NSApp.servicesMenu = nil
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model?.checkForOutsideChanges()
    }

    func applicationDidResignActive(_ notification: Notification) {
        model?.flushSaves()
        model?.savePositions()
    }

    func applicationWillTerminate(_ notification: Notification) {
        model?.flushSaves()
        model?.savePositions()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

struct EmpiricsCommands: Commands {
    let model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var inFile: Bool { model.openFileKey != nil }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            // ⌘N makes an item of the kind the current list page shows
            // (a file, researcher, interviewee, attribute sheet, open or theorising code).
            Button(model.newItemTitle ?? "New Item") { model.newItem() }
                .keyboardShortcut("n")
                .disabled(model.newItemTitle == nil)
            Button("New Project…") { model.sheet = .newProject(nil) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("Open Project…") { model.chooseWorkspace() }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(model.recentWorkspaces, id: \.path) { recent in
                    Button((recent.path as NSString).lastPathComponent) { model.openRecent(recent) }
                }
                Divider()
                Button("Clear Menu") { model.clearRecent() }
                    .disabled(model.recentWorkspaces.isEmpty)
            }
            Divider()
            Button("Add Files…") { model.addFilesPanel() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(!model.isOpen)
            Button("Add New Files from Full-Texts Folder…") { model.scanForNewFiles() }
                .disabled(!model.isOpen)
            Button("Update Empirical File from New Version…") {
                if let k = model.fileToUpdate { model.updateFile(k) }
            }
            .disabled(model.fileToUpdate == nil)
            Button("Choose Full-Texts Folder…") { model.chooseFullTextsFolder() }
                .disabled(!model.isOpen)
            Divider()
            Button("Show Workspace in Finder") { model.revealInFinder() }
                .disabled(!model.isOpen)
            Button("Close Project") { model.closeProject() }
                .disabled(!model.isOpen)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Save Now") { model.flushSaves() }
                .keyboardShortcut("s")
                .disabled(!model.isOpen)
        }

        CommandGroup(after: .toolbar) {
            Button("Larger Text") { model.readingSize = min(32, model.readingSize + 1) }
                .keyboardShortcut("+")
            Button("Smaller Text") { model.readingSize = max(10, model.readingSize - 1) }
                .keyboardShortcut("-")
            Button("Default Text Size") { model.readingSize = 15 }
                .keyboardShortcut("0")
            Divider()
            Toggle("Show Coding Stripes", isOn: Binding(get: { model.showStripes }, set: { model.showStripes = $0 }))
            Toggle("Show Code Names Beside Stripes", isOn: Binding(get: { model.showCodeNames }, set: { model.showCodeNames = $0 }))
                .disabled(!model.showStripes)
            Toggle("Show Other Layers", isOn: Binding(get: { model.showOtherLayers }, set: { model.showOtherLayers = $0 }))
            if model.project.settings.interlocutorLayer {
                Toggle("Show Interlocutors", isOn: Binding(get: { model.showSpeakers }, set: { model.setShowSpeakers($0) }))
                    .keyboardShortcut("i", modifiers: [.command, .control])
            }
            Divider()
            Toggle("Show Real Names", isOn: Binding(get: { model.showRealNames }, set: { model.showRealNames = $0 }))
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!model.hasRealNameFiles)
            Button("Reload Real Names") { model.loadRealNames() }
                .disabled(!model.hasRealNameFiles)
            Divider()
            Button("Reload from Disk") { model.checkForOutsideChanges(force: true) }
                .keyboardShortcut("r")
                .disabled(!model.isOpen)
            Divider()
        }

        CommandMenu("Code") {
            Button("Apply \(model.codeNounTitle) to Selection…") { model.paletteVisible = true }
                .keyboardShortcut("k")
                .disabled(!inFile || !model.canCode)
            Button("Highlight Without \(model.codeNounTitle)") { model.highlightOnly() }
                .keyboardShortcut("k", modifiers: [.command, .option])
                .disabled(!model.hasTextSelection)
            Button("Mark as Irrelevant / Relevant") { model.toggleIrrelevant() }
                .keyboardShortcut("0", modifiers: [.command, .option])
                .disabled(!model.canCode)
            Menu("Quick \(model.codeNounTitle)") {
                ForEach(1...9, id: \.self) { n in
                    let key = model.quickCodes[n - 1]
                    Button("\(n): " + (model.tag(key)?.name ?? "—")) { model.applyQuickCode(n) }
                        .keyboardShortcut(KeyEquivalent(Character(String(n))), modifiers: [.control])
                        .disabled(key.isEmpty || !model.canCode)
                }
            }
            Divider()
            Button("Mark as Protocol Prompt…") { model.openProtocolPalette(.prompt) }
                .disabled(!inFile || !model.canCode || !model.activeIsDeductive)
            Button("Mark as Protocol Response…") { model.openProtocolPalette(.response) }
                .disabled(!inFile || !model.canCode || !model.activeIsDeductive)
            Divider()
            Button("Resize Focused Selection to Text Selection") { model.resizeFocusedToTextSelection() }
                .disabled(model.focusedSelection == nil || !model.hasTextSelection)
            Button("Delete Selection") { model.deleteFocusedSelection() }
                .keyboardShortcut(.delete, modifiers: [.command])
                .disabled(model.focusedSelection == nil)
            Divider()
            Button("Next Selection") { model.stepSelection(1) }
                .keyboardShortcut("]")
                .disabled(!inFile)
            Button("Previous Selection") { model.stepSelection(-1) }
                .keyboardShortcut("[")
                .disabled(!inFile)
            Divider()
            Button("New Open Code…") { model.sheet = .newCode(kind: .open, parent: nil, child: nil) }
                .disabled(!model.isOpen)
            Button("New Theorising Code…") { model.sheet = .newCode(kind: .theorising, parent: nil, child: nil) }
                .disabled(!model.isOpen)
            Button("New A Priori Code") { model.newAprioriCode() }
                .disabled(!model.isOpen)
            Button("New Protocol") { model.newProtocol() }
                .disabled(!model.isOpen)
        }

        CommandMenu("Go") {
            Button("Next File") { model.stepFile(1) }
                .keyboardShortcut("]", modifiers: [.command, .option])
                .disabled(!model.isOpen)
            Button("Previous File") { model.stepFile(-1) }
                .keyboardShortcut("[", modifiers: [.command, .option])
                .disabled(!model.isOpen)
            Button("Next File Not Yet Coded") { model.nextUncodedFile() }
                .keyboardShortcut("n", modifiers: [.command, .option])
                .disabled(!model.isOpen)
            Divider()
            Button("Mark File as Coded") { if let k = model.openFileKey { model.setStatus(.coded, file: k) } }
                .keyboardShortcut("c", modifiers: [.command, .control])
                .disabled(!inFile)
            Divider()
            Button("Back") { model.goBack() }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .control])
                .disabled(!model.canGoBack)
            Button("Forward") { model.goForward() }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .control])
                .disabled(!model.canGoForward)
            Divider()
            let pages: [(String, SidebarItem)] = [("Empirical Files", .files), ("Researchers", .researchers),
                                                  ("Layers", .layers), ("Project Settings", .settings),
                                                  ("Protocols", .protocols), ("Interviewees", .interviewees),
                                                  ("Attribute Sheets", .attributeSheets), ("A Priori Codes", .aprioriCodes),
                                                  ("Open Codes", .openCodes), ("Theorising Codes", .theorisingCodes),
                                                  ("Coding Chart", .codingChart), ("Attribute Sheet Report", .attributeSheetReport),
                                                  ("Protocol Report", .protocolReport)]
            // ⌃⌘1 … ⌃⌘9, then ⌃⌘0 for the tenth; the rest have none.
            ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                Button(page.0) { model.sidebar = page.1 }
                    .keyboardShortcut(i < 10 ? KeyboardShortcut(KeyEquivalent(Character(String((i + 1) % 10))),
                                                                modifiers: [.command, .control]) : nil)
                    .disabled(!model.isOpen)
            }
            Divider()
            Menu("Layer") {
                ForEach(model.project.layers) { layer in
                    Button(layer.name) { model.setActiveLayer(layer.key) }
                        .disabled(layer.key == model.activeLayerKey)
                }
            }
            .disabled(!model.isOpen)
        }

        CommandGroup(before: .windowList) {
            Button("Welcome to QDVC Empirics") {
                model.welcomeRequested = true
                openWindow(id: WelcomeWindow.id)
            }
            .keyboardShortcut("1", modifiers: [.command, .shift])
            Divider()
        }
    }
}

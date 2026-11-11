import AppKit
import EmpiricsCore
import SwiftUI

/// The window shown at launch, as in Xcode and Keynote (and the other QDVC
/// apps): the app on the left with New and Open, recent projects on the
/// right.
struct WelcomeWindow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var selection: String?

    static let id = "welcome"

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "development build"
    }

    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                Spacer(minLength: 28)
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 128, height: 128)
                Text("QDVC Empirics")
                    .font(.system(size: 26, weight: .semibold))
                    .padding(.top, 6)
                Text("Version \(version)")
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
                Spacer(minLength: 28)
                VStack(alignment: .leading, spacing: 6) {
                    WelcomeAction(symbol: "plus.square", title: "Create a New Project…",
                                  detail: "A workspace for Git, and a full-texts folder kept apart") {
                        model.sheet = .newProject(nil)
                    }
                    WelcomeAction(symbol: "folder", title: "Open an Existing Project…",
                                  detail: "Choose a project's workspace folder") {
                        model.chooseWorkspace()
                    }
                }
                .frame(width: 340)
                Spacer(minLength: 28)
                Toggle("Show this window when QDVC Empirics opens", isOn: $model.showWelcomeAtLaunch)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }
            .frame(width: 440)

            Divider()

            VStack(spacing: 0) {
                if model.recentWorkspaces.isEmpty {
                    ContentUnavailableView("No Recent Projects", systemImage: "clock",
                                           description: Text("Projects you open appear here."))
                } else {
                    List(selection: $selection) {
                        ForEach(model.recentWorkspaces, id: \.path) { recent in
                            RecentRow(path: recent.path).tag(recent.path)
                        }
                    }
                    .listStyle(.sidebar)
                    .contextMenu(forSelectionType: String.self) { paths in
                        if let path = paths.first {
                            Button("Open") { openRecent(path) }
                            Divider()
                            Button("Remove from List") { model.removeRecent(path: path) }
                        }
                    } primaryAction: { paths in
                        if let path = paths.first { openRecent(path) }
                    }
                }
                Divider()
                HStack {
                    Text(model.recentWorkspaces.isEmpty ? "" : "Double-click to open")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button("Clear Recent List") {
                        model.clearRecent()
                        selection = nil
                    }
                    .disabled(model.recentWorkspaces.isEmpty)
                }
                .controlSize(.small)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .frame(width: 340)
        }
        .frame(height: 460)
        .ignoresSafeArea()
        // Sheets and alerts show here only while no project is open; with a
        // project open, the main window shows them.
        .sheet(item: model.isOpen ? .constant(nil) : $model.sheet) { kind in
            SheetHost(kind: kind).environment(model)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { !model.isOpen && model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
        .onAppear {
            model.startUp()
            if model.isOpen && !model.welcomeRequested { proceed() }
            model.welcomeRequested = false
        }
        .onChange(of: model.workspaceURL) { _, url in
            if url != nil { proceed() }
        }
        .modifier(NoWritingTools())
    }

    private func openRecent(_ path: String) {
        guard let recent = model.recentWorkspaces.first(where: { $0.path == path }) else { return }
        model.openRecent(recent)
        if model.isOpen { proceed() }
    }

    /// Hands over to the main window.
    private func proceed() {
        openWindow(id: MainWindowID.main)
        // Close this one a moment later, so the app never has no window
        // (which would quit it).
        DispatchQueue.main.async { dismissWindow(id: Self.id) }
    }
}

enum MainWindowID {
    static let main = "main"
}

/// A big row on the left of the welcome window.
struct WelcomeAction: View {
    var symbol: String
    var title: String
    var detail: String
    var action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.system(size: 22))
                    .foregroundStyle(.tint)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).fontWeight(.medium)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(RoundedRectangle(cornerRadius: 8).fill(hovering ? Color.primary.opacity(0.07) : .clear))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A recent project: its folder name, title, and where it is.
struct RecentRow: View {
    var path: String

    var body: some View {
        let url = URL(fileURLWithPath: path)
        // Reading the title needs access to the folder, which a sandboxed app
        // has only once the bookmark is resolved; show what we can.
        let summary = Workspace.summary(url)
        HStack(spacing: 10) {
            Image(systemName: "folder.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text(summary.map { $0.title.isEmpty ? url.lastPathComponent : $0.title } ?? url.lastPathComponent)
                    .fontWeight(.medium).lineLimit(1)
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 3)
        .help(path)
    }
}

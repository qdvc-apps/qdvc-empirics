import AppKit
import EmpiricsCore
import Foundation

/// What this Mac remembers, outside any workspace (UserDefaults): recent
/// projects, and per project the full-texts folder, who the researcher at
/// this Mac is, the active and hidden layers, quick codes and reading
/// positions. None of it is written to the workspace, so it never reaches
/// Git; Settings › Privacy erases it.
///
/// The app is sandboxed (docs/DESIGN.md §Data security), so folders are
/// remembered as security-scoped bookmarks, the full-texts folder's too
/// (read and write: a confirmed edit to a text file is written there; a
/// folder chosen before edits existed has a read-only bookmark, and is
/// chosen again when an edit needs it).
@MainActor
enum DeviceStore {
    static var defaults: UserDefaults { .standard }

    // MARK: Bookmarks

    static func bookmark(_ url: URL, readOnly: Bool) -> Data? {
        var options: URL.BookmarkCreationOptions = [.withSecurityScope]
        if readOnly { options.insert(.securityScopeAllowOnlyReadAccess) }
        if let data = try? url.bookmarkData(options: options, includingResourceValuesForKeys: nil, relativeTo: nil) {
            return data
        }
        // Not sandboxed (swift run): a plain bookmark is enough.
        return try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a bookmark and starts access to it (balanced by
    /// `stopAccessing` when the project closes).
    static func resolve(_ data: Data) -> URL? {
        var stale = false
        if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil,
                              bookmarkDataIsStale: &stale) {
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
        if let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) {
            return url
        }
        return nil
    }

    // MARK: Recent projects

    private static let recentKey = "recentWorkspaces"

    struct Recent: Equatable {
        var path: String
        var bookmark: Data
    }

    static var recents: [Recent] {
        let list = defaults.array(forKey: recentKey) as? [[String: Any]] ?? []
        return list.compactMap { d in
            guard let path = d["path"] as? String, let data = d["bookmark"] as? Data else { return nil }
            return Recent(path: path, bookmark: data)
        }
    }

    static func setRecents(_ list: [Recent]) {
        defaults.set(list.prefix(12).map { ["path": $0.path, "bookmark": $0.bookmark] as [String: Any] }, forKey: recentKey)
    }

    static func addRecent(_ url: URL) {
        guard let data = bookmark(url, readOnly: false) else { return }
        var list = recents.filter { $0.path != url.path }
        list.insert(Recent(path: url.path, bookmark: data), at: 0)
        setRecents(list)
    }

    static func removeRecent(path: String) {
        setRecents(recents.filter { $0.path != path })
    }

    // MARK: Per project

    private static func key(_ name: String, _ project: String) -> String { "project.\(project).\(name)" }

    /// The full-texts folder for a project on this Mac.
    static func fullTexts(project: String) -> URL? {
        guard let data = defaults.data(forKey: key("fullTexts", project)) else { return nil }
        return resolve(data)
    }

    static func fullTextsPath(project: String) -> String? {
        defaults.string(forKey: key("fullTextsPath", project))
    }

    static func setFullTexts(_ url: URL, project: String, title: String) {
        guard let data = bookmark(url, readOnly: false) else { return }
        defaults.set(data, forKey: key("fullTexts", project))
        defaults.set(url.path, forKey: key("fullTextsPath", project))
        defaults.set(title, forKey: key("title", project))
        remember(project)
    }

    static func forgetFullTexts(project: String) {
        defaults.removeObject(forKey: key("fullTexts", project))
        defaults.removeObject(forKey: key("fullTextsPath", project))
    }

    /// The researcher at this Mac (a researcher key), per project.
    static func researcher(project: String) -> String? {
        defaults.string(forKey: key("researcher", project))
    }

    static func setResearcher(_ researcher: String?, project: String, title: String) {
        if let researcher, !researcher.isEmpty {
            defaults.set(researcher, forKey: key("researcher", project))
            defaults.set(title, forKey: key("title", project))
            remember(project)
        } else {
            defaults.removeObject(forKey: key("researcher", project))
        }
    }

    static func string(_ name: String, project: String) -> String? { defaults.string(forKey: key(name, project)) }

    static func setString(_ value: String?, _ name: String, project: String) {
        if let value { defaults.set(value, forKey: key(name, project)) } else { defaults.removeObject(forKey: key(name, project)) }
    }

    static func strings(_ name: String, project: String) -> [String] {
        defaults.stringArray(forKey: key(name, project)) ?? []
    }

    static func setStrings(_ value: [String], _ name: String, project: String) {
        defaults.set(value, forKey: key(name, project))
    }

    static func positions(project: String) -> [String: Int] {
        defaults.dictionary(forKey: key("positions", project)) as? [String: Int] ?? [:]
    }

    static func setPositions(_ value: [String: Int], project: String) {
        defaults.set(value, forKey: key("positions", project))
    }

    // MARK: Privacy (Settings)

    private static let knownKey = "knownProjects"

    private static func remember(_ project: String) {
        var known = defaults.stringArray(forKey: knownKey) ?? []
        if !known.contains(project) {
            known.append(project)
            defaults.set(known, forKey: knownKey)
        }
    }

    struct Remembered: Identifiable, Equatable {
        var id: String { project }
        var project: String
        var title: String
        var fullTextsPath: String?
        var researcher: String?
    }

    /// Projects this Mac remembers a full-texts folder or researcher for.
    static var remembered: [Remembered] {
        (defaults.stringArray(forKey: knownKey) ?? []).compactMap { p in
            let path = fullTextsPath(project: p)
            let researcher = self.researcher(project: p)
            guard path != nil || researcher != nil else { return nil }
            return Remembered(project: p, title: defaults.string(forKey: key("title", p)) ?? p,
                              fullTextsPath: path, researcher: researcher)
        }
    }

    /// Forgets everything this Mac remembers about a project (its full-texts
    /// folder, researcher, layers, quick codes and positions).
    static func forgetAll(project: String) {
        for name in ["fullTexts", "fullTextsPath", "researcher", "title", "activeLayer", "hiddenLayers", "positions",
                     "lastFile", "lastItem", "workingArea", "showSpeakers"] {
            defaults.removeObject(forKey: key(name, project))
        }
        for k in defaults.dictionaryRepresentation().keys where k.hasPrefix("project.\(project).quick.") {
            defaults.removeObject(forKey: k)
        }
        defaults.set((defaults.stringArray(forKey: knownKey) ?? []).filter { $0 != project }, forKey: knownKey)
    }
}

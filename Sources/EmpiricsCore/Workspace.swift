import Foundation

/// One file (or folder) of a workspace, for saving only what changed.
public enum WorkspacePart: Hashable {
    case project
    case file(String)
    case codebook(String)
    case response(ResponseID)
    /// layers/<key>/layer.yml; the whole folder goes if the layer is deleted.
    case layer(String)
    case selections(layer: String, file: String)
    case code(layer: String, code: String)
    case researchers
    case interviewees
    case speakers(String)
}

public struct WorkspaceError: Error, LocalizedError, Equatable {
    public var file: String
    public var message: String

    public init(file: String, message: String) {
        self.file = file
        self.message = message
    }

    public var errorDescription: String? { "\(file): \(message)" }
}

/// A loaded project, with notes about anything that had to be repaired.
public struct LoadedWorkspace {
    public var project: Project
    public var notes: [String]

    public init(project: Project, notes: [String]) {
        self.project = project
        self.notes = notes
    }
}

/// A project's workspace folder (docs/FILE_FORMAT.md):
///
///     project.yml                          title, settings, layer order
///     files/<f-key>.yml                    the catalogue, one file per full-text
///     codebooks/<cb-key>.yml               codebooks and their questions
///     responses/<cb-key>/<target>[--<r-key>].yml   response sheets
///     layers/<l-key>/layer.yml             a layer's name and description
///     layers/<l-key>/selections/<f-key>.yml   its selections in one file
///     layers/<l-key>/codes/<c-key>.yml     its codes, one file each
///     people/researchers.yml, people/interviewees.yml
///     interlocutors/<f-key>.yml            speaker labels → people
///
/// Full-texts and consent forms are never in it.
public enum Workspace {
    public static let formatVersion = 1
    public static let appName = "QDVC Empirics"
    public static let projectFile = "project.yml"
    public static let filesFolder = "files"
    public static let codebooksFolder = "codebooks"
    public static let responsesFolder = "responses"
    public static let layersFolder = "layers"
    public static let peopleFolder = "people"
    public static let researchersFile = "people/researchers.yml"
    public static let intervieweesFile = "people/interviewees.yml"
    public static let interlocutorsFolder = "interlocutors"

    public static func isWorkspace(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(projectFile).path)
    }

    /// The title and key of a workspace, read cheaply for lists of recent
    /// projects; nil if the folder isn't a readable workspace.
    public static func summary(_ url: URL) -> (title: String, key: String)? {
        guard let text = try? String(contentsOf: url.appendingPathComponent(projectFile), encoding: .utf8),
              let node = try? YAML.parse(text) else { return nil }
        return (node["title"]?.string ?? "", node["key"]?.string ?? "")
    }

    /// True if the folder has nothing in it but hidden files.
    public static func isEmptyFolder(_ url: URL) -> Bool {
        let items = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return items.allSatisfy { $0.hasPrefix(".") }
    }

    // MARK: Paths

    public static func path(of part: WorkspacePart) -> String {
        switch part {
        case .project: return projectFile
        case .file(let k): return "\(filesFolder)/\(k).yml"
        case .codebook(let k): return "\(codebooksFolder)/\(k).yml"
        case .response(let id): return id.path
        case .layer(let k): return "\(layersFolder)/\(k)/layer.yml"
        case .selections(let l, let f): return "\(layersFolder)/\(l)/selections/\(f).yml"
        case .code(let l, let c): return "\(layersFolder)/\(l)/codes/\(c).yml"
        case .researchers: return researchersFile
        case .interviewees: return intervieweesFile
        case .speakers(let f): return "\(interlocutorsFolder)/\(f).yml"
        }
    }

    // MARK: Creating

    /// Starts a workspace in `url` (created if needed) and writes everything.
    public static func create(at url: URL, project: Project) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try save(project, parts: allParts(of: project), to: url)
    }

    /// Every part a project has.
    public static func allParts(of p: Project) -> Set<WorkspacePart> {
        var parts: Set<WorkspacePart> = [.project, .researchers, .interviewees]
        for k in p.files.keys { parts.insert(.file(k)) }
        for k in p.codebooks.keys { parts.insert(.codebook(k)) }
        for k in p.responses.keys { parts.insert(.response(k)) }
        for k in p.speakerMaps.keys { parts.insert(.speakers(k)) }
        for layer in p.layers {
            parts.insert(.layer(layer.key))
            for f in layer.selections.keys { parts.insert(.selections(layer: layer.key, file: f)) }
            for c in layer.codes.keys { parts.insert(.code(layer: layer.key, code: c)) }
        }
        return parts
    }

    /// The parts that differ between two versions of a project: what to
    /// write after a change (or an undo).
    public static func changedParts(from old: Project, to new: Project) -> Set<WorkspacePart> {
        var parts = Set<WorkspacePart>()
        if old.settings != new.settings || old.layers.map(\.key) != new.layers.map(\.key) { parts.insert(.project) }
        if old.researchers != new.researchers { parts.insert(.researchers) }
        if old.interviewees != new.interviewees { parts.insert(.interviewees) }
        func diff<K: Hashable, V: Equatable>(_ a: [K: V], _ b: [K: V], _ make: (K) -> WorkspacePart) {
            for k in Set(a.keys).union(b.keys) where a[k] != b[k] { parts.insert(make(k)) }
        }
        diff(old.files, new.files) { .file($0) }
        diff(old.codebooks, new.codebooks) { .codebook($0) }
        diff(old.responses, new.responses) { .response($0) }
        diff(old.speakerMaps, new.speakerMaps) { .speakers($0) }
        let oldLayers = Dictionary(old.layers.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let newLayers = Dictionary(new.layers.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for k in Set(oldLayers.keys).union(newLayers.keys) {
            let a = oldLayers[k], b = newLayers[k]
            if a == b { continue }
            if a?.meta != b?.meta { parts.insert(.layer(k)) }
            diff(a?.selections ?? [:], b?.selections ?? [:]) { .selections(layer: k, file: $0) }
            diff(a?.codes ?? [:], b?.codes ?? [:]) { .code(layer: k, code: $0) }
        }
        return parts
    }

    // MARK: Loading

    public static func load(_ url: URL) throws -> LoadedWorkspace {
        var notes: [String] = []
        let fm = FileManager.default

        let projectNode = try readYAML(url, projectFile, required: true)
        if let format = projectNode["format"]?.int, format > formatVersion {
            throw WorkspaceError(file: projectFile,
                                 message: "written by a newer version of the app (format \(format)); update the app to open it")
        }
        let settings = decodeSettings(projectNode)
        var project = Project(settings: settings)

        for name in yamlFiles(in: url.appendingPathComponent(filesFolder)) {
            let node = try readYAML(url, "\(filesFolder)/\(name)", required: true)
            if let f = decodeFile(key: String(name.dropLast(4)), node) {
                project.files[f.key] = f
            } else {
                notes.append("\(filesFolder)/\(name) has no path; it was skipped.")
            }
        }

        for name in yamlFiles(in: url.appendingPathComponent(codebooksFolder)) {
            let node = try readYAML(url, "\(codebooksFolder)/\(name)", required: true)
            let cb = decodeCodebook(key: String(name.dropLast(4)), node)
            project.codebooks[cb.key] = cb
        }

        let responsesURL = url.appendingPathComponent(responsesFolder)
        for cbFolder in ((try? fm.contentsOfDirectory(atPath: responsesURL.path)) ?? []).sorted() where !cbFolder.hasPrefix(".") {
            for name in yamlFiles(in: responsesURL.appendingPathComponent(cbFolder)) {
                let rel = "\(responsesFolder)/\(cbFolder)/\(name)"
                let node = try readYAML(url, rel, required: true)
                let stem = String(name.dropLast(4))
                let parts = stem.components(separatedBy: "--")
                let id = ResponseID(codebook: cbFolder, target: parts[0], researcher: parts.count > 1 ? parts[1] : "")
                project.responses[id] = decodeResponse(id: id, node)
            }
        }

        // Layers: in project.yml's order, then any folders it doesn't list.
        let layersURL = url.appendingPathComponent(layersFolder)
        var layerKeys = projectNode["layers"]?.strings ?? []
        let onDisk = ((try? fm.contentsOfDirectory(atPath: layersURL.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        for k in onDisk where !layerKeys.contains(k) {
            layerKeys.append(k)
            notes.append("Layer folder \(k) wasn't listed in \(projectFile); it was added at the end.")
        }
        var seenLayers = Set<String>()
        for lk in layerKeys where seenLayers.insert(lk).inserted {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: layersURL.appendingPathComponent(lk).path, isDirectory: &isDir), isDir.boolValue else {
                notes.append("\(projectFile) lists layer \(lk), which has no folder; it was dropped.")
                continue
            }
            let meta = try readYAML(url, "\(layersFolder)/\(lk)/layer.yml", required: false)
            var layer = CodingLayer(key: lk, name: meta["name"]?.string ?? "Layer",
                                    description: meta["description"]?.string ?? "",
                                    researcher: meta["researcher"]?.string ?? "")
            for name in yamlFiles(in: layersURL.appendingPathComponent("\(lk)/selections")) {
                let fk = String(name.dropLast(4))
                let node = try readYAML(url, "\(layersFolder)/\(lk)/selections/\(name)", required: true)
                let list = decodeSelections(fileKey: fk, node)
                if !list.isEmpty { layer.selections[fk] = list.sorted(by: Project.selectionOrder) }
            }
            for name in yamlFiles(in: layersURL.appendingPathComponent("\(lk)/codes")) {
                let node = try readYAML(url, "\(layersFolder)/\(lk)/codes/\(name)", required: true)
                let code = decodeCode(key: String(name.dropLast(4)), node)
                layer.codes[code.key] = code
            }
            project.layers.append(layer)
        }
        if project.layers.isEmpty {
            project.layers = [CodingLayer(key: project.newKey(Keys.layer), name: "Main")]
            notes.append("The project had no layers, so a layer called Main was added.")
        }

        project.researchers = try readYAML(url, researchersFile, required: false)["researchers"]?.items.compactMap(decodeResearcher) ?? []
        project.interviewees = try readYAML(url, intervieweesFile, required: false)["interviewees"]?.items.compactMap(decodeInterviewee) ?? []

        for name in yamlFiles(in: url.appendingPathComponent(interlocutorsFolder)) {
            let fk = String(name.dropLast(4))
            let node = try readYAML(url, "\(interlocutorsFolder)/\(name)", required: true)
            project.speakerMaps[fk] = decodeSpeakers(fileKey: fk, node)
        }

        notes.append(contentsOf: repair(&project))
        return LoadedWorkspace(project: project, notes: notes)
    }

    /// Fixes what a merge or hand edit can break, and says what it did.
    /// The fixes are in memory only; nothing is written until something
    /// changes.
    static func repair(_ p: inout Project) -> [String] {
        var notes: [String] = []
        // A selection or code in two layers keeps its first.
        var seen = Set<String>()
        for li in p.layers.indices {
            for (fk, list) in p.layers[li].selections {
                let kept = list.filter { seen.insert($0.key).inserted }
                if kept.count != list.count {
                    notes.append("Some selections in \(p.layers[li].name) also exist in another layer; only the first copy is shown.")
                    p.layers[li].selections[fk] = kept
                }
            }
            for ck in p.layers[li].codes.keys.sorted() where !seen.insert(ck).inserted {
                notes.append("Code \(p.layers[li].codes[ck]!.name) exists in more than one layer; only the first copy is shown.")
                p.layers[li].codes[ck] = nil
            }
        }
        // Evidence pointing outside its layer, or at the wrong kind.
        for li in p.layers.indices {
            let layer = p.layers[li]
            for (ck, c) in layer.codes {
                let valid = c.evidence.filter { e in
                    c.kind == .open ? layer.selection(e.target).map { !$0.irrelevant } ?? false : layer.codes[e.target] != nil
                }
                if valid.count != c.evidence.count {
                    notes.append("\(c.name) listed evidence that isn't in its layer (or is irrelevant); it is ignored.")
                    p.layers[li].codes[ck]!.evidence = valid
                }
            }
        }
        return notes
    }

    static func yamlFiles(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".yml") && !$0.hasPrefix(".") }
            .sorted()
    }

    static func readYAML(_ root: URL, _ relative: String, required: Bool) throws -> YAMLNode {
        let url = root.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if required { throw WorkspaceError(file: relative, message: "missing") }
            return .mapping([])
        }
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw WorkspaceError(file: relative, message: "can't be read as UTF-8 text")
        }
        if text.contains("\n<<<<<<< ") || text.hasPrefix("<<<<<<< ") {
            throw WorkspaceError(file: relative, message: "has unresolved Git merge conflict markers (<<<<<<<); resolve them, then reopen")
        }
        do {
            let node = try YAML.parse(text)
            if node.isNull { return .mapping([]) }
            return node
        } catch let e as YAMLError {
            throw WorkspaceError(file: relative, message: e.description)
        }
    }

    // MARK: Saving

    /// Writes the given parts (deleting the files of parts that no longer
    /// exist). Files whose content is unchanged are not rewritten, so Git
    /// sees only real changes.
    public static func save(_ p: Project, parts: Set<WorkspacePart>, to root: URL) throws {
        let layers = Dictionary(p.layers.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        // Deleted layers first (whole folders), then everything else.
        for part in parts {
            if case .layer(let k) = part, layers[k] == nil {
                let folder = root.appendingPathComponent("\(layersFolder)/\(k)")
                if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
            }
        }
        for part in parts {
            let rel = path(of: part)
            let text: String?
            switch part {
            case .project: text = emit(encodeSettings(p))
            case .file(let k): text = p.files[k].map { emit(encodeFile($0)) }
            case .codebook(let k): text = p.codebooks[k].map { emit(encodeCodebook($0)) }
            case .response(let id):
                text = p.responses[id].map { emit(encodeResponse($0, codebook: p.codebooks[id.codebook])) }
            case .layer(let k):
                guard let layer = layers[k] else { continue }
                text = emit(encodeLayer(layer))
            case .selections(let l, let f):
                guard let layer = layers[l] else { continue }
                text = (layer.selections[f]).flatMap { $0.isEmpty ? nil : emit(encodeSelections(file: f, $0)) }
            case .code(let l, let c):
                guard let layer = layers[l] else { continue }
                text = layer.codes[c].map { emit(encodeCode($0)) }
            case .researchers:
                text = p.researchers.isEmpty ? nil : "# First and last names are pseudonyms. Real names, if mapped, stay in the full-texts folder.\n"
                    + emit(.mapping([YAMLPair("researchers", .sequence(p.researchers.map(encodeResearcher)))]))
            case .interviewees:
                text = p.interviewees.isEmpty ? nil : "# First and last names are pseudonyms. Real names (if mapped) and consent forms stay in the full-texts folder.\n"
                    + emit(.mapping([YAMLPair("interviewees", .sequence(p.interviewees.map(encodeInterviewee)))]))
            case .speakers(let f):
                text = p.speakerMaps[f].flatMap { $0.isEmpty ? nil : emit(encodeSpeakers($0)) }
            }
            let url = root.appendingPathComponent(rel)
            if let text {
                try writeIfChanged(text, to: url)
            } else if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
                removeEmptyFolders(from: url.deletingLastPathComponent(), upTo: root)
            }
        }
    }

    static func emit(_ node: YAMLNode) -> String {
        // Multi-line text becomes a block scalar (|); single lines stay plain.
        YAML.emit(node)
    }

    static func writeIfChanged(_ text: String, to url: URL) throws {
        let data = Data(text.utf8)
        if let existing = try? Data(contentsOf: url), existing == data { return }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// Removes now-empty folders (responses/<cb>, layers/<l>/codes…), so the
    /// tree stays tidy; stops at the workspace root.
    static func removeEmptyFolders(from folder: URL, upTo root: URL) {
        var f = folder.standardizedFileURL
        let r = root.standardizedFileURL.path
        while f.path.hasPrefix(r) && f.path != r {
            let items = (try? FileManager.default.contentsOfDirectory(atPath: f.path)) ?? ["x"]
            guard items.allSatisfy({ $0 == ".DS_Store" }) else { return }
            try? FileManager.default.removeItem(at: f)
            f = f.deletingLastPathComponent()
        }
    }

    /// A cheap signature of every file in the workspace (paths, sizes,
    /// modification dates), to notice changes made by Git or an editor.
    public static func signature(_ root: URL) -> String {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
                                    options: [.skipsHiddenFiles]) else { return "" }
        var parts: [String] = []
        let base = root.standardizedFileURL.path
        for case let url as URL in e where url.pathExtension == "yml" {
            let v = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            let rel = String(url.standardizedFileURL.path.dropFirst(base.count))
            parts.append("\(rel)|\(v?.fileSize ?? 0)|\(v?.contentModificationDate?.timeIntervalSince1970 ?? 0)")
        }
        return parts.sorted().joined(separator: "\n")
    }
}

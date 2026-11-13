import Foundation

/// One file (or folder) of a workspace, for saving only what changed.
public enum WorkspacePart: Hashable {
    case project
    case file(String)
    case studyProtocol(String)
    case aprioriCode(String)
    case attributeSheet(String)
    case response(ResponseID)
    /// layers/<key>/layer.yml; the whole folder goes if the layer is deleted.
    case layer(String)
    /// A file's selections in a layer, and (deductive layers) the protocol
    /// it follows there.
    case selections(layer: String, file: String)
    case code(layer: String, code: String)
    /// A deductive layer's evidence for one a priori code.
    case aprioriEvidence(layer: String, code: String)
    /// A deductive layer's Framework Matrix summaries for one row.
    case framework(layer: String, row: String)
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
///     protocols/<pr-key>.yml               protocols and their items
///     apriori-codes/<apc-key>.yml          a priori codes (codebook entries)
///     attribute-sheets/<ast-key>.yml       attribute sheets and their questions
///     attribute-responses/<ast-key>/<target>[--<r-key>].yml   response sheets
///     layers/<l-key>/layer.yml             a layer's kind, name and description
///     layers/<l-key>/selections/<f-key>.yml   its selections in one file
///     layers/<l-key>/codes/<c-key>.yml     inductive: its codes, one file each
///     layers/<l-key>/apriori/<apc-key>.yml    deductive: evidence for one a priori code
///     layers/<l-key>/framework/<row>.yml   deductive: Framework Matrix summaries
///     people/researchers.yml, people/interviewees.yml
///     interlocutors/<f-key>.yml            speaker labels → people
///
/// Full-texts and consent forms are never in it.
public enum Workspace {
    public static let formatVersion = 1
    public static let appName = "QDVC Empirics"
    public static let projectFile = "project.yml"
    public static let filesFolder = "files"
    public static let protocolsFolder = "protocols"
    public static let aprioriCodesFolder = "apriori-codes"
    public static let attributeSheetsFolder = "attribute-sheets"
    public static let responsesFolder = "attribute-responses"
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
        case .studyProtocol(let k): return "\(protocolsFolder)/\(k).yml"
        case .aprioriCode(let k): return "\(aprioriCodesFolder)/\(k).yml"
        case .attributeSheet(let k): return "\(attributeSheetsFolder)/\(k).yml"
        case .response(let id): return id.path
        case .layer(let k): return "\(layersFolder)/\(k)/layer.yml"
        case .selections(let l, let f): return "\(layersFolder)/\(l)/selections/\(f).yml"
        case .code(let l, let c): return "\(layersFolder)/\(l)/codes/\(c).yml"
        case .aprioriEvidence(let l, let c): return "\(layersFolder)/\(l)/apriori/\(c).yml"
        case .framework(let l, let r): return "\(layersFolder)/\(l)/framework/\(r).yml"
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
        for k in p.protocols.keys { parts.insert(.studyProtocol(k)) }
        for k in p.aprioriCodes.keys { parts.insert(.aprioriCode(k)) }
        for k in p.attributeSheets.keys { parts.insert(.attributeSheet(k)) }
        for k in p.responses.keys { parts.insert(.response(k)) }
        for k in p.speakerMaps.keys { parts.insert(.speakers(k)) }
        for layer in p.layers {
            parts.insert(.layer(layer.key))
            for f in Set(layer.selections.keys).union(layer.protocols.keys) {
                parts.insert(.selections(layer: layer.key, file: f))
            }
            for c in layer.codes.keys { parts.insert(.code(layer: layer.key, code: c)) }
            for c in layer.aprioriEvidence.keys { parts.insert(.aprioriEvidence(layer: layer.key, code: c)) }
            for r in layer.framework.keys { parts.insert(.framework(layer: layer.key, row: r)) }
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
        diff(old.protocols, new.protocols) { .studyProtocol($0) }
        diff(old.aprioriCodes, new.aprioriCodes) { .aprioriCode($0) }
        diff(old.attributeSheets, new.attributeSheets) { .attributeSheet($0) }
        diff(old.responses, new.responses) { .response($0) }
        diff(old.speakerMaps, new.speakerMaps) { .speakers($0) }
        let oldLayers = Dictionary(old.layers.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let newLayers = Dictionary(new.layers.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        for k in Set(oldLayers.keys).union(newLayers.keys) {
            let a = oldLayers[k], b = newLayers[k]
            if a == b { continue }
            if a?.meta != b?.meta { parts.insert(.layer(k)) }
            diff(a?.selections ?? [:], b?.selections ?? [:]) { .selections(layer: k, file: $0) }
            diff(a?.protocols ?? [:], b?.protocols ?? [:]) { .selections(layer: k, file: $0) }
            diff(a?.codes ?? [:], b?.codes ?? [:]) { .code(layer: k, code: $0) }
            diff(a?.aprioriEvidence ?? [:], b?.aprioriEvidence ?? [:]) { .aprioriEvidence(layer: k, code: $0) }
            diff(a?.framework ?? [:], b?.framework ?? [:]) { .framework(layer: k, row: $0) }
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

        for name in yamlFiles(in: url.appendingPathComponent(protocolsFolder)) {
            let node = try readYAML(url, "\(protocolsFolder)/\(name)", required: true)
            let pr = decodeProtocol(key: String(name.dropLast(4)), node)
            project.protocols[pr.key] = pr
        }

        for name in yamlFiles(in: url.appendingPathComponent(aprioriCodesFolder)) {
            let node = try readYAML(url, "\(aprioriCodesFolder)/\(name)", required: true)
            let c = decodeAprioriCode(key: String(name.dropLast(4)), node)
            project.aprioriCodes[c.key] = c
        }

        for name in yamlFiles(in: url.appendingPathComponent(attributeSheetsFolder)) {
            let node = try readYAML(url, "\(attributeSheetsFolder)/\(name)", required: true)
            let cb = decodeAttributeSheet(key: String(name.dropLast(4)), node)
            project.attributeSheets[cb.key] = cb
        }

        let responsesURL = url.appendingPathComponent(responsesFolder)
        for cbFolder in ((try? fm.contentsOfDirectory(atPath: responsesURL.path)) ?? []).sorted() where !cbFolder.hasPrefix(".") {
            for name in yamlFiles(in: responsesURL.appendingPathComponent(cbFolder)) {
                let rel = "\(responsesFolder)/\(cbFolder)/\(name)"
                let node = try readYAML(url, rel, required: true)
                let stem = String(name.dropLast(4))
                let parts = stem.components(separatedBy: "--")
                let id = ResponseID(attributeSheet: cbFolder, target: parts[0], researcher: parts.count > 1 ? parts[1] : "")
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
            // A layer that doesn't say is inductive (as every layer was before
            // layers had kinds).
            var layer = CodingLayer(key: lk, kind: meta["kind"]?.string.flatMap(LayerKind.init(rawValue:)) ?? .inductive,
                                    name: meta["name"]?.string ?? "Layer",
                                    description: meta["description"]?.string ?? "",
                                    researcher: meta["researcher"]?.string ?? "")
            for name in yamlFiles(in: layersURL.appendingPathComponent("\(lk)/selections")) {
                let fk = String(name.dropLast(4))
                let node = try readYAML(url, "\(layersFolder)/\(lk)/selections/\(name)", required: true)
                let list = decodeSelections(fileKey: fk, node)
                if !list.isEmpty { layer.selections[fk] = list.sorted(by: Project.selectionOrder) }
                if let pr = node["protocol"]?.string, !pr.isEmpty { layer.protocols[fk] = pr }
            }
            for name in yamlFiles(in: layersURL.appendingPathComponent("\(lk)/codes")) {
                let node = try readYAML(url, "\(layersFolder)/\(lk)/codes/\(name)", required: true)
                let code = decodeCode(key: String(name.dropLast(4)), node)
                layer.codes[code.key] = code
            }
            for name in yamlFiles(in: layersURL.appendingPathComponent("\(lk)/apriori")) {
                let node = try readYAML(url, "\(layersFolder)/\(lk)/apriori/\(name)", required: true)
                let evidence = decodeAprioriEvidence(node)
                if !evidence.isEmpty { layer.aprioriEvidence[String(name.dropLast(4))] = evidence }
            }
            for name in yamlFiles(in: layersURL.appendingPathComponent("\(lk)/framework")) {
                let node = try readYAML(url, "\(layersFolder)/\(lk)/framework/\(name)", required: true)
                let cells = decodeFrameworkRow(node)
                if !cells.isEmpty { layer.framework[String(name.dropLast(4))] = cells }
            }
            project.layers.append(layer)
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
        notes.append(contentsOf: repairKinds(&p))
        return notes
    }

    /// The rules about deductive and inductive layers (Editing.swift):
    /// each kind's content only in layers of that kind, a priori evidence
    /// and protocol segments that fit, links to existing a priori codes, and
    /// at least one layer of each kind.
    static func repairKinds(_ p: inout Project) -> [String] {
        var notes: [String] = []
        for li in p.layers.indices {
            let name = p.layers[li].name
            if p.layers[li].isDeductive {
                if !p.layers[li].codes.isEmpty {
                    notes.append("\(name) is deductive but had open or theorising codes; they are ignored.")
                    p.layers[li].codes = [:]
                }
                // Protocols that exist; segments of the file's protocol.
                for (file, pr) in p.layers[li].protocols where p.protocols[pr] == nil {
                    notes.append("\(name) gave a file a protocol that doesn't exist; it is ignored.")
                    p.layers[li].protocols[file] = nil
                }
                for (file, list) in p.layers[li].selections {
                    var fixed = list
                    for i in fixed.indices {
                        guard let seg = fixed[i].segment else { continue }
                        let owner = p.protocolItem(seg.item)?.protocolKey
                        if fixed[i].irrelevant || owner == nil {
                            fixed[i].segment = nil
                        } else if let current = p.layers[li].protocols[file] {
                            if current != owner { fixed[i].segment = nil }
                        } else {
                            p.layers[li].protocols[file] = owner
                        }
                    }
                    if fixed != list {
                        notes.append("Some protocol segments in \(name) don't belong to their file's protocol; they are plain selections now.")
                        p.layers[li].selections[file] = fixed
                    }
                }
                // A priori evidence: existing codes; selections of this layer
                // that are neither irrelevant nor protocol segments.
                let layer = p.layers[li]
                for (apc, evidence) in layer.aprioriEvidence {
                    guard p.aprioriCodes[apc] != nil else {
                        notes.append("\(name) has evidence for an a priori code that doesn't exist; it is ignored.")
                        p.layers[li].aprioriEvidence[apc] = nil
                        continue
                    }
                    let valid = evidence.filter { e in
                        layer.selection(e.target).map { !$0.irrelevant && $0.segment == nil } ?? false
                    }
                    if valid.count != evidence.count {
                        notes.append("\(p.aprioriCodes[apc]!.name) listed evidence in \(name) that isn't there (or is irrelevant, or a protocol segment); it is ignored.")
                        p.layers[li].aprioriEvidence[apc] = valid.isEmpty ? nil : valid
                    }
                }
            } else {
                if !p.layers[li].aprioriEvidence.isEmpty || !p.layers[li].protocols.isEmpty || !p.layers[li].framework.isEmpty {
                    notes.append("\(name) is inductive but had a priori code evidence, protocols or Framework Matrix summaries; they are ignored.")
                    p.layers[li].aprioriEvidence = [:]
                    p.layers[li].protocols = [:]
                    p.layers[li].framework = [:]
                }
                for (file, list) in p.layers[li].selections where list.contains(where: { $0.segment != nil }) {
                    notes.append("\(name) is inductive but had protocol segments; they are plain selections now.")
                    p.layers[li].selections[file] = list.map { s in
                        var s = s
                        s.segment = nil
                        return s
                    }
                }
                // Links to a priori codes that exist.
                for ck in p.layers[li].codes.keys {
                    let links = p.layers[li].codes[ck]!.links
                    let valid = links.filter { p.aprioriCodes[$0.aprioriCode] != nil }
                    if valid.count != links.count {
                        notes.append("\(p.layers[li].codes[ck]!.name) linked to a priori codes that don't exist; those links are ignored.")
                        p.layers[li].codes[ck]!.links = valid
                    }
                }
            }
        }
        if !p.layers.contains(where: { $0.isDeductive }) {
            let key = p.newKey(Keys.layer)
            p.layers.insert(CodingLayer(key: key, kind: .deductive, name: Project.mainDeductiveName), at: 0)
            notes.append("The project had no deductive layer, so \(Project.mainDeductiveName) was added.")
        }
        if !p.layers.contains(where: { $0.isInductive }) {
            let key = p.newKey(Keys.layer)
            p.layers.append(CodingLayer(key: key, kind: .inductive, name: Project.mainInductiveName))
            notes.append("The project had no inductive layer, so \(Project.mainInductiveName) was added.")
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
            case .studyProtocol(let k): text = p.protocols[k].map { emit(encodeProtocol($0)) }
            case .aprioriCode(let k): text = p.aprioriCodes[k].map { emit(encodeAprioriCode($0)) }
            case .attributeSheet(let k): text = p.attributeSheets[k].map { emit(encodeAttributeSheet($0)) }
            case .response(let id):
                text = p.responses[id].map { emit(encodeResponse($0, attributeSheet: p.attributeSheets[id.attributeSheet])) }
            case .layer(let k):
                guard let layer = layers[k] else { continue }
                text = emit(encodeLayer(layer))
            case .selections(let l, let f):
                guard let layer = layers[l] else { continue }
                let list = layer.selections[f] ?? []
                let pr = layer.protocols[f]
                text = list.isEmpty && pr == nil ? nil : emit(encodeSelections(file: f, list, protocolKey: pr))
            case .code(let l, let c):
                guard let layer = layers[l] else { continue }
                text = layer.codes[c].map { emit(encodeCode($0)) }
            case .aprioriEvidence(let l, let c):
                guard let layer = layers[l] else { continue }
                text = layer.aprioriEvidence[c].flatMap { $0.isEmpty ? nil : emit(encodeAprioriEvidence(code: c, $0)) }
            case .framework(let l, let r):
                guard let layer = layers[l] else { continue }
                text = layer.framework[r].flatMap { $0.isEmpty ? nil : emit(encodeFrameworkRow(row: r, $0)) }
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

import AppKit
import EmpiricsCore
import SwiftUI

// Pages of single items, opened from the tables (double-click) and kept in
// the sidebar's Working Area.

// MARK: - Code

/// An open or axial code's page: its evidence. The inspector holds the
/// code itself (name, description, comments, questions, interrelations…).
struct CodePage: View {
    @Environment(AppModel.self) private var model
    let codeKey: String

    var body: some View {
        if let code = model.project.code(codeKey) {
            EvidencePane(code: code)
        } else {
            ContentUnavailableView("Open or Axial Code Deleted", systemImage: "tag.slash")
        }
    }
}

// MARK: - Codebook

struct CodebookPage: View {
    @Environment(AppModel.self) private var model
    let codebookKey: String

    var body: some View {
        if let cb = model.project.codebooks[codebookKey] {
            CodebookEditor(codebook: cb, delete: { model.deleteCodebook(codebookKey) })
        } else {
            ContentUnavailableView("Codebook Deleted", systemImage: "text.book.closed")
        }
    }
}

/// The inspector for a codebook chosen in the table: its title, what it
/// applies to, and its questions at a glance.
struct CodebookSummary: View {
    @Environment(AppModel.self) private var model
    let codebookKey: String

    var body: some View {
        if let cb = model.project.codebooks[codebookKey] {
            VStack(alignment: .leading, spacing: 12) {
                InspectorTitle(model: model, title: "Codebook", key: codebookKey)
                TextField("Title", text: Binding(get: { model.project.codebooks[codebookKey]?.title ?? "" },
                                                 set: { v in model.edit { $0.codebooks[codebookKey]?.title = v } }))
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                TextField("Description", text: Binding(get: { model.project.codebooks[codebookKey]?.description ?? "" },
                                                       set: { v in model.edit { $0.codebooks[codebookKey]?.description = v } }),
                          axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
                SectionHeader(title: "Applies To")
                ForEach(CodebookTarget.allCases, id: \.self) { t in
                    Toggle(t.label, isOn: Binding(get: { cb.appliesTo.contains(t) }, set: { on in
                        model.perform("Change Codebook") { p in
                            if on { p.codebooks[codebookKey]?.appliesTo.insert(t) } else { p.codebooks[codebookKey]?.appliesTo.remove(t) }
                        }
                    }))
                    .toggleStyle(.checkbox)
                }
                SectionHeader(title: "Questions", trailing: "\(cb.questions.count)")
                ForEach(Array(cb.questions.enumerated()), id: \.element.key) { i, q in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(i + 1).").foregroundStyle(.secondary).monospacedDigit()
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text(q.label).fontWeight(.medium)
                                RequirementMark(requirement: q.requirement)
                            }
                            Text(q.type.label + (q.type.usesOptions ? " · \(q.options.count) options" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button("Edit Questions…") { model.show(.codebook(codebookKey)) }
                    if model.sidebar != .codebookReport {
                        Button("Show Report") {
                            model.reportCodebook = codebookKey
                            model.sidebar = .codebookReport
                        }
                    }
                }
                Divider()
                CodebookUsage(codebookKey: codebookKey)
            }
        }
    }
}

/// Where a codebook is used, and how far this Mac's researcher has got.
struct CodebookUsage: View {
    @Environment(AppModel.self) private var model
    let codebookKey: String

    var body: some View {
        let files = model.project.sortedFiles.filter { $0.codebooks.contains(codebookKey) }
        let codes = model.project.layers.flatMap { Array($0.codes.values) }.filter { $0.codebooks.contains(codebookKey) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        let people = model.project.interviewees.filter { $0.codebooks.contains(codebookKey) }
            .sorted { model.itemTitle($0.key).localizedStandardCompare(model.itemTitle($1.key)) == .orderedAscending }
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Associated With", trailing: "\(files.count + people.count + codes.count)")
            if files.isEmpty && people.isEmpty && codes.isEmpty {
                Text("Nothing yet. Add it from the inspector of an empirical file, interviewee, open code or axial code.").font(.callout).foregroundStyle(.secondary)
            }
            ForEach(files) { f in
                usageRow(target: f.key)
            }
            ForEach(people) { i in
                usageRow(target: i.key)
            }
            ForEach(codes) { c in
                usageRow(target: c.key)
            }
            if model.sidebar == .codebook(codebookKey) {
                Button("Show Report") {
                    model.reportCodebook = codebookKey
                    model.sidebar = .codebookReport
                }
                .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    func usageRow(target: String) -> some View {
        let cb = model.project.codebooks[codebookKey]
        let mine = model.responseID(codebook: codebookKey, target: target).flatMap { model.project.responses[$0] }
        let complete = cb.map { SheetCompleteness.of(mine?.answers ?? [:], against: $0).isComplete } ?? false
        HStack(spacing: 6) {
            Image(systemName: mine == nil ? "circle.dashed" : complete ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(mine == nil ? Color.secondary : complete ? Color.green : Color.orange)
            Button {
                model.openKey(target)
            } label: {
                ItemLine(model: model, key: target, iconWidth: 16)
            }
            .buttonStyle(.plain)
            Button(mine == nil ? "Fill In…" : "Edit…") { model.openResponseSheet(codebook: codebookKey, target: target) }
                .controlSize(.small)
        }
    }
}

// MARK: - People

enum PersonKind {
    case researcher
    case interviewee
}

/// A researcher's or interviewee's card, laid out like a contact in the
/// Contacts app: a monogram and the name above, labelled fields below.
struct PersonForm: View {
    @Environment(AppModel.self) private var model
    let key: String
    var compact = false

    var kind: PersonKind? {
        if model.project.researcher(key) != nil { return .researcher }
        if model.project.interviewee(key) != nil { return .interviewee }
        return nil
    }

    var first: String {
        model.project.researcher(key)?.firstName ?? model.project.interviewee(key)?.firstName ?? ""
    }

    var last: String {
        model.project.researcher(key)?.lastName ?? model.project.interviewee(key)?.lastName ?? ""
    }

    func setName(first newFirst: String? = nil, last newLast: String? = nil) {
        model.edit { p in
            if let i = p.researchers.firstIndex(where: { $0.key == key }) {
                if let newFirst { p.researchers[i].firstName = newFirst }
                if let newLast { p.researchers[i].lastName = newLast }
            } else if let i = p.interviewees.firstIndex(where: { $0.key == key }) {
                if let newFirst { p.interviewees[i].firstName = newFirst }
                if let newLast { p.interviewees[i].lastName = newLast }
            }
        }
    }

    var body: some View {
        if let kind {
            VStack(alignment: .leading, spacing: compact ? 12 : 18) {
                header(kind)
                Divider()
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    GridRow {
                        fieldLabel("first name")
                        TextField("First name", text: Binding(get: { first }, set: { setName(first: $0) }))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        fieldLabel("last name")
                        TextField("Last name", text: Binding(get: { last }, set: { setName(last: $0) }))
                            .textFieldStyle(.roundedBorder)
                    }
                    GridRow {
                        fieldLabel("")
                        Text("A pseudonym: it is saved in the workspace, which is shared through Git.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    GridRow {
                        fieldLabel("real name")
                        realName
                    }
                    if kind == .interviewee {
                        GridRow {
                            fieldLabel("consent form")
                            consent
                        }
                    } else {
                        GridRow {
                            fieldLabel("this Mac")
                            Toggle("This is me on this Mac", isOn: Binding(
                                get: { model.currentResearcher == key },
                                set: { model.setCurrentResearcher($0 ? key : nil) }
                            ))
                            .toggleStyle(.checkbox)
                        }
                    }
                    GridRow {
                        fieldLabel("key")
                        Text(key).font(.callout.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                }
                if !compact {
                    Divider()
                    PersonRelated(key: key)
                } else {
                    if kind == .interviewee {
                        SectionHeader(title: "Codebooks")
                        CodebookAssociations(target: key, kind: .interviewees)
                    }
                    Button("Open") { model.show(kind == .researcher ? SidebarItem.researcher(key) : SidebarItem.interviewee(key)) }
                        .controlSize(.small)
                }
            }
        } else {
            ContentUnavailableView("Not Found", systemImage: "person.crop.circle.badge.questionmark")
        }
    }

    func header(_ kind: PersonKind) -> some View {
        HStack(spacing: 16) {
            Monogram(first: first, last: last, kind: kind, size: compact ? 52 : 84)
            VStack(alignment: .leading, spacing: 3) {
                Text(model.personName(key) ?? "Unnamed")
                    .font(compact ? .title2.weight(.semibold) : .largeTitle.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    Text(kind == .researcher ? "Researcher" : "Interviewee")
                        .foregroundStyle(.secondary)
                    WorkingBadge(text: model.wid(key), color: nil)
                }
                if model.showRealNames, model.realNames[key] != nil {
                    Text("Pseudonym: " + [first, last].filter { !$0.isEmpty }.joined(separator: " "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    func fieldLabel(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(width: compact ? 74 : 110, alignment: .trailing)
            .gridColumnAlignment(.trailing)
    }

    @ViewBuilder
    var realName: some View {
        if let real = model.realNames[key] {
            if model.showRealNames {
                Text(real).textSelection(.enabled)
            } else {
                HStack {
                    Text("Hidden").foregroundStyle(.tertiary)
                    Button("Show Real Names") { model.showRealNames = true }
                        .controlSize(.small)
                }
            }
        } else if model.hasRealNameFiles {
            Text("Not in the mapping file").foregroundStyle(.tertiary)
        } else {
            Button("Set Up Mapping File…") { model.sidebar = .settings }
                .controlSize(.small)
        }
    }

    @ViewBuilder
    var consent: some View {
        if let i = model.project.interviewee(key) {
            VStack(alignment: .leading, spacing: 4) {
                if i.consentForm.isEmpty {
                    Button("Choose Consent Form…") { model.chooseConsentForm(for: key) }
                        .controlSize(.small)
                } else {
                    ConsentStatus(model: model, interviewee: i)
                    Text(i.consentForm).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    HStack {
                        Button("View") { model.sheet = .consent(key) }
                        Button("Change…") { model.chooseConsentForm(for: key) }
                        Button("Remove Link") {
                            model.perform("Remove Consent Form") { p in
                                if let x = p.interviewees.firstIndex(where: { $0.key == key }) { p.interviewees[x].consentForm = "" }
                            }
                        }
                    }
                    .controlSize(.small)
                }
            }
        }
    }
}

/// Initials in a circle, as in Contacts: blue for researchers, green for
/// interviewees.
struct Monogram: View {
    var first: String
    var last: String
    var kind: PersonKind
    var size: CGFloat

    var body: some View {
        let initials = String(first.prefix(1) + last.prefix(1)).uppercased()
        // Greyscale, as in Contacts, and like speakers in the text:
        // interviewees darker, researchers lighter.
        let base = Color(white: kind == .researcher ? 0.62 : 0.38)
        ZStack {
            Circle().fill(LinearGradient(colors: [base.opacity(0.75), base], startPoint: .top, endPoint: .bottom))
            if initials.isEmpty {
                Image(systemName: "person.fill").font(.system(size: size * 0.45)).foregroundStyle(.white)
            } else {
                Text(initials).font(.system(size: size * 0.4, weight: .medium, design: .rounded)).foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
    }
}

/// What a person is linked to: transcripts they speak in; for researchers,
/// their layers and response sheets.
struct PersonRelated: View {
    @Environment(AppModel.self) private var model
    let key: String

    var body: some View {
        let transcripts = model.transcripts(of: key)
        VStack(alignment: .leading, spacing: 8) {
            if model.project.interviewee(key) != nil {
                SectionHeader(title: "Codebooks")
                CodebookAssociations(target: key, kind: .interviewees)
            }
            SectionHeader(title: "Speaks In", trailing: transcripts.isEmpty ? nil : "\(transcripts.count)")
            if transcripts.isEmpty {
                Text("No transcripts. Assign speakers in a file's inspector (Interlocutor layer).")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(transcripts) { f in
                Button {
                    model.show(.file(f.key))
                } label: {
                    Label(f.displayTitle, systemImage: f.kind.symbol)
                }
                .buttonStyle(.link)
            }
            if model.project.researcher(key) != nil {
                let layers = model.project.layers.filter { $0.researcher == key }
                let sheets = model.project.responses.keys.filter { $0.researcher == key }.count
                let selections = model.project.layers.reduce(0) { n, l in n + l.allSelections.filter { $0.by == key }.count }
                SectionHeader(title: "Work")
                Text("\(selections) selection\(selections == 1 ? "" : "s") · \(sheets) response sheet\(sheets == 1 ? "" : "s")")
                    .font(.callout).foregroundStyle(.secondary)
                if !layers.isEmpty {
                    Text("Layers: " + layers.map(\.name).joined(separator: ", ")).font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// A researcher's or interviewee's page.
struct PersonPage: View {
    let key: String

    var body: some View {
        ScrollView {
            PersonForm(key: key)
                .padding(28)
                .frame(maxWidth: 640, alignment: .leading)
                .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

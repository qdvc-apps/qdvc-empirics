import AppKit
import EmpiricsCore
import SwiftUI

// One way of showing any item (empirical file, attribute sheet, open code, axial
// code, researcher, interviewee) on a single line: a neutral icon, its title
// and its working-identifier badge ("EF 3", "OC 12"…). Used in the Working
// Area, the Coding Chart, the Attribute Sheet Report and the inspector headers.

extension AppModel {
    /// The item's symbol (always drawn in one neutral colour).
    func itemSymbol(_ key: String) -> String {
        if let f = project.files[key] { return f.kind.symbol }
        if let c = project.code(key) { return c.kind.symbol }
        if project.attributeSheets[key] != nil { return "text.book.closed" }
        if project.protocols[key] != nil { return "list.bullet.rectangle" }
        if project.aprioriCodes[key] != nil { return "character.book.closed" }
        if project.researcher(key) != nil { return "graduationcap" }
        if project.interviewee(key) != nil { return "person.bubble" }
        return "questionmark.circle"
    }

    /// The item's title or (shown) name.
    func itemTitle(_ key: String) -> String {
        if let f = project.files[key] { return f.displayTitle }
        if let c = project.code(key) { return c.name.isEmpty ? "Untitled" : c.name }
        if let cb = project.attributeSheets[key] { return cb.title.isEmpty ? "Untitled" : cb.title }
        if let pr = project.protocols[key] { return pr.title.isEmpty ? "Untitled" : pr.title }
        if let apc = project.aprioriCodes[key] { return apc.name.isEmpty ? "Untitled" : apc.name }
        if let name = personName(key) { return name }
        return ""
    }

    /// The item's title, with people always by pseudonym whatever View ›
    /// Show Real Names says: for anything that leaves the app (CSV).
    func pseudonymousTitle(_ key: String) -> String {
        if let name = project.personName(key) { return name.isEmpty ? "Unnamed" : name }
        return itemTitle(key)
    }

    /// What kind of item it is, in words ("Open Code", "Empirical File"…).
    func itemKind(_ key: String) -> String {
        if project.files[key] != nil { return "Empirical File" }
        if let c = project.code(key) { return c.kind == .open ? "Open Code" : "Axial Code" }
        if project.attributeSheets[key] != nil { return "Attribute Sheet" }
        if project.protocols[key] != nil { return "Protocol" }
        if project.aprioriCodes[key] != nil { return "A Priori Code" }
        if project.researcher(key) != nil { return "Researcher" }
        if project.interviewee(key) != nil { return "Interviewee" }
        return ""
    }

    /// The badge colour: a code's own colour; a file's coding status (grey
    /// not started, orange in progress, green coded); nil for the rest.
    func itemAccent(_ key: String) -> Color? {
        if let f = project.files[key] { return f.status == .notStarted ? nil : f.status.tint }
        if let c = project.code(key) { return c.color }
        if let apc = project.aprioriCodes[key] { return apc.color }
        return nil
    }

    /// Titles of the attribute sheets associated with a file, code or interviewee,
    /// for the Attribute Sheets columns.
    func attributeSheetTitles(_ key: String) -> String {
        project.attributeSheets(for: key).map(\.title)
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            .joined(separator: ", ")
    }

    /// The attribute sheet the Attribute Sheet Report shows: the one chosen, or the first.
    var shownReportAttributeSheet: String? {
        reportAttributeSheet.flatMap { project.attributeSheets[$0] != nil ? $0 : nil } ?? project.sortedAttributeSheets.first?.key
    }

    /// "3 open codes and 1 axial code", for counts in sentences.
    func codeCounts(_ keys: [String]) -> String {
        let codes = keys.compactMap { project.code($0) }
        return Self.codeCounts(open: codes.filter { $0.kind == .open }.count, axial: codes.filter { $0.kind == .axial }.count)
    }

    nonisolated static func codeCounts(open: Int, axial: Int) -> String {
        "\(open) open code\(open == 1 ? "" : "s") and \(axial) axial code\(axial == 1 ? "" : "s")"
    }

    /// "OC 12 Fatigue": for menus and other places that take plain text.
    func itemLabel(_ key: String) -> String {
        let id = wid(key)
        return id.isEmpty ? itemTitle(key) : "\(id)  \(itemTitle(key))"
    }
}

/// A working identifier ("OC 12") as a small capsule, tinted with the
/// item's colour when it has one.
struct WorkingBadge: View {
    var text: String
    var color: Color?

    var body: some View {
        if !text.isEmpty {
            Text(text)
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(Capsule().fill((color ?? .secondary).opacity(color == nil ? 0.14 : 0.30)))
                .overlay(Capsule().strokeBorder((color ?? .secondary).opacity(color == nil ? 0.25 : 0.75), lineWidth: 1))
                .help("Working identifier: numbered alphabetically, so it can change as items are added, renamed or removed")
        }
    }
}

/// The working identifier in a table cell (the "No." column).
struct WorkingIDCell: View {
    let model: AppModel
    var key: String

    var body: some View {
        WorkingBadge(text: model.wid(key), color: model.itemAccent(key))
    }
}

/// An item on exactly one line: icon (fixed width, neutral colour), title
/// (truncated), and the working-identifier badge on the right.
struct ItemLine: View {
    let model: AppModel
    var key: String
    var iconWidth: CGFloat = 18
    var badge = true

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.itemSymbol(key))
                .foregroundStyle(.secondary)
                .frame(width: iconWidth, alignment: .center)
            Text(model.itemTitle(key))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            if badge {
                WorkingBadge(text: model.wid(key), color: model.itemAccent(key))
            }
        }
        .help("\(model.itemKind(key)): \(model.itemTitle(key))")
    }
}

/// The heading of an inspector for one item: its kind, its working
/// identifier, and an optional note on the right (a layer, a file kind).
struct InspectorTitle: View {
    let model: AppModel
    var title: String
    var key: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            WorkingBadge(text: model.wid(key), color: model.itemAccent(key))
            Spacer(minLength: 4)
            if let trailing { Text(trailing).font(.caption).foregroundStyle(.tertiary).lineLimit(1) }
        }
    }
}

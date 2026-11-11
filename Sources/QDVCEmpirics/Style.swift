import AppKit
import EmpiricsCore
import SwiftUI

// MARK: - Colours

extension NSColor {
    /// "#RRGGBB" (or "RRGGBB"); nil if malformed.
    static func hex(_ s: String) -> NSColor? {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("#") { t.removeFirst() }
        guard t.count == 6, let v = UInt32(t, radix: 16) else { return nil }
        return NSColor(srgbRed: CGFloat((v >> 16) & 0xff) / 255, green: CGFloat((v >> 8) & 0xff) / 255,
                       blue: CGFloat(v & 0xff) / 255, alpha: 1)
    }

    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(round(c.redComponent * 255)), Int(round(c.greenComponent * 255)),
                      Int(round(c.blueComponent * 255)))
    }
}

extension QDACode {
    var nsColor: NSColor { NSColor.hex(colour) ?? .systemYellow }
    var color: Color { Color(nsColor: nsColor) }
}

extension CodingStatus {
    var symbol: String {
        switch self {
        case .notStarted: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .coded: return "checkmark.circle.fill"
        }
    }

    var tint: Color {
        switch self {
        case .notStarted: return .secondary
        case .inProgress: return .orange
        case .coded: return .green
        }
    }
}

extension FileKind {
    var symbol: String {
        switch self {
        case .text: return "doc.plaintext"
        case .markdown: return "doc.text"
        case .pdf: return "doc.richtext"
        }
    }
}

extension CodeKind {
    var symbol: String { self == .open ? "tag" : "point.3.connected.trianglepath.dotted" }
}

/// A small filled circle in a code's colour.
struct CodeDot: View {
    var color: Color
    var size: CGFloat = 9

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.5))
    }
}

/// A code as a rounded chip: dot, name, and an optional quick-code number.
struct CodeChip: View {
    var code: QDACode
    var slot: Int?
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            if let slot {
                Text("\(slot)")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 14)
                    .background(RoundedRectangle(cornerRadius: 3).fill(Color.primary.opacity(0.08)))
            }
            CodeDot(color: code.color, size: compact ? 7 : 9)
            Text(code.name).lineLimit(1).truncationMode(.tail)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(code.color.opacity(0.16)))
        .overlay(Capsule().strokeBorder(code.color.opacity(0.45), lineWidth: 0.5))
    }
}

/// A requirement marker for codebook questions: red for blocking, orange
/// for flagged.
struct RequirementMark: View {
    var requirement: Requirement

    var body: some View {
        switch requirement {
        case .blocking:
            Image(systemName: "asterisk").font(.system(size: 9, weight: .bold)).foregroundStyle(.red)
                .help("Mandatory: the sheet can't be saved without an answer")
        case .flagged:
            Image(systemName: "asterisk").font(.system(size: 9, weight: .bold)).foregroundStyle(.orange)
                .help("Mandatory, but the sheet can be saved without it (it stays flagged)")
        case .optional:
            EmptyView()
        }
    }
}

/// A transient message at the top of the window.
struct NoticeBanner: View {
    var notice: Notice
    var dismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: notice.isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .foregroundStyle(notice.isWarning ? Color.orange : Color.accentColor)
            Text(notice.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            if let action = notice.action {
                Button(action.title) {
                    action.perform()
                    dismiss()
                }
                .controlSize(.small)
            }
            Button("Dismiss", action: dismiss).buttonStyle(.borderless).controlSize(.small)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct NoticeAction {
    var title: String
    var perform: () -> Void
}

struct Notice: Identifiable {
    let id = UUID()
    var text: String
    var isWarning = false
    var action: NoticeAction?
}

/// A section heading in the inspector and pages.
struct SectionHeader: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Spacer()
            if let trailing { Text(trailing).font(.caption).foregroundStyle(.tertiary) }
        }
    }
}

/// A quote from a full-text, set apart like a block quote.
struct QuoteBlock: View {
    var text: String
    var color: Color = .accentColor
    var lineLimit: Int?

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1.5).fill(color.opacity(0.7)).frame(width: 3)
            Text(text)
                .font(.system(.body, design: .serif))
                .lineLimit(lineLimit)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Pop-up buttons (as in QDVC Response Letter)

/// A choice in a PopUpButton.
struct PopUpItem {
    var title: String
    var image: NSImage?
    var checked: Bool = false
    var enabled: Bool = true
    var action: () -> Void
}

/// A button with any label that pops up an AppKit menu. (A SwiftUI Menu's
/// label on macOS shows only text and SF Symbols, so a drawn colour dot in
/// it simply disappears.)
struct PopUpButton<Label: View>: View {
    var items: () -> [PopUpItem]
    @ViewBuilder var label: () -> Label

    var body: some View {
        Button(action: popUp) {
            label().contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @MainActor
    private func popUp() {
        guard let event = NSApp.currentEvent, let view = event.window?.contentView else { return }
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in items() {
            let menuItem = ClosureMenuItem(title: item.title, handler: item.action)
            menuItem.image = item.image
            menuItem.state = item.checked ? .on : .off
            menuItem.isEnabled = item.enabled
            menu.addItem(menuItem)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }
}

final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(fire), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError("not used") }

    @objc private func fire() { handler() }
}

/// A coloured dot as a small image, for AppKit menus.
@MainActor
func dotImage(_ color: NSColor, size: CGFloat = 10) -> NSImage {
    NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        color.setFill()
        NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
        return true
    }
}

// MARK: - Layout helpers (as in QDVC Response Letter, docs/MAINTENANCE.md §2.3)

/// A centred column of at most `maxWidth` points on the text background,
/// for running text: long lines are hard to read, however wide the window.
struct ReadableColumn<Content: View>: View {
    var maxWidth: CGFloat
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            content()
                .frame(width: min(geo.size.width, maxWidth), height: geo.size.height)
                .clipped()
                .frame(width: geo.size.width, height: geo.size.height)
                .background(Color(nsColor: .textBackgroundColor))
        }
    }
}

/// A vertical SwiftUI scroll view around a self-sizing text view: the text
/// view gets exactly the width available and at least the visible height.
struct FillingScroll<Content: View>: View {
    var padding: CGFloat = 0
    @ViewBuilder var content: () -> Content

    var body: some View {
        GeometryReader { geo in
            ScrollView(.vertical) {
                content()
                    .frame(width: max(0, geo.size.width - 2 * padding))
                    .frame(minHeight: geo.size.height, alignment: .top)
                    .padding(.horizontal, padding)
            }
        }
    }
}

/// An editable list of short texts (comments, questions, options), one
/// field per line, with add and remove buttons.
struct StringListEditor: View {
    var items: [String]
    var placeholder: String
    var addTitle: String
    var multiline = true
    var onChange: ([String]) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                HStack(alignment: .top, spacing: 6) {
                    if multiline {
                        TextField(placeholder, text: binding(i), axis: .vertical)
                            .lineLimit(1...8)
                            .textFieldStyle(.roundedBorder)
                    } else {
                        TextField(placeholder, text: binding(i))
                            .textFieldStyle(.roundedBorder)
                    }
                    Button {
                        var copy = items
                        copy.remove(at: i)
                        onChange(copy)
                    } label: {
                        Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .help("Remove")
                }
            }
            Button {
                onChange(items + [""])
            } label: {
                Label(addTitle, systemImage: "plus")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
        }
    }

    private func binding(_ i: Int) -> Binding<String> {
        Binding(
            get: { i < items.count ? items[i] : "" },
            set: { v in
                guard i < items.count else { return }
                var copy = items
                copy[i] = v
                onChange(copy)
            }
        )
    }
}

/// Turns off Writing Tools (macOS 15 and later) for everything inside, so
/// no text is ever offered to a model or service from this app.
struct NoWritingTools: ViewModifier {
    func body(content: Content) -> some View {
        #if compiler(>=6.0)
        if #available(macOS 15.0, *) {
            content.writingToolsBehavior(.disabled)
        } else {
            content
        }
        #else
        content
        #endif
    }
}

enum Platform {
    /// Opens the Settings window.
    @MainActor
    static func openSettings() {
        _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate()
    }

    /// Removes context-menu items that hand text to other apps or online
    /// services (Look Up, Translate, Search With…, Share, Services, Writing
    /// Tools), so nothing from a full-text leaves the app that way.
    @MainActor
    static func stripOutsideServices(_ menu: NSMenu) {
        let titles = ["Look Up", "Translate", "Search With", "Share", "Services", "Writing Tools", "Show Writing Tools",
                      "Speech", "AutoFill", "Spelling and Grammar", "Substitutions", "Transformations", "Font", "Layout Orientation"]
        let actions = ["lookUp", "translate", "search", "share", "service", "writingTools", "startSpeaking", "_rtfd"]
        for item in menu.items.reversed() {
            let title = item.title
            let action = item.action.map { NSStringFromSelector($0) } ?? ""
            if titles.contains(where: { title.hasPrefix($0) }) || actions.contains(where: { action.localizedCaseInsensitiveContains($0) }) {
                menu.removeItem(item)
            }
        }
        // Tidy separators left at the ends or doubled.
        while menu.items.first?.isSeparatorItem == true { menu.removeItem(at: 0) }
        while menu.items.last?.isSeparatorItem == true { menu.removeItem(at: menu.items.count - 1) }
        var previousWasSeparator = false
        for item in menu.items.reversed() {
            if item.isSeparatorItem && previousWasSeparator { menu.removeItem(item) }
            previousWasSeparator = item.isSeparatorItem
        }
    }
}

import AppKit
import EmpiricsCore
import SwiftUI

/// Editing part of a text file's full-text in place (a typo in a
/// transcript), in two steps: write the new text for the selected part,
/// then confirm saving it to disk, having seen what it does to the
/// selections. Saving writes the file in the full-texts folder and adjusts
/// the workspace (AppModel.saveTextEdit); Edit › Undo writes the previous
/// text back.
struct EditTextSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let fileKey: String
    let start: Int
    let length: Int
    @State private var replacement = ""
    @State private var loaded = false
    @State private var confirming = false

    /// The file's text as shown, if loaded.
    var text: String? { model.pages(fileKey)?.first }

    var original: String? {
        guard let text else { return nil }
        let ns = text as NSString
        guard start >= 0, length >= 0, start + length <= ns.length else { return nil }
        return ns.substring(with: NSRange(location: start, length: length))
    }

    var body: some View {
        let file = model.project.files[fileKey]
        VStack(alignment: .leading, spacing: 14) {
            Text(confirming ? "Save the Edit to Disk?" : "Edit Text").font(.title2.weight(.semibold))
            if let original, let file {
                if confirming {
                    confirmation(original, file: file)
                } else {
                    editor(original, file: file)
                }
            } else {
                Label("That part of the text is no longer there. Close this and select it again.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                HStack {
                    Spacer()
                    Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
                }
            }
        }
        .padding(20)
        .frame(width: 600)
        .onAppear {
            guard !loaded else { return }
            loaded = true
            replacement = original ?? ""
        }
    }

    // MARK: Step 1: the new text

    @ViewBuilder
    func editor(_ original: String, file: EmpiricalFile) -> some View {
        Text("Change the selected text of “\(file.displayTitle)”, to correct a typo say. When you save, the file itself is changed in the full-texts folder, and every layer's selections are adjusted to the new text.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        GroupBox("Now") {
            ScrollView {
                Text(original)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 110)
        }
        VStack(alignment: .leading, spacing: 4) {
            Text("New text").font(.headline)
            TextEditor(text: $replacement)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.secondary.opacity(0.3)))
                .frame(minHeight: 120, maxHeight: 220)
        }
        HStack {
            Text("\((original as NSString).length) → \((replacement as NSString).length) characters")
                .font(.caption).foregroundStyle(.secondary).monospacedDigit()
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Continue…") { confirming = true }
                .keyboardShortcut(.defaultAction)
                .disabled(replacement == original)
        }
    }

    // MARK: Step 2: confirm

    @ViewBuilder
    func confirmation(_ original: String, file: EmpiricalFile) -> some View {
        let impact = model.project.textEditImpact(file: fileKey, start: start, length: length, replacement: replacement)
        HStack(alignment: .top, spacing: 12) {
            GroupBox("Before") { snippet(original, deleted: true) }
            GroupBox("After") { snippet(replacement, deleted: false) }
        }
        VStack(alignment: .leading, spacing: 6) {
            if impact.isEmpty {
                Label("No selection is affected.", systemImage: "checkmark.circle")
            } else {
                if impact.resized > 0 {
                    Label("\(impact.resized) selection\(impact.resized == 1 ? "" : "s") overlapping the edit will take in the new text.",
                          systemImage: "arrow.left.and.right.text.vertical")
                }
                if impact.moved > 0 {
                    Label("\(impact.moved) selection\(impact.moved == 1 ? "" : "s") after it will move with the text.",
                          systemImage: "arrow.down.to.line")
                }
                if !impact.emptied.isEmpty {
                    Label("\(impact.emptied.count) selection\(impact.emptied.count == 1 ? "" : "s") would have no text left and will be deleted, with \(impact.emptied.count == 1 ? "its" : "their") memos.",
                          systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
            }
        }
        .font(.callout)
        GroupBox {
            Label {
                (Text("This overwrites ") + Text(file.path).bold()
                    + Text(" in the full-texts folder (kept in its encoding and line endings), and updates the workspace to match: selections in every layer, their quotes and the file's fingerprint. Edit › Undo writes the previous text back while the project is open. The full-texts aren't in Git, so keep a backup of them if you may need older versions later."))
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "square.and.pencil").foregroundStyle(.orange)
            }
            .padding(4)
        }
        HStack {
            Button("Back") { confirming = false }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Save to Disk") {
                if model.saveTextEdit(file: fileKey, start: start, length: length, replacement: replacement) {
                    model.clearTextSelection()
                    dismiss()
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    func snippet(_ s: String, deleted: Bool) -> some View {
        ScrollView {
            Text(s.isEmpty ? "(nothing)" : s)
                .foregroundStyle(s.isEmpty ? Color.secondary : (deleted ? Color.red.opacity(0.85) : Color.green.opacity(0.9)))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: 120)
    }
}

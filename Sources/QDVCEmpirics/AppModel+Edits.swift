import AppKit
import EmpiricsCore
import SwiftUI

// Edits that follow the full-text: correcting a text file in place (the
// sheet is EditTextSheet; saving is AppModel.saveTextEdit, which writes the
// file), turning PDF pages, and merging two selections next to each other
// that are coded the same way (offered, never done automatically).
extension AppModel {

    // MARK: Editing text

    /// The text selected in a text file can be edited in place: one run of
    /// text, in a text or Markdown file whose full-text is at hand.
    var canEditTextSelection: Bool {
        guard hasTextSelection, textSelection.count == 1, let file = textSelectionFile,
              project.files[file]?.kind.isText == true, fullTexts != nil else { return false }
        return true
    }

    /// Opens the sheet to edit the selected text.
    func editSelectedText() {
        guard canEditTextSelection, let file = textSelectionFile, let span = textSelection.first else { return }
        paletteVisible = false
        protocolPalette = nil
        sheet = .editText(file: file, start: span.start, length: span.length)
    }

    // MARK: Turning PDF pages

    func rotatePage(file: String, page: Int, by degrees: Int) {
        perform(degrees < 0 ? "Rotate Page Left" : "Rotate Page Right") { p in
            p.rotatePage(file: file, page: page, by: degrees)
        }
    }

    func resetPageRotation(file: String, page: Int) {
        perform("Show Page Unrotated") { p in p.resetPageRotation(file: file, page: page) }
    }

    // MARK: Merging selections

    /// The selections the given one could be merged with (next to it, coded
    /// the same way).
    func mergeCandidates(for key: String) -> [String] {
        guard let file = index.fileOf[key], let pages = pages(file) else { return [] }
        return project.mergeCandidates(for: key, pages: pages)
    }

    /// "Merge with Previous Selection" or "Merge with Next Selection".
    func mergeTitle(_ key: String, _ other: String) -> String {
        guard let a = project.selection(key)?.first, let b = project.selection(other)?.first else { return "Merge Selections" }
        return b < a ? "Merge with Previous Selection" : "Merge with Next Selection"
    }

    /// Merges two selections next to each other and coded the same way into
    /// one (their memos joined), and focuses it.
    func mergeSelections(_ key: String, _ other: String) {
        guard let file = index.fileOf[key], let pages = pages(file) else { return }
        var merged: String?
        let ok = perform("Merge Selections") { p in merged = try p.mergeSelections(key, other, pages: pages) }
        guard ok, let merged else { return }
        for k in [key, other] where k != merged { lostSelections.remove(k) }
        focusedSelection = merged
        inspectorTab = .selection
    }
}

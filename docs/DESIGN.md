# QDVC Empirics — Design Notes

## The long session comes first

Researchers code for hours at a time. The coding view is designed so that
the common path needs no mouse and no dialogs, and so that nothing moves
unexpectedly:

- **Reading comfort.** A centred column (720 pt by default) on the text
  background, a serif reading font (New York), 1.35 line spacing and
  paragraph spacing; all adjustable (Settings › Reading) and remembered on
  this Mac. Highlights are pale (28 %) by default and stronger only for the
  focused selection; irrelevant text is dimmed, not struck through.
- **One gesture per step.** Select (drag, or T / P / S for turn, paragraph,
  sentence), then Return and a few letters, or one digit. After coding, the
  new selection stays focused, so Return again adds a second code. Esc
  clears; Delete removes; ] and [ step through selections.
- **Stable quick codes.** Quick codes 1–9 are slots, not a recently-used
  list: the first nine codes used take a slot and keep it until reassigned.
  A most-recently-used order would move numbers under the fingers, the very
  kind of small friction that accumulates over a session.
- **The next action is always visible.** The coding bar under the document
  changes with what is selected: the selected text's actions; a focused
  selection's codes; or a hint. Quick codes are always on the right.
- **No modal interruptions while coding.** Rule refusals (irrelevant
  overlaps, cycles) show as a banner and a beep, not an alert; information
  banners dismiss themselves after a few seconds.
- **Everything undoes.** Every structural change is one step of Edit › Undo.
- **Resume.** Each file reopens at the place you left it; the project
  reopens at the last file.

## Windows and layout

Welcome window at launch, as in Xcode and the other QDVC apps. The main
window is a standard NavigationSplitView (sidebar, detail) with a standard
inspector, so it picks up Liquid Glass on macOS 26 without custom chrome.

- **Sidebar.** Analysis pages (Codes, Codebooks, People, Layers, Project)
  above the empirical files. Files show their status (Not Started, In
  Progress, Coded), ID, date, kind and selection count; a progress bar and a
  filter field sit at the bottom.
- **Document.** Text in a readable column, the Interlocutor layer's speaker
  names in a left margin (researchers blue, interviewees green), coding
  stripes in a right margin, and the coding bar below. The code palette
  floats at the top, like Spotlight.
- **Inspector.** Selection (quote, speaker, codes with interpretation memos),
  Code (name, kind, colour, quick-code slot, description, evidence,
  "evidence for", comments, questions, interrelations, codebooks) and File
  (title, ID, date, status, location, fingerprint, codebooks, speakers).

## Text documents

An NSTextView on TextKit 1, read-only and selectable, sized by SwiftUI
(`sizeThatFits`) inside a SwiftUI ScrollView, exactly as QDVC Response
Letter's decision letter (its docs/MAINTENANCE.md §2.3 explains why: an
NSTextView in an NSScrollView hosted in SwiftUI ends up wider than the
window). Highlights, dimming, underlines and speaker colours are temporary
attributes of the layout manager, so the text storage is never touched by
coding. Overlapping selections are drawn as elementary segments coloured by
their innermost selection and a little stronger where they overlap, found by
a sweep over start and end points. Margins are SwiftUI views placed from the
layout manager's line fragments, recomputed only when the text, width or
decorations change.

Markdown is shown as its source (offsets are into the file's text), with
headings in bold.

## PDFs

Coded on their own pages with PDFKit, as asked. Selections are page and
character ranges in PDFKit's page text (`PDFPage.string`), so they survive
zooming and re-flowing. Highlights are drawn with
`PDFView.highlightedSelections`: no annotations are added, the document is
never modified, and it is loaded from memory (`PDFDocument(data:)`), so
nothing could be written back to the file. Links in PDFs are never followed
(`pdfViewWillClick(onLink:with:)` does nothing).

## Data security

- The workspace and full-texts are separate folders and may not be nested
  either way (checked when creating a project or choosing the folder).
- Full-texts are only read: `FullTexts` in the core has no write method; the
  app is sandboxed, and the full-texts folder's security-scoped bookmark is
  read-only, so after the session in which it was chosen macOS refuses any
  write there. Consent forms are viewed inside the app (never handed to
  Preview, which could save them).
- Where the full-texts are, and who the researcher is, are remembered per
  project per Mac (UserDefaults in the sandbox container), never in the
  workspace; Settings › Privacy shows and forgets them.
- Interviewee names are pseudonyms; People says so, and the YAML file says so
  in a comment.
- No network: no network entitlement, no dependencies, no networking API
  (checked by a unit test), no link following, outside-service menu items
  removed, Writing Tools disabled.

## Change detection

Each empirical file records a SHA-256 fingerprint. On opening a file whose
fingerprint differs, every selection in every layer is checked against the
new text: unchanged, found again by its quote (nearest the old position) and
moved, or lost (flagged in the inspector and on its quote cards, to resize or
delete). Without stored quotes, a selection is kept if it still fits, and the
banner warns that positions may now be off.

## Layers

A selection or code exists in one layer. Evidence, interrelations and
irrelevance are per layer, so two researchers (or two lenses) can read the
same transcript differently. Moving anything to another layer moves its
connected component (selections ↔ open codes ↔ axial codes), with a sheet
saying how much will move; it is refused if a moved selection would overlap
text of the other kind (irrelevant or not) in the target layer.

The Interlocutor layer is not a coding layer: it is derived from the text
(speaker header lines) plus a per-file mapping of labels to people.

## Choices worth revisiting

- An uncoded selection (Highlight Only) counts as potential evidence for the
  irrelevance rule: irrelevant text may not overlap any selection that is
  not irrelevant.
- A selection may be evidence for several open codes, and selections may
  overlap.
- Irrelevant selections that touch or overlap merge into one.
- New codes take the least-used colour of the palette.
- Response sheets are per researcher when the project lists researchers;
  otherwise there is one sheet per codebook and item.
- Removing a file from the project removes its selections in every layer;
  the full-text is untouched.

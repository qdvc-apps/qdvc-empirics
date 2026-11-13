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

- **Sidebar.** Four sections, in the spirit of Mail's mailboxes above its
  smart mailboxes: *Project* (Empirical Files, Researchers, Interviewees,
  Project Settings), *Analysis* (Codebooks, Open Codes, Axial Codes,
  Layers), *Reporting* (Coding Chart, Codebook Report), and the *Working
  Area*: the items being worked on, like open documents, one line each
  (neutral icon, title, working-identifier badge; colour only in the badge). Double-clicking a row in any table opens its page and puts it
  there; it is kept on this Mac (reorder from the context menu). Moving to the
  next file (⌥⌘], ⌥⌘N) swaps the file in its place, so a session of coding
  file after file doesn't fill the Working Area. A progress bar of coded
  files sits at the bottom.
- **List pages** are plain tables (sortable columns, a filter, add buttons
  in a bar at the bottom), as in Finder's list view: selecting a row shows
  it in the inspector, double-clicking opens it. Each page starts with its
  table; nothing sits above it (docs/MAINTENANCE.md §Layout). The tables of
  items codebooks apply to (files, interviewees, open and axial codes) can
  show codebook questions as columns, chosen by right-clicking a column
  heading (SwiftUI column customization, in which only the question columns
  take part, so the menu lists just them; the columns come from
  `TableColumnForEach`, which is why the app needs macOS 14.4). The choice is saved in the
  workspace (`table_columns` in project.yml), so a team sees the same
  columns, and is on Edit › Undo; widths and column order last the session.
  A cell shows the answer when all who answered agree, otherwise each
  answer with its researchers' initials, in orange, and everyone's answer in
  the tooltip: disagreement between coders is the thing to notice.
- **Item pages.** An empirical file (the document), a code (its evidence), a
  codebook (its questions), a person (a card laid out like Contacts, with a
  monogram, labelled fields and the transcripts they speak in).
- **Back and Forward** in the Go menu (⌃⌘← / ⌃⌘→), as in Finder and
  Safari, since following a code from a quote and back is a common move.
- **Document.** Text in a readable column, the Interlocutor layer's speaker
  names in a left margin (greyscale: interviewees dark, interviewers lighter),
  coding stripes in a right margin (dashed grey for irrelevant text), open
  code labels beside them when there is room (in the stripe's colour: the
  working identifiers on the first line, then the names in bold, wrapped so
  they show whole), and the coding bar below. Irrelevant text is greyed out
  whole, in the same faint grey, including the speaker header and margin
  name of a turn whose words are all irrelevant. The
  code palette floats at the top, like Spotlight. The page shares its width
  in a fixed order of sacrifice (`ColumnLayout`): outer margins, then a
  quarter of the text width, then the code names, then the speaker margin,
  then the text; the coding bar falls back to compact and minimal variants.
  Nothing on any page may ask for more width than the detail column gives
  it, so the sidebar is never pushed off the window.
- **Working identifiers.** `EF`, `CB`, `OC`, `AC`, `R`, `I` and a number,
  alphabetical per kind (`WorkingIDs` in the core). Deliberately unstable
  and never stored: they are for talking and thinking ("OC 12 and OC 14
  overlap"), short enough for badges, and keys remain the real identity.
  The UI always says "open code" or "axial code", never just "code".
- **Reporting.** The Coding Chart (`CodingChart` in the core: columns by
  level, M:N links, barycentre ordering to reduce crossings) and the Codebook
  Report (`CodebookReport`: rows per response sheet, CSV with pseudonyms).
- **Inspector.** Follows the page. On a file: Selection (quote, speaker,
  codes with interpretation memos) and File (title, ID, date, status,
  location, fingerprint, codebooks, speakers). On a code: the code (name,
  kind, colour, quick-code slot, description, "evidence for", comments,
  questions, interrelations, codebooks). On a codebook: where it is used and
  how complete your sheets are. On a person: what they are linked to. On a
  list page: the selected row.

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
- Researchers' and interviewees' names are pseudonyms; the pages say so, and
  the YAML files say so in a comment. Real names live only in mapping files
  in the full-texts folder, are read into memory, and are shown only while
  View › Show Real Names is on, which resets at every launch (screen sharing
  is common in supervision meetings). The only file the app ever writes
  outside the workspace is a mapping template, and only when asked, through a
  save panel, never over an existing file, and never into the workspace.
- No network: no network entitlement, no dependencies, no networking API
  (checked by a unit test), no link following, outside-service menu items
  removed, Writing Tools disabled.

## Change detection

Each empirical file records a SHA-256 fingerprint. On opening a file whose
fingerprint differs, every selection in every layer is checked against the
new text: unchanged, found again by its quote (nearest the old position;
exactly, or else ignoring differences in white space, since a corrected
transcript is often re-wrapped) and moved, or lost (flagged in the inspector
and on its quote cards, to resize or delete). Without stored quotes, a
selection is kept if it still fits, and the banner warns that positions may
now be off.

**Updating a file in place** (File › Update Empirical File…, or the File
inspector) is the deliberate version of this: a wizard in three steps.
Choose the new version (in the full-texts folder, which is still only read;
the same sort of file, text or PDF; not catalogued as another file). Check:
every selection, in every layer, is shown as unchanged, moved, unchecked or
not found, with its text and open codes, and each mapped speaker label as
found or not in the new version. Selections without a stored quote
(irrelevant text always) are looked for with their text in the version they
were made on, while that can still be read (this session's copy, or the
file, if its fingerprint still matches); otherwise they keep their positions,
unchecked. Confirm: keep what wasn't found (flagged) or delete it, with a
reminder to commit the workspace to Git first so the diff can be read and
the previous version restored. Nothing changes before Confirm; the update is
one step of Edit › Undo. The file keeps its key, so its codebooks, response
sheets, speakers, title, ID, date and status all stay.

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
- Researchers' pages are reachable by double-click like the others, though
  the specification listed double-click for interviewees only.
- Opening a code from a chip or a quote puts it in the Working Area, like a
  double-click: the page needs a sidebar row to come back to.
- ⌘N makes an item of the kind the current list page shows (Add Files on
  Empirical Files); on other pages it does nothing.
- Updating a file keeps selections it can't find (flagged) unless asked to
  delete them; a speaker label missing from the new version is only
  reported, its mapping is kept.
- Codebooks apply to interviewees but not to researchers (researchers are
  the ones answering).

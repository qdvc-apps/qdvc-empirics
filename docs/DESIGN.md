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

- **Sidebar.** Five sections, in the spirit of Mail's mailboxes above its
  smart mailboxes: *Project* (Empirical Files, Researchers, Layers, Project
  Settings), *Deductive* (Protocols, Interviewees, Attribute Sheets, A Priori
  Codes), *Inductive* (Open Codes, Theorising Codes), *Reports* (Coding Chart,
  Attribute Sheet Report, Protocol Report; the Codebook, Coverage Report,
  Overlap Matrix and Framework Matrix to come), and the *Working Area*: the items being worked on, like open documents, one line each
  (neutral icon, title, working-identifier badge; colour only in the badge). Double-clicking a row in any table opens its page and puts it
  there; it is kept on this Mac (reorder from the context menu). Moving to the
  next file (⌥⌘], ⌥⌘N) swaps the file in its place, so a session of coding
  file after file doesn't fill the Working Area. A progress bar of coded
  files sits at the bottom.
- **List pages** are plain tables (sortable columns, a filter, add buttons
  in a bar at the bottom), as in Finder's list view: selecting a row shows
  it in the inspector, double-clicking opens it. Each page starts with its
  table; nothing sits above it (docs/MAINTENANCE.md §Layout). The tables of
  items attribute sheets apply to (files, interviewees, open and theorising codes) can
  show attribute sheet questions as columns, chosen by right-clicking a column
  heading (SwiftUI column customization, in which only the question columns
  take part, so the menu lists just them; the columns come from
  `TableColumnForEach`, which is why the app needs macOS 14.4). The choice is saved in the
  workspace (`table_columns` in project.yml), so a team sees the same
  columns, and is on Edit › Undo. Question columns are headed by their
  attribute sheet's working identifier in a badge (an image inside the
  heading's Text, the only way to put a capsule there), then the label.
  Their arrangement (order, widths) is saved in the workspace too
  (`table_layouts`, SwiftUI's own column customization as JSON, the only
  form in which SwiftUI gives the order away), half a second after the last
  change, and not on Edit › Undo; only question columns can be moved, since
  only columns with a customization identifier take part.
  A cell shows the answer when all who answered agree, otherwise each
  answer with its researchers' initials, in orange, and everyone's answer in
  the tooltip: disagreement between coders is the thing to notice.
- **Item pages.** An empirical file (the document), a code (its evidence), a
  attribute sheet (its questions), a person (a card laid out like Contacts, with a
  monogram, labelled fields and the transcripts they speak in).
- **Back and Forward** in the Go menu (⌃⌘← / ⌃⌘→), as in Finder and
  Safari, since following a code from a quote and back is a common move.
- **Document.** Text in a readable column, the Interlocutor layer's speaker
  names in a narrow left margin (greyscale: interviewees dark, interviewers
  lighter) as capsule badges in capitals turned to run up each turn's rail,
  which slide down the rail as a long turn scrolls past so the speaker stays
  in view (a frozen heading, per turn; the margin reads the scroll offset
  from FillingScroll's named coordinate space),
  coding stripes in a right margin (dashed grey for irrelevant text), open
  code labels beside them when there is room (in the stripe's colour: the
  working identifiers on the first line, then the names in bold, wrapped so
  they show whole), and the coding bar below. Irrelevant text is greyed out
  whole, in the same faint grey, including the speaker header and margin
  name of a turn whose words are all irrelevant. The
  code palette floats at the top, like Spotlight. The page shares its width
  in a fixed order of sacrifice (`ColumnLayout`): outer margins, then a
  quarter of the text width, then the code names, then the text (the
  speaker margin is narrow already); the coding bar falls back to compact
  and minimal variants. Protocol segments sit at the far left with their
  item labels, and under each label a summary bubble (dotted while empty;
  double-click to write the item's summary for the file). While coding on an
  inductive layer, the segments of the visible deductive layers stay there,
  lighter and only for reference, so the protocol is always in view.
  Nothing on any page may ask for more width than the detail column gives
  it, so the sidebar is never pushed off the window.
- **Working identifiers.** `EF`, `AST`, `OC`, `TC`, `R`, `I` and a number,
  alphabetical per kind (`WorkingIDs` in the core). Deliberately unstable
  and never stored: they are for talking and thinking ("OC 12 and OC 14
  overlap"), short enough for badges, and keys remain the real identity.
  The UI always says "open code" or "theorising code", never just "code".
- **Reports.** The Coding Chart (`CodingChart` in the core: columns by
  level, M:N links, barycentre ordering to reduce crossings), the Attribute Sheet
  Report (`AttributeSheetReport`: rows per response sheet, CSV with pseudonyms)
  and the Protocol Report (`ProtocolReport`: a protocol's items across the
  files following it in a deductive layer, each cell the item's summary for
  the file, with the full answer a click away). A protocol item's summary
  for a file is that layer's Framework Matrix cell for the file and the
  item, so the Framework Matrix, when it comes, shows the same summaries.
- **Inspector.** Follows the page. On a file: Selection (quote, speaker,
  codes with interpretation memos) and File (title, ID, date, status,
  location, fingerprint, attribute sheets, speakers). On a code: the code (name,
  kind, colour, quick-code slot, description, "evidence for", comments,
  questions, interrelations, attribute sheets). On an attribute sheet: where it is used and
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

**Correcting the text.** A transcript often needs a typo fixed after coding
has begun. Select the text, right-click, Edit Text…: a sheet in two steps
(write the new text; then confirm, seeing before and after and what happens
to the selections) writes the file in the full-texts folder and adjusts the
workspace in one go (`Project.applyTextEdit` in the core). The edit is
precise, so nothing has to be searched for again: what follows moves by the
change in length, what overlaps the edit takes in the new text (irrelevant
text stops at its edges, keeping the irrelevance rule), and a selection
left with nothing is deleted, which the sheet says beforehand. The file is
written back the way it was (encoding, byte-order mark, line endings), so
the diff of a corrected transcript is the correction. Edit › Undo writes the
previous bytes back. For larger revisions (a re-transcribed interview),
Update Empirical File from New Version is still the way.

## PDFs

Coded on their own pages with PDFKit, as asked. Selections are page and
character ranges in PDFKit's page text (`PDFPage.string`), so they survive
zooming and re-flowing. Highlights are drawn with
`PDFView.highlightedSelections`: no annotations are added, the document is
never modified, and it is loaded from memory (`PDFDocument(data:)`), so
nothing could be written back to the file. Links in PDFs are never followed
(`pdfViewWillClick(onLink:with:)` does nothing).

Coding stripes sit in the background beside the pages, as beside text:
`pageBreakMargins` leaves room, and a transparent view over the PDF view
(`PDFStripeOverlay`) draws them from the selections' bounds on each visible
page, in lanes, laid out again as the PDF scrolls or zooms; it takes clicks
only on stripes. A page printed sideways can be turned for reading
(right-click it): the turn is stored per page in the file's YAML and added
to the page's own rotation in the copy in memory; the PDF is still never
written, and selections, which count into the page's text, don't move.

## Data security

- The workspace and full-texts are separate folders and may not be nested
  either way (checked when creating a project or choosing the folder).
- Full-texts are read, and written only when the researcher confirms an
  edit to a text file's text (Edit Text…, and undoing or redoing it):
  `FullTexts.write` is the one write, and the app calls it nowhere else. The
  app is sandboxed; the full-texts folder's security-scoped bookmark allows
  reading and writing (folders chosen before edits existed have a read-only
  one, and the first edit asks for the folder again). PDFs and consent
  forms are never written. Consent forms are viewed inside the app (never
  handed to Preview, which could save them).
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
one step of Edit › Undo. The file keeps its key, so its attribute sheets, response
sheets, speakers, title, ID, date and status all stay.

## Deductive and inductive

The app supports deductive and inductive approaches side by side, and works
towards abductive ones: abduction is not a third kind of coding but what
happens when the two are juxtaposed (Timmermans & Tavory, 2012), so it is
served by putting deductive and inductive layers next to each other and by
**links** from open and theorising codes to a priori codes (confirms, refines,
extends, contradicts, not covered).

- **Deductive** (defined upfront, with consequences for the result):
  protocols, interviewees, attribute sheets and a priori codes. Protocols
  and a priori codes are project-wide: two coders apply the *same*
  instrument, each on their own deductive layer.
- **Inductive** (emerging from the data): open and theorising codes, per
  inductive layer, since emergent codes belong to a coder's reading.

A **protocol** marks *where in the text* something occurs (structural
coding: Saldaña; MacQueen et al., 2008): an item's prompt and its response
are separate selections on a deductive layer, drawn in the margin like
speaker turns, never a priori evidence. An **attribute sheet** records *what
the researcher concludes about* an item. An **a priori code** carries its
codebook entry (MacQueen et al., 1998; Boyatzis, 1998): definition, what is
included and excluded, an ideal example, a counter-example and its source.

Inductive coding has two levels: **open codes** and **theorising codes**
(`OC n`, `TC n`). There is no level above theorising codes, so they cover
what the grounded-theory traditions split over one or two higher levels:
Selective *and* Theoretical Codes (Glaser, 1978); Axial *and* Selective Codes
(Strauss & Corbin, 1990, 1998); Focused *and* Theoretical Coding (Charmaz,
2006); Second-Order Themes *and* Aggregate Dimensions (Gioia et al., 2012).
A theorising code may be built on other theorising codes, which is how the
higher of those levels is expressed. "Theorising" alludes to *products of
theorising* (Weick, 1995; Hassan et al., 2022): what the coding produces is
a step towards theory, not yet the theory itself.

The coding UI follows the active layer's kind rather than offering both:
the same keys, palette, quick codes (nine per layer), stripes and inspector
apply open codes on an inductive layer and a priori codes on a deductive
one, so a coder never has to think about which kind of code goes where.
Protocol segments get their own keys (Q for a prompt, A for a response),
their own palette and their own margin at the far left, drawn as brackets
in one neutral colour: they are structure, like speaker turns, and must
never be read as coding. A file's protocol in a layer is set by its first
segment (or in the File inspector), so most coders never choose it
explicitly.

## Layers

Each layer is deductive or inductive. A project starts with Main Deductive
and Main Inductive and always keeps one of each; a layer's kind can change
only while nothing is coded in it. A selection or code exists in one layer.
Evidence, interrelations and irrelevance are per layer, so two researchers
(or two lenses) can read the same transcript differently. Moving anything
to another layer (of the same kind) moves its connected component
(selections ↔ open codes ↔ theorising codes; on deductive layers, a selection
with its a priori evidence), with a sheet saying how much will move; it is
refused if a moved selection would overlap text of the other kind
(irrelevant or not) in the target layer, or if its protocol segments would
land on a file following another protocol there.

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
  otherwise there is one sheet per attribute sheet and item.
- Removing a file from the project removes its selections in every layer;
  the full-text is untouched.
- Researchers' pages are reachable by double-click like the others, though
  the specification listed double-click for interviewees only.
- A file follows at most one protocol per deductive layer.
- A priori codes are a flat list, as are protocol items.
- A link joins one open or theorising code to one a priori code, once.
- Opening a code from a chip or a quote puts it in the Working Area, like a
  double-click: the page needs a sidebar row to come back to.
- ⌘N makes an item of the kind the current list page shows (Add Files on
  Empirical Files); on other pages it does nothing.
- Updating a file keeps selections it can't find (flagged) unless asked to
  delete them; a speaker label missing from the new version is only
  reported, its mapping is kept.
- Attribute Sheets apply to interviewees but not to researchers (researchers are
  the ones answering).
- Two selections next to each other and coded the same way are only ever
  merged when the researcher asks (Merge in the coding bar, the Selection
  inspector or the right-click menu): splitting a passage may be
  deliberate. "Next to each other" means nothing but white space between
  them, on the same page; "coded the same way" means the same codes (open
  codes, or a priori codes), both irrelevant, the same protocol item and
  part, or both highlights without a code. The earlier selection stays,
  with both memos joined.
- An edit to a text file's text that overlaps a selection gives it the new
  text (a typo fixed inside a quote stays in the quote); an edit at the very
  start or end of a selection stays outside it.
- A protocol item's summary is one per file per deductive layer, shown in a
  bubble under every label of the item's segments in that file (prompt and
  response alike), and stored as the layer's Framework Matrix cell.
- While an inductive layer is active, the segments of every visible
  deductive layer show, in lanes if they overlap.

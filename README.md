# QDVC Empirics for macOS

Qualitative data analysis of interview transcripts, field notes and
articles: highlight selections, code them to open codes, build theorising codes
from those, write down why each piece of evidence counts, answer attribute sheets
about files and codes, and keep it all in a folder of plain YAML files that
diffs cleanly in Git.

A native SwiftUI and AppKit app for macOS 14.4 (Sonoma) and later, loosely
based on the YAML workflow for qualitative data analysis in Wang (2022),
*Programming for Qualitative Data Analysis: Towards a YAML Workflow*, ACIS
2022 (https://aisel.aisnet.org/acis2022/17/). See
[Build and run](#build-and-run) to get started on your Mac.

## Two folders, kept apart

Every project has two folders:

- The **workspace**: the analysis, as small YAML files (one per code, one per
  file's selections in each layer, one per attribute sheet response sheet…), meant
  to be tracked in Git and shared with co-authors. The format is documented
  in [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md).
- The **full-texts folder**: the transcripts, PDFs and signed consent forms.
  It never goes into the workspace or Git. QDVC Empirics reads it, and
  writes to it only when you confirm an edit to a text file's text (a typo in
  a transcript, say; see below). Its location is remembered per project on
  each Mac, never in the workspace; Settings › Privacy forgets it.

By default each selection's text (its quote) is stored in the workspace, so
the YAML reads well and selections can be found again if a transcript is
corrected. Project › *Store quotes in the workspace* turns that off, leaving
only positions and a checksum.

**No network, ever.** The app is sandboxed without any network entitlement,
so macOS itself refuses any connection; it has no dependencies (its YAML
reader and writer and its SHA-256 are its own); links in PDFs are never
followed; Look Up, Translate, Share, Services and Writing Tools are removed
from its menus; and a unit test fails if a networking API appears anywhere
in the sources.

## What it does

At launch a welcome window, as in Xcode and the other QDVC apps, offers to
create or open a project and lists recent ones.

The main window has a **sidebar**, the page in the middle, and an
**inspector** on the right (⌥⌘I) that follows the page. The sidebar has five
sections:

- **Project:** Empirical Files, Researchers, Layers, Project Settings.
- **Deductive** (defined upfront): Protocols, Interviewees, Attribute
  Sheets, A Priori Codes.
- **Inductive** (emerging from the data): Open Codes, Theorising Codes.
- **Reports:** Inductive Coding Chart, Attribute Sheet Report, Protocol
  Responses, Protocol Outcomes.
- **Working Area:** the files, open codes, theorising codes, attribute sheets and people
  you are working on, one line each: an icon, the title and the working
  identifier (coloured like the code, or orange or green for a file in
  progress or coded). Double-click a row in any table to open its page and
  put it here; right-click to move it up or down, or to remove it (or the
  others). It is remembered on this Mac.

**Working identifiers.** Every empirical file, protocol, attribute sheet, a
priori code, open code, theorising code, researcher and interviewee has a short
identifier to talk about it while working: `EF 31`, `PR 1`, `AST 4`,
`APC 7`, `OC 23`, `TC 12`, `R 5`, `I 17`. They number
each kind alphabetically (by title or pseudonym), so they are **not stable**:
adding, renaming or removing an item renumbers the ones after it. They are
shown in the tables (the No. column), the Working Area, the inspectors, the
code palette (type `oc 23` to find that open code) and the reports, and are
never stored.

The list pages are plain tables (click a column heading to sort, filter at
the bottom): selecting a row shows its details in the inspector,
double-clicking opens its page, and ⌘N makes a new one (on Empirical Files,
it adds files). Tables of items that attribute sheets can be associated with
(empirical files, interviewees, open codes, theorising codes) have an Attribute Sheets
column, and can show any question of the attribute sheets that apply to them as a
column of its own: right-click a column heading and tick the questions.
Each question column is headed by its attribute sheet's working identifier
in a badge (`AST 2`), then the question's label.
Where researchers' answers differ, the cell shows each answer with their
initials, in orange ("Yes (AB) · No (CD)"); hover for everyone's answer.
Sort by a question column like any other, and drag it to another place
among the headings. Which questions show, and where (their order and
widths), are saved in the workspace, so everyone sharing it sees the same
columns in the same places. Go › Back and Forward (⌃⌘← / ⌃⌘→)
retrace your steps. The pages of single items are:

- an **empirical file**: the document, coded as below, with the inspector's
  Selection and File tabs;
- an **open or theorising code**: its evidence, with the code itself (name,
  colour, description, comments, questions, interrelations, attribute sheets) in
  the inspector;
- a **protocol**: its items;
- an **a priori code**: its codebook entry, the open and theorising codes linked
  to it and its evidence, with the entry itself in the inspector;
- an **attribute sheet**: its questions;
- a **researcher** or **interviewee**: a card as in Contacts, with the
  transcripts they speak in.

**Coding a file** (text, Markdown or PDF):

- Text and Markdown files are shown in a calm reading column (serif by
  default, generous line spacing, adjustable in Settings › Reading; the
  column's width follows View › **Margins**, narrow, medium or wide, as in
  QDVC Manuscript, ⌃⌥⌘1–3), with
  **coding stripes** in the right margin, one per selection, in lanes where
  they overlap (irrelevant text has a dashed grey one); click a stripe to
  focus its selection. When the window is wide enough, each stripe has a
  label beside it in its own colour: the open codes' working identifiers
  on the first line, then their names in bold, wrapped so the whole label
  shows. As the window narrows, the wide outer margins go first, then the
  labels; the sidebar is never pushed off the window.
- PDFs are coded on their own pages (PDFKit), with the same keys and the
  same margins in the background beside the pages: protocol segments with
  their labels and summary bubbles on the left, coding stripes and the
  codes' labels on the right (they make room as the window allows, and
  scroll with the pages). Right-click a page to **rotate** it
  left or right (a table printed sideways, say): the turn is saved in the
  workspace, so everyone sees the page that way; the PDF itself isn't
  changed.
- A thin bar above the coding bar shows how far the file's coding has come
  in the active layer: **coded** (green), **irrelevant** (grey) and still to
  do (the empty part); hover for the percentages. It counts characters that
  aren't white space, leaving out speaker header lines and time indicators.
  Text counts as coded when a selection over it is evidence for a code, or
  is a protocol segment; a highlight without a code is still to do.
- **Time indicators** a transcriber leaves in the text, such as `[~5 min]`
  or `[~20 min]` (also `[5 mins]`, `[~1.5 h]`, `[~2–3 min]`), are ignored for
  coding: shown faint, trimmed from the ends of anything you select to code
  (a selection of nothing but one is refused), and left out of the progress
  bar.
- On the Interlocutor layer, each speaker's turn has a line in the narrow
  left margin, with the speaker's name in capitals on its left, running up
  the margin. The name is centred on the part of the line that is on
  screen, so on a long turn it moves as you scroll and who is speaking stays
  in view.
- Select text, then press **Return** (or ⌘K) to open the **code palette**:
  type a few letters, Return applies the code; a name that isn't a code yet
  creates it (⌘Return always creates). On an inductive layer the palette
  holds the layer's open codes; on a deductive layer, the project's a priori
  codes (a new name makes a new a priori code). Press **1–9** for **quick
  codes**: the first nine codes you use take 1–9 and keep them, so the
  numbers never shift under your fingers (reassign them from any code's
  context menu or inspector). Each layer has its own nine.
- On a deductive layer, **Q** marks the selected text as the **prompt** of a
  protocol item and **A** as its **response** (or use the coding bar's
  Protocol menu): a small palette lists the items of the file's protocol
  (type a number or words, Tab switches prompt and response). Segments are
  structure, not coding: they show at the far left, a bracket and the item
  beside the lines (dashed for a prompt), and are never evidence. A file
  follows one protocol per deductive layer, set by its first segment or in
  the File inspector. While you code on an inductive layer, the segments of
  the deductive layers shown beside it (the toolbar's layer menu, Also
  Show) stay at the far left, lighter, so you always see where you are in
  the protocol.
- Under each protocol label is a small **summary bubble**: a dotted circle
  while the item has no summary for this file. Double-click it to write
  one (what this file says for the item, in a sentence or two); it then
  fills in, and shows in the **Protocol Responses** report.
- **Editing the text itself**: select a part of a text or Markdown file,
  right-click it and choose **Edit Text…** (also in the Selection
  inspector) to correct it, a typo in a transcript say. Write the new text,
  then confirm saving it to disk, having seen what it does to the
  selections. The file in the full-texts folder is rewritten in its own
  encoding and line endings, and the workspace follows, in every layer:
  selections after the edit move with the text, those overlapping it take in
  the new text, one left with no text at all is deleted, and quotes and the
  fingerprint are updated. Edit › Undo writes the previous text back. (A
  full-texts folder chosen in an earlier version was granted read-only
  access: the first edit asks you to choose it again.)
- **Merging selections**: when the focused selection has a neighbour right
  next to it (nothing but white space between them) coded the same way (the
  same codes, both irrelevant, the same protocol item and part, or both
  highlights without a code), the coding bar and the Selection inspector
  offer **Merge**, and the right-click menu Merge with Previous or Next
  Selection. Their memos are kept, joined. Selections are never merged
  without asking.
- **0** marks the selected text irrelevant: it is greyed out in a faint grey,
  speaker names included. Irrelevant text can never
  be evidence: the app refuses to code over it, and refuses to mark evidence
  irrelevant. **H** makes a selection without a code, to come back to.
- **T** selects the speaker's turn under the cursor (Interlocutor layer),
  **P** the paragraph, **S** the sentence. **]** and **[** step through the
  selections; **Delete** deletes the focused one; **Esc** clears.
- Click a highlight to focus it. The inspector shows its quote, speaker,
  codes, and for each code an **interpretation memo**: why this is evidence
  for the code (the "Interpretation" entity of Wang 2022, Figure 2).
- Everything is on Edit › Undo (⌘Z). Changes are saved as you go.
- The keyboard button in the coding bar lists every key. Go › Next File Not
  Yet Coded (⌥⌘N) and the status menu in the toolbar (Not Started, In
  Progress, Coded) keep long sessions moving; the sidebar shows progress.
- Each file reopens where you left off.
- **Updating a file** with a corrected or re-exported version of its
  full-text (File › Update Empirical File from New Version…, or the File
  inspector): choose the new version in the full-texts folder, see which
  selections (in every layer) and speakers can be found in it, then confirm,
  keeping or deleting what wasn't found. The file keeps its coding,
  attribute sheets and response sheets; the old version is left untouched. Commit
  the workspace to Git first, and the diff shows exactly what moved.

**Open Codes** and **Theorising Codes** (⌃⌘9, ⌃⌘0): the codes of an inductive
layer (the active layer, or the first inductive one). A code's page shows its **evidence**: every quote, grouped by file,
with speaker, other codes and memo, and Show in File; for a theorising code, the
codes it is built from and their quotes. Open codes have selections as
evidence; theorising codes have open codes and other theorising codes (cycles are
refused). Each code has a name, colour, description, **comments** and
**questions** (unresolved matters), and **interrelations**: commentary on how
two or more pieces of its evidence relate, typed Compare, Contrast or your
own types.

Inductive coding has two levels, and **theorising codes** are the higher
one. As there is nothing above them, they take in what the grounded-theory
traditions spread over one or two higher levels: Selective and Theoretical
Codes (Glaser, 1978), Axial and Selective Codes (Strauss & Corbin, 1990,
1998), Focused and Theoretical Coding (Charmaz, 2006), Second-Order Themes
and Aggregate Dimensions (Gioia et al., 2012); a theorising code built on
other theorising codes expresses the higher of those. "Theorising" alludes
to products of theorising (Weick, 1995; Hassan et al., 2022).

**Attribute Sheets** (⌃⌘7): ordered questions, each with a short label (16
characters at most), the full question, and an answer type: free text,
choose one or choose any from a list. A list can be strictly predefined, or
open to options added while coding (they join the attribute sheet). Each question is
*mandatory, blocking* (the response sheet can't be saved without it),
*mandatory, non-blocking* (flagged until answered) or *optional*. An attribute sheet
applies to empirical files, interviewees, open codes and/or theorising codes, and
is associated with any of them from the inspector, where each researcher fills in their own
**response sheet**.

**Researchers** and **Interviewees** (⌃⌘2, ⌃⌘6): everyone is known by a
**pseudonym**; the pages say so plainly. Interviewees link to their consent
form in the full-texts folder, viewable read-only inside the app. On
Researchers, choose *This Mac's researcher* so selections and answers are
attributed to you.

**Real names.** Optionally, keep a mapping file (CSV: key, pseudonym, real
first and last names) for researchers and one for interviewees in the
full-texts folder; Project Settings chooses them, and can save a template to
fill in. The app only reads them and keeps the names in memory. View › Show
Real Names (⇧⌘R, or the eye in the toolbar) swaps pseudonyms for real names
everywhere they are shown; it is off at every launch, so a shared screen
never shows them by surprise.

**Layers** (⌃⌘3): each layer is **deductive** (it applies what was defined
beforehand: protocols and a priori codes) or **inductive** (it holds what
emerges from the data: open and theorising codes). A project starts with Main
Deductive and Main Inductive, and always keeps at least one of each; a
layer's kind can change only while nothing is coded in it. Selections and
codes live in exactly one layer (a theoretical lens, one researcher's
reading). Code in the active layer (the toolbar's layer menu); other layers
can show as underlines. Moving a selection or code to another layer (of the
same kind) moves everything linked to it. The
**Interlocutor layer** finds conversational turns from speaker header lines,
forgiving inconsistent capitals, colons, line breaks, timestamps and
Markdown emphasis, and maps each speaker to a researcher or interviewee
(File inspector › Speakers…); names then show in the left margin, running
up beside each turn's line (see Coding a file), in greyscale so they never
compete with code colours: interviewees dark, interviewers a lighter grey.

**Protocols** (⌃⌘5) and **A Priori Codes** (⌃⌘8) are defined once for the
project and applied on deductive layers. A **protocol** is a predefined set
of items (the questions of an interview protocol, the sections of an
article), each with a short label and its full wording, that each file
follows in part or in whole; in a file, an item's *prompt* and *response*
are marked as protocol segments (above). Its page edits the items (add,
reorder, delete); its inspector shows which files follow it and how many
segments each item has. An **a priori code** is defined before coding, with
its codebook entry: name, definition, what is included and excluded, an
ideal example, a counter-example (a near miss) and its source; its page
shows the entry, the codes linked to it and its evidence by file, with a
memo on each piece. Open and theorising codes can be **linked** to a priori codes
(confirms, refines, extends, contradicts, not covered), which is where
theory and data meet. *Side-by-side layers, editing links, and the
Codebook, Coverage Report, Overlap Matrix and Framework Matrix follow in the
next updates.*

**Project Settings** (⌃⌘4): title, description, the two folders, real-name
mapping files, quote storage and interrelation types.

**Inductive Coding Chart** (Go menu): an inductive layer at a glance (the
active layer, or the first inductive one). Empirical files on the
left, linked to the open codes with evidence in them, linked to the theorising
codes they are evidence for; theorising codes built on other theorising codes sit
further right. Each item is one line (icon, title, working identifier).
Click one to light up everything it is linked to and see it in the
inspector; double-click to open it. Items nothing links to are left out
unless you ask for them.

**Attribute Sheet Report** (Go menu): choose an attribute sheet in the bar below and see every
response to it in one table: a row per response sheet (and per associated
item nobody has answered yet), a column per question, with flagged
mandatory questions marked. Double-click a row for its response sheet; copy
or save the table as CSV (always with pseudonyms).

**Protocol Responses** (Go menu): choose a protocol and a deductive layer in
the bar below and see, for every empirical file following the protocol
there, a row with each item's summary (written in the bubbles under the
protocol labels in the file). A cell whose item is marked in the file has a
**Full Answer** button: the prompt and response as they are in the text,
with Show in File. Double-click a cell to write or change its summary; copy
or save the summaries as CSV.

**Protocol Outcomes** (Go menu): where codes are grounded, protocol-wise.
Choose a protocol (and the deductive layer whose prompts and responses
count) and a kind of code (a priori, open or theorising, and the layer they
come from). Each code is a row; each item's prompt and response is a
column, with the number of the code's instances in text marked as that part
of that item, shaded by count; then the instances elsewhere, and the total.
An instance is a selection the code is evidence for (for a theorising code,
those of the codes it is built from, all the way down); it counts in every
segment it overlaps, wherever the two were made, since they are compared
by where they are in the file. Click a count to read its instances (with
Show in File); copy or save the counts as CSV. Use it to trace, say, how far
inductive codes rest on answers to particular questions, or on the
interviewer's own prompts.

## Requirements

- macOS 14.4 Sonoma or later.
- Xcode 16 or later (free from the Mac App Store); Xcode 26 or later for the
  Liquid Glass look. Full Xcode is needed, not just the Command Line Tools:
  from Xcode 27, SwiftUI's `@State` is a macro whose compiler plugin
  (SwiftUIMacros) ships only with Xcode, so a Command Line Tools or swift.org
  toolchain fails with "plugin for module 'SwiftUIMacros' not found".
- No paid Apple Developer account.

## Build and run

From the repository root:

```sh
scripts/build-app.sh            # build "build/QDVC Empirics.app" (release)
scripts/build-app.sh --install  # …and copy it to ~/Applications
```

`scripts/build-app.sh` builds with Xcode's toolchain even when
`xcode-select` points at the Command Line Tools: it picks the newest Xcode
installed, and says which Xcode and macOS SDK it is using (warning if the
SDK predates Liquid Glass). It also records that SDK in the app's binary,
which is what turns on Liquid Glass (`swift build` alone writes the
deployment target there, 14.0, so a `swift run` build keeps the classic
look). Check a build with
`vtool -show-build "build/QDVC Empirics.app/Contents/MacOS/QDVCEmpirics"`:
`sdk` should be 26.0 or later.

The app is signed with the sandbox and no network entitlement (the script
checks both). `--no-sandbox` signs without the sandbox, for troubleshooting
only.

To run or test from the command line, point the tools at Xcode:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
# or: sudo xcode-select --switch /Applications/Xcode.app
swift run                       # build and launch (debug, not sandboxed)
swift test                      # run the unit tests
```

The core library (`EmpiricsCore`: the model, the rules, YAML, the workspace,
turn detection, re-anchoring) has no AppKit or SwiftUI and builds and tests
on Linux too (docs/MAINTENANCE.md).

A ready-made sample is included: open `sample-workspace/` (File › Open
Project…) and, when asked, choose `sample-full-texts/` as its full-texts
folder. It has two interviews (one with exactly the messy speaker headers the
Interlocutor layer is built for), field notes in Markdown and a two-page PDF;
a deductive layer with an interview protocol (prompts and responses marked)
and a priori codes from the Technology Acceptance Model with evidence and
Framework Matrix summaries; two inductive layers with open and theorising codes,
memos, comments, questions, interrelations and links to the a priori codes;
irrelevant text, two attribute sheets and response sheets, and real-name
mapping files (all names in it are invented).
Regenerate it with `MAKE_SAMPLE=$PWD swift test --filter MakeSampleTests`.

## Signing without a paid account

`scripts/build-app.sh` signs the app **ad hoc** (`codesign --sign -`). That is
all macOS needs to run an app on the Mac that built it. If you give the app
to someone else, macOS will block the first launch; they can allow it in
**System Settings → Privacy & Security → Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine "/Applications/QDVC Empirics.app"
```

## App icon

The icon, a well-worked book (two pages swept with highlighter, margin notes
and a circled word in pen, a sticky note on the page, more sticky notes and
paper flags poking out of its edges, two ribbon bookmarks) on a pale
cantaloupe gradient, is generated by `tools/make_icon.py` on Apple's macOS
icon template, built like the other QDVC apps' icons. It appears in the
`.app` built by `scripts/build-app.sh`, not with `swift run`.

## Where things are stored

- The analysis: only in the workspace, as described in
  [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md). Changes are written as you go;
  only files whose content changed are rewritten. The app notices files
  changed by Git or another editor when you come back to it, and View ›
  Reload from Disk (⌘R) re-reads them at any time. A file with Git conflict
  markers is reported (with its name) rather than misread.
- The full-texts: only in the full-texts folder; written only when you
  confirm an edit to a text file's text (and when you undo or redo one).
- On this Mac (the app's sandbox container, not the workspace): recent
  projects, each project's full-texts folder and researcher, the Working
  Area, active and hidden layers, quick codes, reading positions and reading
  preferences.
- Real names: only in the mapping files in the full-texts folder; read into
  memory, never written anywhere.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⌘N | New item on the current page (file, researcher, protocol, interviewee, attribute sheet, a priori code, open or theorising code) |
| ⇧⌘N / ⌘O | New / open project |
| ⇧⌘A | Add files from the full-texts folder |
| Return, K, ⌘K | Code the selection (code palette) |
| 1 … 9 (⌃1 … ⌃9) | Quick codes |
| Q / A | Mark as a protocol prompt / response (deductive layers) |
| 0 (⌥⌘0) | Mark irrelevant / relevant |
| H (⌥⌘K) | Highlight without a code |
| T / P / S | Select turn / paragraph / sentence |
| ] / [ (⌘] / ⌘[) | Next / previous selection |
| Delete (⌘⌫) | Delete the focused selection |
| ⌥⌘] / ⌥⌘[ | Next / previous file |
| ⌥⌘N | Next file not yet coded |
| ⌃⌘C | Mark the file as coded |
| ⌃⌘1 … ⌃⌘9, ⌃⌘0 | Empirical Files, Researchers, Layers, Project Settings, Protocols, Interviewees, Attribute Sheets, A Priori Codes, Open Codes, Theorising Codes (the Reports pages are in the Go menu) |
| ⌃⌘← / ⌃⌘→ | Back / forward |
| ⇧⌘R | Show real names |
| ⌃⌘I | Show or hide interlocutors |
| ⌘+ / ⌘− / ⌘0 | Larger / smaller / default text |
| ⌃⌥⌘1 / 2 / 3 | Narrow / medium / wide margins |
| ⌥⌘I | Inspector |
| ⇧⌘1 | Welcome window |
| ⌘R | Reload from disk |
| ⌘Z / ⇧⌘Z | Undo / redo |

## Licence of the paper

Wang (2022) is licensed under CC BY-NC 3.0 AU; this app only takes ideas
from it, and doesn't include it.

# QDVC Empirics for macOS

Qualitative data analysis of interview transcripts, field notes and
articles: highlight selections, code them to open codes, build axial codes
from those, write down why each piece of evidence counts, answer codebooks
about files and codes, and keep it all in a folder of plain YAML files that
diffs cleanly in Git.

A native SwiftUI and AppKit app for macOS 14 (Sonoma) and later, loosely
based on the YAML workflow for qualitative data analysis in Wang (2022),
*Programming for Qualitative Data Analysis: Towards a YAML Workflow*, ACIS
2022 (https://aisel.aisnet.org/acis2022/17/). See
[Build and run](#build-and-run) to get started on your Mac.

## Two folders, kept apart

Every project has two folders:

- The **workspace**: the analysis, as small YAML files (one per code, one per
  file's selections in each layer, one per codebook response sheet…), meant
  to be tracked in Git and shared with co-authors. The format is documented
  in [docs/FILE_FORMAT.md](docs/FILE_FORMAT.md).
- The **full-texts folder**: the transcripts, PDFs and signed consent forms.
  It never goes into the workspace or Git. QDVC Empirics only ever reads it
  (it is opened read-only, and macOS enforces that on later launches). Its
  location is remembered per project on each Mac, never in the workspace;
  Settings › Privacy forgets it.

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
**inspector** on the right (⌥⌘I) that follows the page. The sidebar has three
sections:

- **Project:** Empirical Files, Researchers, Interviewees, Project Settings.
- **Analysis:** Codebooks, Open Codes, Axial Codes, Layers.
- **Working Area:** the files, codes, codebooks and people you are working
  on. Double-click a row in any table to open its page and put it here;
  right-click to move it up or down, or to remove it (or the others). It is
  remembered on this Mac.

The list pages are plain tables (click a column heading to sort, filter at
the bottom): selecting a row shows its details in the inspector,
double-clicking opens its page. Go › Back and Forward (⌃⌘← / ⌃⌘→)
retrace your steps. The pages of single items are:

- an **empirical file**: the document, coded as below, with the inspector's
  Selection and File tabs;
- an **open or axial code**: its evidence, with the code itself (name,
  colour, description, comments, questions, interrelations, codebooks) in
  the inspector;
- a **codebook**: its questions;
- a **researcher** or **interviewee**: a card as in Contacts, with the
  transcripts they speak in.

**Coding a file** (text, Markdown or PDF):

- Text and Markdown files are shown in a calm reading column (serif by
  default, generous line spacing, adjustable in Settings › Reading), with
  **coding stripes** in the right margin, one per selection, in lanes where
  they overlap; click a stripe to focus its selection. PDFs are coded on
  their own pages (PDFKit), with the same keys.
- Select text, then press **Return** (or ⌘K) to open the **code palette**:
  type a few letters, Return applies the code; a name that isn't a code yet
  creates it (⌘Return always creates). Press **1–9** for **quick codes**: the
  first nine codes you use take 1–9 and keep them, so the numbers never shift
  under your fingers (reassign them from any code's context menu or the Code
  inspector).
- **0** marks the selected text irrelevant (dimmed). Irrelevant text can never
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

**Open Codes** and **Axial Codes** (⌃⌘6, ⌃⌘7): the codes of the active
layer. A code's page shows its **evidence**: every quote, grouped by file,
with speaker, other codes and memo, and Show in File; for an axial code, the
codes it is built from and their quotes. Open codes have selections as
evidence; axial codes have open codes and other axial codes (cycles are
refused). Each code has a name, colour, description, **comments** and
**questions** (unresolved matters), and **interrelations**: commentary on how
two or more pieces of its evidence relate, typed Compare, Contrast or your
own types.

**Codebooks** (⌃⌘5): ordered questions, each with a short label (16
characters at most), the full question, and an answer type: free text,
choose one or choose any from a list. A list can be strictly predefined, or
open to options added while coding (they join the codebook). Each question is
*mandatory, blocking* (the response sheet can't be saved without it),
*mandatory, non-blocking* (flagged until answered) or *optional*. A codebook
applies to empirical files, open codes and/or axial codes, and is associated
with any of them from the inspector, where each researcher fills in their own
**response sheet**.

**Researchers** and **Interviewees** (⌃⌘2, ⌃⌘3): everyone is known by a
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

**Layers** (⌃⌘8): selections and codes live in exactly one layer (a
theoretical lens, one researcher's reading). Code in the active layer (the
toolbar's layer menu); other layers can show as underlines. Moving a
selection or code to another layer moves everything linked to it. The
**Interlocutor layer** finds conversational turns from speaker header lines,
forgiving inconsistent capitals, colons, line breaks, timestamps and
Markdown emphasis, and maps each speaker to a researcher or interviewee
(File inspector › Speakers…); names then show in the left margin.

**Project Settings** (⌃⌘4): title, description, the two folders, real-name
mapping files, quote storage and interrelation types.

## Requirements

- macOS 14 Sonoma or later.
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
two layers, open and axial codes with memos, comments, questions and
interrelations, irrelevant text, two codebooks and response sheets, and
real-name mapping files (all names in it are invented).
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
- The full-texts: only in the full-texts folder; never written.
- On this Mac (the app's sandbox container, not the workspace): recent
  projects, each project's full-texts folder and researcher, the Working
  Area, active and hidden layers, quick codes, reading positions and reading
  preferences.
- Real names: only in the mapping files in the full-texts folder; read into
  memory, never written anywhere.

## Keyboard shortcuts

| Shortcut | Action |
| --- | --- |
| ⇧⌘N / ⌘O | New / open project |
| ⇧⌘A | Add files from the full-texts folder |
| Return, K, ⌘K | Code the selection (code palette) |
| 1 … 9 (⌃1 … ⌃9) | Quick codes |
| 0 (⌥⌘0) | Mark irrelevant / relevant |
| H (⌥⌘K) | Highlight without a code |
| T / P / S | Select turn / paragraph / sentence |
| ] / [ (⌘] / ⌘[) | Next / previous selection |
| Delete (⌘⌫) | Delete the focused selection |
| ⌥⌘] / ⌥⌘[ | Next / previous file |
| ⌥⌘N | Next file not yet coded |
| ⌃⌘C | Mark the file as coded |
| ⌃⌘1 … ⌃⌘8 | Empirical Files, Researchers, Interviewees, Project Settings, Codebooks, Open Codes, Axial Codes, Layers |
| ⌃⌘← / ⌃⌘→ | Back / forward |
| ⇧⌘R | Show real names |
| ⌃⌘I | Show or hide interlocutors |
| ⌘+ / ⌘− / ⌘0 | Larger / smaller / default text |
| ⌥⌘I | Inspector |
| ⇧⌘1 | Welcome window |
| ⌘R | Reload from disk |
| ⌘Z / ⇧⌘Z | Undo / redo |

## Licence of the paper

Wang (2022) is licensed under CC BY-NC 3.0 AU; this app only takes ideas
from it, and doesn't include it.

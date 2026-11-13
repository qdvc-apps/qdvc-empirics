# QDVC Empirics for macOS — Maintenance Guide

The one rule that matters most: **the workspace is the contract.** The files
the app writes are documented in [FILE_FORMAT.md](FILE_FORMAT.md) and
checked by the unit tests. Any change to a file name or to the bytes of a
file is a format change: update FILE_FORMAT.md and the tests with it.

The second: **no network, and full-texts are read-only.** See §Network and
§Full-texts below before adding any API or dependency.

## 1. Layout

```
Package.swift                 SwiftPM manifest (no Xcode project, no dependencies)
Sources/EmpiricsCore/         the model: Foundation only, no AppKit/SwiftUI
Sources/QDVCEmpirics/         the SwiftUI/AppKit app
Tests/EmpiricsCoreTests/      unit tests (and the sample generator)
tools/make_icon.py            regenerates Resources/AppIcon.{svg,icns}
scripts/build-app.sh          builds (with the newest Xcode), signs sandboxed
Resources/Info.plist          bundle id org.qdvc.empirics.mac
Resources/QDVCEmpirics.entitlements   sandbox, user-selected files, bookmarks; NO network
sample-workspace/             a worked example (regenerate, below)
sample-full-texts/            its full-texts
docs/                         DESIGN, FILE_FORMAT, this guide
```

`EmpiricsCore` builds and tests on Linux (Swift 5.10 or later), which is how
it was developed; the app target is declared on macOS only.

### 1.0 Toolchain

Build with full Xcode. From Xcode 27, SwiftUI's `@State` is a macro whose
implementation (the SwiftUIMacros compiler plugin) ships with Xcode, so the
Command Line Tools or a swift.org toolchain fail with "plugin for module
'SwiftUIMacros' not found". `scripts/build-app.sh` therefore sets
`DEVELOPER_DIR` to the newest installed Xcode when `xcode-select` points at
the Command Line Tools, runs `xcrun swift`, prints the compiler and SDK
versions, and warns when the SDK is older than 26 (no Liquid Glass). An
explicit `DEVELOPER_DIR` is respected. The same block is used in the other
QDVC macOS apps; keep them in step.

AppKit decides on Liquid Glass from the SDK version recorded in the
executable's `LC_BUILD_VERSION`. `swift build` records the deployment target
there (`sdk 14.0`), so after copying the executable into the bundle the
script rewrites that field with `vtool -set-build-version macos <minos>
<sdk> -replace`, before signing. Check with `vtool -show-build`.

The script then signs ad hoc **with** `Resources/QDVCEmpirics.entitlements`
and fails if the signature lacks the sandbox or carries a network
entitlement. `--no-sandbox` exists only for troubleshooting.

### 1.1 App icon

`tools/make_icon.py` writes `Resources/AppIcon.svg` and
`Resources/AppIcon.icns` (needs `rsvg-convert`). "Sage" palette, Apple's
template geometry, matching the other QDVC apps. `--preview` also writes
`build/icon-preview.png`.

### 1.2 Sample

`MAKE_SAMPLE=$PWD swift test --filter MakeSampleTests` rebuilds
`sample-workspace/` and `sample-full-texts/` through the core API (so they
are always valid), with repeatable keys and timestamps, so regenerating
changes nothing unless the generator changed.

## 2. Modules

`EmpiricsCore`:

| File | Responsibility |
| --- | --- |
| `YAML.swift` | the YAML subset (from QDVC Response Letter): `YAMLNode`, parser with line numbers, emitter |
| `Model.swift` | `Keys`, `Stamp`, `EmpiricalFile`, `TextSpan`, `CodeSelection` (with `ProtocolSegment`), `QDACode` (with `CodeLink`), `Evidence`, `Interrelation`, `LayerKind`, `CodingLayer`, `StudyProtocol`, `ProtocolItem`, `AprioriCode`, `AttributeSheet`, `AttributeSheetQuestion`, `ResponseSheet`, `SheetCompleteness`, people, `SpeakerMap`, `Project` |
| `Editing.swift` | every change and its rules (`RuleError`): layers and their kinds, selections, irrelevance, codes, evidence, cycles, layer moves (`component`, `move`), attribute sheets, sheets; `ProjectIndex`, `WorkingIDs` |
| `Deductive.swift` | changes to what is defined beforehand and applied on deductive layers: protocols and segments, a priori codes and their evidence, links from open and axial codes, Framework Matrix summaries |
| `Workspace.swift` | loading (with repairs and notes, `repairKinds` for the deductive/inductive rules), saving by `WorkspacePart`, `changedParts`, `signature` |
| `Encoding.swift` | each file's YAML, both ways |
| `Interlocutors.swift` | `TurnDetector`: speaker candidates, turns, name suggestions |
| `FullTexts.swift` | read-only `FullTexts`, `TextNormaliser`, `Anchoring` (re-finding selections) |
| `SHA256.swift` | fingerprints |
| `RealNames.swift` | `CSV` reader and writer; `RealNames` (mapping files, templates) |
| `Reports.swift` | `CodingChart` (columns, levels, links, crossing reduction), `AttributeSheetReport` (rows, CSV) |

`WorkingIDs` (in `Editing.swift`) numbers items alphabetically per kind;
`ProjectIndex.workingID` holds them, `AppModel.wid(_:)` reads them.

Core type names avoid SwiftUI, AppKit and Foundation names (QDVC Progress hit
`GridRow`, Response Letter `Section`): hence `QDACode`, `CodingLayer`,
`CodeSelection`, `TextSpan`, and `StudyProtocol` (Objective-C has a
`Protocol` class). Check new public names.

The app (`QDVCEmpirics`): `EmpiricsApp` (scenes, delegate, menus),
`Welcome`, `AppModel` (state, opening, saving, undo, navigation and the
Working Area, documents, interlocutors, response sheets, real names;
`@Observable`, main actor), `AppModel+Coding` (coding operations, files,
layers), `DeviceStore` (UserDefaults and security-scoped bookmarks),
`ContentView` (split view, sidebar and Working Area, toolbar, document page),
`Items` (one-line items: `ItemLine`, `WorkingBadge`, `InspectorTitle`, item
titles, symbols and colours), `ListPages` (the list pages, SwiftUI Tables),
`ItemPages` (code, attribute sheet and person pages), `CodingChart` and
`AttributeSheetReport` (the Reporting pages),
`TextCodingView` (text view, decorations, margins, keys), `PDFCodingView`,
`CodingBar` (coding bar, quick codes, code palette), `InspectorView` (routed
by page), `EvidencePane`, `AttributeSheetsPage` (the attribute sheet editor and the
response sheet), `Pages` (Layers, Project Settings, real names, pages still
to come), `Sheets`,
`UpdateFileSheet` (updating a file from a new version of its full-text),
`QuestionColumns` (attribute sheet questions as table columns: the cells, the
sort comparator and the column-customization binding that saves the
choice in the workspace),
`SettingsView`, `Style`.

Navigation is `AppModel.sidebar` (a `SidebarItem`: a list page or an item's
page). Open item pages with `show(_:)`, which adds them to the Working
Area; `sidebarChanged(from:)` (from the view's `onChange`) records history
and resets per-page state. Tables bind their selection to
`AppModel.tableSelection`, which the inspector reads.

**The main window copies QDVC Response Letter's structure exactly**
(ContentView.swift), because departures from it threw the sidebar's rows up
under the window buttons whenever certain pages opened, and resizing didn't
repair it:

- `ContentView` holds the title, subtitle, sheets and alerts around
  `MainView`; `MainView` is a `NavigationSplitView` with no
  column-visibility binding, the `.inspector`, and the `.toolbar` on the
  split view with trailing (`.primaryAction`) items only. Items with
  placement `.navigation` went into the sidebar's title bar, beside the
  window buttons; Back and Forward are in the Go menu instead.
- `DetailView` puts the page in an overlay of a flexible `Color.clear`
  with a min/max frame, and clips it: a page can never be wider than the
  detail column. (A page whose content had a larger minimum width, such as
  the coding bar with all its quick codes, used to widen the detail column
  past the window and cut off the sidebar on the left.) The notice banner
  is a `.safeAreaInset(edge: .top)` over the page, not a view stacked above
  it.
- **Every page starts with its scrolling content at the top**: a `Table`,
  a ScrollView, the document. Bars go below (the tables' footers, the
  coding bar). The glitch followed the pages that put a fixed header (a
  title and description) above their table; pages starting with a scroll
  view never did it. SwiftUI `Table` itself is fine, as in Response Letter.

Toolbar items, table cells and context-menu content take the model
directly (`MainToolbar(model:)`, `LayerMenu(model:)`, `RealNameCell(model:)`,
`FileTableMenu(model:keys:)`…) rather than reading
`@Environment(AppModel.self)`: when the toolbar was rebuilt, an item that
read it found no model and the app trapped in
`EnvironmentValues.subscript.getter`.

Sidebar rows are kept to one line each, and the Working Area has no
drag-to-reorder (Move Up and Move Down are in its context menu).

Long closure chains are slow to type-check: split sorts into statements
(the compiler gave up on one chain in `CodingBar`).

### 2.1 Changes, undo and saving

- `perform(name) { project in … }` applies a change through the core's
  functions (which throw `RuleError` when a rule would break; the message is
  shown in a banner) and registers the previous project with the window's
  undo manager. Undo swaps whole snapshots; `Project` is a value type, so a
  snapshot costs little.
- `edit { … }` is for typing: saved, not on Edit › Undo.
- After either, `Workspace.changedParts(from:to:)` works out which files
  differ; they are written 0.6 s later, when the app is left, and on quit.
  Identical content is never rewritten.
- On returning to the app, the workspace's signature (paths, sizes, dates)
  is compared and the project reloaded if something outside changed it.

### 2.2 Documents

`AppModel.pages(_:)` reads a full-text (through `FullTexts`, read-only) into
`DocumentStore`, which is not observed; `documentsRevision` tells views to
refresh. `prepareDocument(_:)` also checks the fingerprint and re-anchors
selections (`Anchoring.reanchor`) once per session per file. When a change
points a file at another full-text or another version of it (updating a
file, and undoing or redoing that), `commit` drops the file's cached text
(`forgetStaleDocuments`) so it is read and checked again.

Updating a file (`UpdateFileSheet`) checks first and changes nothing until
confirmed: `Anchoring.check` says what would become of every selection
(unchanged, moved, unchecked, not found), taking the text to look for from
the stored quote or, failing that, from the version the selections were made
on (the cached copy or the file itself, if either still has the catalogued
fingerprint); `Anchoring.apply` then moves them, in one `perform`. The new
version must be inside the full-texts folder (nothing is copied there) and of
the same sort, text or PDF. Views must never
change the project while being drawn: loading pages is safe (it only fills
the cache), fingerprint checks happen in `prepareDocument`, called from
`.task` and navigation.

### 2.3 Layout

Pages adapt to the width they are given rather than asking for one: the
file page through `ColumnLayout` (TextCodingView.swift), the coding bar
through `ViewThatFits` with a minimal last variant inside an overlay
(CodingBar.swift), the reports by scrolling both ways.

The rules of QDVC Response Letter's docs/MAINTENANCE.md §2.3 apply: no text
view lives in an AppKit scroll view (it is sized by `sizeThatFits` inside a
SwiftUI ScrollView, `FillingScroll`); `sizeThatFits` measures only real
widths and caches by width and text version; margins are SwiftUI views
placed from the layout manager and reported asynchronously, only when the
text, width or decorations change (otherwise the page re-lays itself out
continuously).

## 3. Network

Nothing may touch the network:

- No dependencies (`Package.swift` must not declare any).
- No networking API anywhere in `Sources/` (URLSession, Network, WebKit,
  `openURL`, sharing services…). `NetworkPolicyTests` scans the sources and
  fails on any of them; extend its list rather than working around it.
- The entitlements file has no `com.apple.security.network.*`; the build
  script checks the signed app.
- Text views turn off link and data detection and Writing Tools, and their
  context menus drop Look Up, Translate, Search With, Share and Services;
  PDF link clicks are swallowed; `NSApp.servicesMenu` is nil.

## 4. Full-texts

- `FullTexts` (core) has no write method; keep it that way.
- PDFs are loaded with `PDFDocument(data:)` and never written; highlights
  use `highlightedSelections`, not annotations.
- The full-texts folder's bookmark is created with
  `.securityScopeAllowOnlyReadAccess`.
- Consent forms are shown in-app (`ConsentViewer`), never opened in another
  app.
- Real-name mapping files are read with `FullTexts`; the names stay in
  `AppModel.realNames` (memory only). Never write real names to the
  workspace, UserDefaults or logs.
- New projects refuse nested workspace and full-texts folders.

## 5. Behaviour to preserve (tests)

- SHA-256 matches the standard test vectors.
- Turn detection handles the messy transcript of the specification
  (capitals, colons, blank lines), inline "Name: text", timestamps and
  Markdown emphasis, and does not take sentences for headers.
- Irrelevant text is never evidence: no coding over it, no marking evidence
  irrelevant, irrelevant selections merge, rules are per layer.
- Axial evidence refuses cycles and the wrong kind.
- Moving to a layer moves the whole component, and is refused on irrelevant
  clashes.
- Response sheets refuse to save without blocking answers; new options join
  non-strict lists.
- A workspace saves and loads to an identical project; saving again writes
  nothing; deleting a layer removes its folder; hand-written YAML is read;
  conflict markers are reported; quotes are dropped when switched off.
- Re-anchoring moves selections whose text moved (also when only its white
  space changed) and reports lost ones; checking a new version finds
  irrelevant text through the old version, keeps what it can't check, and
  applying it deletes lost selections only when asked.
- Answers to a question come back in researcher order; deleting a question
  or attribute sheet stops showing it as a table column; `table_columns` survives
  the round trip.
- Attribute sheets can be associated with interviewees (only when they apply to
  them); deleting the interviewee deletes the sheets about them.
- New projects have Main Deductive and Main Inductive; the last layer of
  each kind can't be deleted or change kind; a layer's kind is fixed once it
  has coding; open and axial codes only in inductive layers; coding moves
  only between layers of the same kind (a deductive selection takes its a
  priori evidence along).
- Protocol segments only on deductive layers, one protocol per file per
  layer, never a priori evidence or irrelevant; deleting an item deletes its
  segments; deleting a protocol frees its files.
- A priori evidence only from deductive, relevant, non-segment selections;
  links can't repeat; Framework Matrix summaries only on deductive layers,
  an empty summary clears the cell; deleting an a priori code drops its
  evidence, links and column but keeps the selections.
- A layer without a kind loads as inductive, and a project missing a kind of
  layer gets one (with a note).
- The sample builds, saves and loads back unchanged.
- Working identifiers are alphabetical per kind (natural number order) and
  renumber when an item is added.
- The Coding Chart puts axial codes by level, links files to open codes and
  codes to the axial codes they are evidence for (also across columns),
  leaves out unlinked items unless asked; the Attribute Sheet Report lists sheets
  and unanswered items, and its CSV quotes fields properly.
- No networking API in the sources, no dependencies.

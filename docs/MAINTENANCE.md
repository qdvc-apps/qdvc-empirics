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
| `Model.swift` | `Keys`, `Stamp`, `EmpiricalFile`, `TextSpan`, `CodeSelection`, `QDACode`, `Evidence`, `Interrelation`, `CodingLayer`, `Codebook`, `CodebookQuestion`, `ResponseSheet`, `SheetCompleteness`, people, `SpeakerMap`, `Project` |
| `Editing.swift` | every change and its rules (`RuleError`): selections, irrelevance, codes, evidence, cycles, layer moves (`component`, `move`), codebooks, sheets; `ProjectIndex` |
| `Workspace.swift` | loading (with repairs and notes), saving by `WorkspacePart`, `changedParts`, `signature` |
| `Encoding.swift` | each file's YAML, both ways |
| `Interlocutors.swift` | `TurnDetector`: speaker candidates, turns, name suggestions |
| `FullTexts.swift` | read-only `FullTexts`, `TextNormaliser`, `Anchoring` (re-finding selections) |
| `SHA256.swift` | fingerprints |
| `RealNames.swift` | `CSV` reader and writer; `RealNames` (mapping files, templates) |

Core type names avoid SwiftUI, AppKit and Foundation names (QDVC Progress hit
`GridRow`, Response Letter `Section`): hence `QDACode`, `CodingLayer`,
`CodeSelection`, `TextSpan`. Check new public names.

The app (`QDVCEmpirics`): `EmpiricsApp` (scenes, delegate, menus),
`Welcome`, `AppModel` (state, opening, saving, undo, navigation and the
Working Area, documents, interlocutors, response sheets, real names;
`@Observable`, main actor), `AppModel+Coding` (coding operations, files,
layers), `DeviceStore` (UserDefaults and security-scoped bookmarks),
`ContentView` (split view, sidebar and Working Area, toolbar, document page),
`ListPages` (the tables), `ItemPages` (code, codebook and person pages),
`TextCodingView` (text view, decorations, margins, keys), `PDFCodingView`,
`CodingBar` (coding bar, quick codes, code palette), `InspectorView` (routed
by page), `EvidencePane`, `CodebooksPage` (the codebook editor and the
response sheet), `Pages` (Layers, Project Settings, real names), `Sheets`,
`SettingsView`, `Style`.

Navigation is `AppModel.sidebar` (a `SidebarItem`: a list page or an item's
page). Open item pages with `show(_:)`, which adds them to the Working
Area; `sidebarChanged(from:)` (from the view's `onChange`) records history
and resets per-page state. Tables bind their selection to
`AppModel.tableSelection`, which the inspector reads.

**Never read `@Environment(AppModel.self)` in views that SwiftUI hosts
apart from the window's view tree:** toolbar items, table cells and
context-menu content. Pass the model in (`MainToolbar(model:)`,
`LayerMenu(model:)`, `RealNameCell(model:)`, `ConsentStatus(model:)`,
`WorkingAreaRow(model:)`), or capture it in a local constant in `body`.
When the toolbar was rebuilt after a sidebar click, a toolbar item with
`@Environment(AppModel.self)` found no model and the app trapped in
`EnvironmentValues.subscript.getter`. The toolbar is attached to the
detail column, not the split view: attached to the split view, items with
placement `.navigation` (Back, Forward) went into the sidebar's title bar
beside the window buttons. Each split-view column also gets the model
injected again with `.environment(model)`.

SwiftUI Tables and long closure chains are slow to type-check: give table
columns explicit row types (`{ (f: EmpiricalFile) in … }`), keep cells
simple, and split sorts into statements (the compiler gave up on one chain
in `CodingBar`).

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
selections (`Anchoring.reanchor`) once per session per file. Views must never
change the project while being drawn: loading pages is safe (it only fills
the cache), fingerprint checks happen in `prepareDocument`, called from
`.task` and navigation.

### 2.3 Layout

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
- Re-anchoring moves selections whose text moved and reports lost ones.
- The sample builds, saves and loads back unchanged.
- No networking API in the sources, no dependencies.

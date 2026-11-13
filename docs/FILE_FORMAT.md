# QDVC Empirics — Workspace File Format (format 1)

A project's workspace is a folder. Every file is UTF-8 YAML with `\n` line
endings, small, and written only when its content changes, so the folder
works well in Git: researchers coding different files, or in different
layers, touch different files.

```
My project/
  project.yml                          title, settings, layer order
  files/f-1a2b3c4d.yml                 one catalogue entry per full-text
  protocols/pr-1a2b3c4d.yml            one per protocol, with its items
  apriori-codes/apc-1a2b3c4d.yml       one per a priori code (its codebook entry)
  attribute-sheets/ast-1a2b3c4d.yml    one per attribute sheet
  attribute-responses/ast-1a2b3c4d/f-1a2b3c4d--r-1a2b3c4d.yml
                                       one response sheet per attribute sheet,
                                       item (file, code or interviewee) and
                                       researcher
  layers/l-1a2b3c4d/layer.yml          a layer's kind, name and description
  layers/l-1a2b3c4d/selections/f-1a2b3c4d.yml
                                       the layer's selections in one file (and,
                                       deductive, the protocol it follows there)
  layers/l-1a2b3c4d/codes/c-1a2b3c4d.yml
                                       inductive: one per code (open or theorising)
  layers/l-1a2b3c4d/apriori/apc-1a2b3c4d.yml
                                       deductive: the layer's evidence for one
                                       a priori code
  layers/l-1a2b3c4d/framework/f-1a2b3c4d.yml
                                       deductive: Framework Matrix summaries for
                                       one row (a file or an interviewee)
  people/researchers.yml
  people/interviewees.yml
  interlocutors/f-1a2b3c4d.yml         speaker labels → people, per transcript
```

What is defined beforehand (protocols, a priori codes, attribute sheets)
belongs to the project, at the top level. What a coder makes lives in their
layer, one small file per file, code or row, so two coders working in
different layers never touch the same file.

The full-texts (transcripts, PDFs, consent forms) are **never** in the
workspace. They live in a separate full-texts folder, whose location each
Mac remembers for itself; paths in the workspace are relative to it.

## Keys

Everything has a **stable key**: a prefix, a hyphen and eight lowercase hex
digits. Keys never change, so renaming touches one file and links survive.

| Prefix | Entity |
| --- | --- |
| `p-` | project |
| `f-` | empirical file |
| `l-` | layer |
| `s-` | selection |
| `c-` | code (open or theorising) |
| `x-` | interrelation |
| `ln-` | link from an open or theorising code to an a priori code |
| `pr-` | protocol |
| `pi-` | protocol item |
| `apc-` | a priori code |
| `ast-` | attribute sheet |
| `q-` | attribute sheet question |
| `r-` | researcher |
| `i-` | interviewee |

The **working identifiers** shown in the app (`EF 31`, `PR 2`, `AST 4`,
`APC 7`, `OC 23`, `TC 12`, `R 5`, `I 17`) are not stored anywhere: they are worked out from the
titles and names each time (alphabetical order, per kind), so they change as
items come and go. Refer to items by key in anything that must last.

## YAML

The app reads and writes a subset of YAML (no anchors, aliases, tags or
multiple documents; see Sources/EmpiricsCore/YAML.swift). Multi-line text is
written as a literal block (`|`); everything else on one line, quoted only
when needed. Values are read as text, so `true`, `2026-03-14` and `0042` are
never reinterpreted. Unknown keys are ignored, missing ones take defaults.
A file containing Git conflict markers (`<<<<<<<`) is reported, not read.

## project.yml

```yaml
format: 1                         # newer formats are refused
app: QDVC Empirics
key: p-5a3f1c20                   # per-Mac settings (full-texts folder) hang on this
title: Using QDA software
description: Optional, may be multi-line
store_quotes: true                # write selection text into the workspace
interlocutor_layer: true
interrelation_types: [Compare, Contrast]
real_names:                       # optional: mapping files, relative to the full-texts folder
  researchers: private/researchers-real-names.csv
  interviewees: private/interviewees-real-names.csv
table_columns:                    # optional: attribute sheet questions shown as table columns
  files: [q-0a1b2c3d, q-4e5f6a7b] # per table: files | interviewees | open-codes | theorising-codes
  interviewees: [q-9c8d7e6f]
table_layouts:                    # optional: how those tables' question columns are arranged
  files: "{\"…\"}"               # per table: SwiftUI's column customization as JSON (order, widths)
layers: [l-0a1b2c3d, l-4e5f6a7b]  # display order; folders not listed are added
```

`table_layouts` is written by the app when question columns are moved or
resized, and read back as written; it is not meant to be edited by hand (a
value the app can't read is ignored, and the columns take their default
order). Which questions show is `table_columns`, whatever the layout says.

## files/<f-key>.yml

```yaml
key: f-1e7e0001
path: interviews/SF-2026-01.txt   # relative to the full-texts folder, "/" separators
kind: text                        # text | markdown | pdf
title: Interview with John Smith  # optional (else the file name)
date: 2026-03-14                  # optional, YYYY-MM-DD
id: SF-2026-01                    # optional, the researcher's own ID
status: coded                     # not-started | in-progress | coded
fingerprint: sha256:fb3a…         # of the file's bytes, to notice changes
attribute_sheets: [ast-c0debee1]  # associated attribute sheets
added: 2026-11-01
rotations:                        # optional, PDFs only: pages shown turned, for reading
  3: 90                           # page number (from 1): 90, 180 or 270 degrees clockwise
```

`rotations` only says how a page is shown (a table printed sideways, say):
it is added to the page's own rotation in the PDF, the PDF itself is never
changed, and selections, which count into the page's text, are unaffected.

## layers/<l-key>/layer.yml

```yaml
key: l-0a1b2c3d
kind: inductive                   # deductive | inductive (missing: inductive)
name: Main Inductive
description: First reading
researcher: r-a11ce000            # optional
```

A **deductive** layer applies what was defined beforehand: protocol
segments, evidence for a priori codes, Framework Matrix summaries. An
**inductive** layer holds what emerges from the data: open and theorising codes.
A project always has at least one layer of each kind (on load, a missing
kind gets a layer called Main Deductive or Main Inductive, with a note); new
projects start with both. A layer's kind can change only while nothing is
coded in it. Content of the wrong kind for its layer is ignored on load,
with a note.

## layers/<l-key>/selections/<f-key>.yml

The layer's selections in one file, in order, and (deductive layers) the
protocol the file follows in this layer. The file exists while either is
there.

```yaml
file: f-1e7e0001
protocol: pr-1a7e0001             # deductive layers: at most one per file per layer
selections:
  - key: s-1d9c13bd
    start: 396                    # UTF-16 offset into the normalised text
    length: 50
    quote: The existing crop of QDA software is very limited.
    by: r-a11ce000
    created: 2026-11-01T09:00:00Z
  - key: s-455ecf3d
    irrelevant: true              # never evidence; never overlaps evidence
    start: 117
    length: 53
  - key: s-77aa0012               # a PDF selection
    page: 2                       # one-based
    start: 120                    # offset into PDFKit's text of that page
    length: 64
  - key: s-2b000001               # a protocol segment (deductive layers)
    item: pi-0a000001             # an item of the file's protocol
    part: prompt                  # prompt | response
    start: 312
    length: 64
  - key: s-77aa0013               # across pages: one span per page
    spans:
      - page: 2
        start: 1800
        length: 120
      - page: 3
        start: 0
        length: 85
```

**Offsets.** For text and Markdown files, offsets count UTF-16 code units
(the units of NSString) in the file's text after normalisation: decoded as
UTF-8 (or UTF-16 with a byte-order mark, else Windows-1252), byte-order mark
removed, line endings as `\n`. For PDFs, they count into each page's text as
PDFKit extracts it.

**Quotes** are written while `store_quotes` is true (and never for irrelevant
selections). When a file's fingerprint changes, selections whose quote is no
longer at their position are looked for by their quote (exactly, or else
ignoring differences in white space) and moved; the quote then takes the
text found. Updating a file from a new version (File › Update Empirical
File…) changes its `path`, `kind` (text or Markdown) and `fingerprint` and
moves its selections the same way; its key, and everything that refers to
it, stay.

**Editing a text file in place** (right-click selected text › Edit Text…)
writes the full-text itself (in its own encoding, byte-order mark and line
endings) and updates the workspace to match, in every layer: selections
after the edit move by the change in length; selections overlapping it take
in the new text (irrelevant ones stop at its edges, so irrelevant text never
comes to overlap other selections); a selection left with no text is
deleted, with its evidence links; stored quotes are taken again from the new
text; and the file's `fingerprint` becomes that of the new bytes.

**Rules** (enforced by the app): within a layer, irrelevant selections never
overlap selections that aren't irrelevant, and are never evidence. On a
deductive layer, a selection is a protocol segment or evidence for a priori
codes, never both, and a segment's item belongs to the protocol its file
follows there. If a hand edit breaks these rules, what breaks them is
ignored on load (with a note): the evidence is dropped, or the segment
becomes a plain selection.

## layers/<l-key>/codes/<c-key>.yml

```yaml
key: c-843835de
kind: open                        # open | theorising
name: Fatigue in long sessions
colour: "#E55934"
description: Tiredness, eyes, pace over hours of coding.
evidence:                         # open: selections; theorising: codes (no cycles)
  - selection: s-1405501d         # theorising codes write "code: c-…"
    memo: Reading comfort matters over hours.   # the interpretation memo
  - selection: s-6092745d
comments:
  - Self-report and observation point the same way.
questions: ["Is this fatigue, or a shift from coding to interpreting?"]
links:                            # to a priori codes (where data meets theory)
  - key: ln-7c01ab22
    apriori_code: apc-7a0e0001
    type: refines                 # confirms | refines | extends | contradicts | not-covered
    memo: Ease of use is learnt over time, not a fixed perception.
interrelations:
  - key: x-bf8eb359
    type: Compare                 # one of project.yml's types (or any text)
    members: [s-1405501d, s-6092745d]   # evidence of this code
    description: |-
      Interview and observation agree…
attribute_sheets: [ast-c0debee2]
by: r-a11ce000
created: 2026-11-01T09:00:00Z
```

Codes exist only in inductive layers. Evidence must be in the code's own
layer. `evidence: [s-…]` (keys alone) is accepted when written by hand.

## layers/<l-key>/apriori/<apc-key>.yml

A deductive layer's evidence for one a priori code (the code itself is
defined once, in `apriori-codes/`).

```yaml
apriori_code: apc-7a0e0001
evidence:
  - selection: s-3c000001         # a selection of this layer: not irrelevant,
    memo: Effort falls with the shortcuts.   # not a protocol segment
  - selection: s-3c000002
```

## layers/<l-key>/framework/<row>.yml

A deductive layer's Framework Matrix summaries for one row: an empirical
file or an interviewee. Each cell is a column (an a priori code or a
protocol item) and the researcher's summary of the row's data for it. A
file's cells for protocol items are the summaries written in the bubbles
under its protocol labels, which the Protocol Report shows.

```yaml
row: f-1e7e0001
cells:
  - column: apc-7a0e0001
    summary: Still learning the interface; the shortcuts make long sessions easier.
  - column: pi-0a000001             # a protocol item
    summary: An improvement on other QDA tools, but still learning the interface.
```

## protocols/<pr-key>.yml

A predefined set of items expected to occur, in part or in whole, in the
files that follow it: an interview protocol, the structure of an article.

```yaml
key: pr-1a7e0001
title: Interview protocol
description: The questions planned for every interview.
items:                            # a flat list, in order
  - key: pi-0a000001
    label: Interface              # short, for margins and headings
    text: Do you think the user interface is user friendly?
  - key: pi-0a000002
    label: Long sessions
```

## apriori-codes/<apc-key>.yml

An a priori code: defined before coding, and its codebook entry. Applied on
deductive layers (`layers/<l-key>/apriori/`).

```yaml
key: apc-7a0e0001
name: Perceived ease of use
colour: "#F78FB3"
definition: The degree to which a researcher believes that using the tool would be free of effort.
included: Learning the tool, effort, friction, fluency, speed of use.
excluded: Whether the tool makes the research better (see Perceived usefulness).
example: I barely touch the mouse now.
counter_example: It's certainly an improvement over alternatives.
source: Davis, F. D. (1989). MIS Quarterly, 13(3), 319–340.
by: r-a11ce000
created: 2026-11-01T09:00:00Z
```

Every field but `name` is optional.

## attribute-sheets/<ast-key>.yml

```yaml
key: ast-c0debee1
title: Interview context
description: Answer once per interview.
applies_to: [files]               # files | interviewees | open-codes | theorising-codes
questions:                        # in order
  - key: q-5e771460
    label: Setting                # at most 16 characters
    text: How was the interview conducted?
    type: choose-one              # text | choose-one | choose-many
    options: [In person, Video call, Phone]
    strict: true                  # false: options may be added while coding
    requirement: mandatory-blocking   # | mandatory-non-blocking | optional
```

## attribute-responses/<ast-key>/<target>[--<r-key>].yml

One response sheet: an attribute sheet's answers about one file, code or
interviewee, by one researcher (the `--r-…` part is absent when the project lists no
researchers).

```yaml
attribute_sheet: ast-c0debee1
target: f-1e7e0001
researcher: r-a11ce000
updated: 2026-11-01T09:30:00Z
answers:
  - question: q-5e771460
    label: Setting                # for reading only; the key is what counts
    answer: Video call            # choose-one
  - question: q-d0a7104e
    label: Duration
    text: About 40 minutes        # text
  - question: q-70b1c500
    label: Topics
    answers: [Interface, Fatigue] # choose-many
```

A sheet can't be saved while a mandatory, blocking question is unanswered.

## people/researchers.yml, people/interviewees.yml

```yaml
# First and last names are pseudonyms. Real names, if mapped, stay in the full-texts folder.
researchers:
  - key: r-a11ce000
    first: Alice                  # pseudonyms
    last: Bob
```

```yaml
# First and last names are pseudonyms. Real names (if mapped) and consent forms stay in the full-texts folder.
interviewees:
  - key: i-05a17400
    first: John                   # pseudonyms
    last: Smith
    consent_form: consent/john-smith.pdf   # relative to the full-texts folder
    attribute_sheets: [ast-c0debee3]       # associated attribute sheets (optional)
```

## interlocutors/<f-key>.yml

```yaml
file: f-1e7e0001
speakers:                         # labels as written in the header lines
  - label: Alice Bob
    person: r-a11ce000
  - label: John Smith
    person: i-05a17400
not_speakers: [okay]              # header-like lines that aren't speakers
```

Labels compare without case, extra spaces, colons or emphasis marks, so
`ALICE BOB:` and `Alice Bob` are one speaker. Turns themselves are not
stored: they are found from the text each time.

## Real-name mapping files (in the full-texts folder)

Not part of the workspace: CSV files kept in the full-texts folder, one for
researchers and one for interviewees, chosen in Project Settings. The app
only reads them. Columns are found by their headings:

```
key,pseudonym,real_first_name,real_last_name
i-05a17400,John Smith,Jonathan,Example-Participant
```

Rows are matched by `key`, or by `pseudonym` when the key is blank. A single
`real_name` column may replace the first and last name columns. Project
Settings › Save Template writes a file listing everyone's key and pseudonym,
to fill in (it never overwrites an existing file).

## Not in the workspace

Kept on each Mac (the app's UserDefaults), never in Git: recent projects;
per project, the full-texts folder (a security-scoped bookmark),
this Mac's researcher, the Working Area, the page last open, the active and
hidden layers, quick codes per layer and reading positions. Settings ›
Privacy forgets them.

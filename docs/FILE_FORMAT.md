# QDVC Empirics — Workspace File Format (format 1)

A project's workspace is a folder. Every file is UTF-8 YAML with `\n` line
endings, small, and written only when its content changes, so the folder
works well in Git: researchers coding different files, or in different
layers, touch different files.

```
My project/
  project.yml                          title, settings, layer order
  files/f-1a2b3c4d.yml                 one catalogue entry per full-text
  codebooks/cb-1a2b3c4d.yml            one per codebook
  responses/cb-1a2b3c4d/f-1a2b3c4d--r-1a2b3c4d.yml
                                       one response sheet per codebook, item
                                       (file or code) and researcher
  layers/l-1a2b3c4d/layer.yml          a layer's name and description
  layers/l-1a2b3c4d/selections/f-1a2b3c4d.yml
                                       the layer's selections in one file
  layers/l-1a2b3c4d/codes/c-1a2b3c4d.yml
                                       one per code (open or axial)
  people/researchers.yml
  people/interviewees.yml
  interlocutors/f-1a2b3c4d.yml         speaker labels → people, per transcript
```

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
| `c-` | code (open or axial) |
| `x-` | interrelation |
| `cb-` | codebook |
| `q-` | codebook question |
| `r-` | researcher |
| `i-` | interviewee |

The **working identifiers** shown in the app (`EF 31`, `CB 4`, `OC 23`,
`AC 12`, `R 5`, `I 17`) are not stored anywhere: they are worked out from the
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
layers: [l-0a1b2c3d, l-4e5f6a7b]  # display order; folders not listed are added
```

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
codebooks: [cb-c0debee1]          # associated codebooks
added: 2026-11-01
```

## layers/<l-key>/layer.yml

```yaml
key: l-0a1b2c3d
name: Main
description: First reading
researcher: r-a11ce000            # optional
```

## layers/<l-key>/selections/<f-key>.yml

The layer's selections in one file, in order.

```yaml
file: f-1e7e0001
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
longer at their position are looked for by their quote and moved.

**Rules** (enforced by the app): within a layer, irrelevant selections never
overlap selections that aren't irrelevant, and are never evidence. If a hand
edit makes an irrelevant selection evidence, that evidence is ignored on
load (with a note).

## layers/<l-key>/codes/<c-key>.yml

```yaml
key: c-843835de
kind: open                        # open | axial
name: Fatigue in long sessions
colour: "#E55934"
description: Tiredness, eyes, pace over hours of coding.
evidence:                         # open: selections; axial: codes (no cycles)
  - selection: s-1405501d         # axial codes write "code: c-…"
    memo: Reading comfort matters over hours.   # the interpretation memo
  - selection: s-6092745d
comments:
  - Self-report and observation point the same way.
questions: ["Is this fatigue, or a shift from coding to interpreting?"]
interrelations:
  - key: x-bf8eb359
    type: Compare                 # one of project.yml's types (or any text)
    members: [s-1405501d, s-6092745d]   # evidence of this code
    description: |-
      Interview and observation agree…
codebooks: [cb-c0debee2]
by: r-a11ce000
created: 2026-11-01T09:00:00Z
```

Evidence must be in the code's own layer. `evidence: [s-…]` (keys alone) is
accepted when written by hand.

## codebooks/<cb-key>.yml

```yaml
key: cb-c0debee1
title: Interview context
description: Answer once per interview.
applies_to: [files]               # files | open-codes | axial-codes
questions:                        # in order
  - key: q-5e771460
    label: Setting                # at most 16 characters
    text: How was the interview conducted?
    type: choose-one              # text | choose-one | choose-many
    options: [In person, Video call, Phone]
    strict: true                  # false: options may be added while coding
    requirement: mandatory-blocking   # | mandatory-non-blocking | optional
```

## responses/<cb-key>/<target>[--<r-key>].yml

One response sheet: a codebook's answers about one file or code, by one
researcher (the `--r-…` part is absent when the project lists no
researchers).

```yaml
codebook: cb-c0debee1
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
per project, the full-texts folder (a read-only security-scoped bookmark),
this Mac's researcher, the Working Area, the page last open, the active and
hidden layers, quick codes per layer and reading positions. Settings ›
Privacy forgets them.

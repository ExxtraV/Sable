# Typing in a long manuscript: baseline

This records how long one keystroke takes in a single-file manuscript before any incremental-styling work, so that
work has a number to beat. It was measured on the commit that added `scripts/bench-typing.swift`.

## How it was measured

`scripts/bench-typing.swift` generates a novel with `scripts/typing-fixture.swift` (seeded, so it's the same text every
run). The novel has front matter, chapters and scenes, about a third dialogue, emphasis of every kind, lists, task
lists, quotes, notes, fenced code, a table, footnotes, links, images, emoji, and a cast of character, place, and lore
names that have cards. The benchmark hosts `WritingTextView` the way the app does: `WritingScrollView`,
`RoomClipView`, and the real `NativeEditor.Coordinator` as delegate, with a stand-in for the SwiftUI binding and the
document's undo manager, all in an offscreen window. It puts the caret in the middle of the book and types `tide `
over and over.

- **Edit** is `insertText` returning. That covers the coordinator copying the text into the binding,
  `decorate()` (full `styleMarkdown`, focus, prose suggestions), caret centering, and the layout AppKit does to keep
  the caret in view.
- **Layout** finishes laying out the visible page. **Draw** draws it into a bitmap.
- **Full restyle** is a setting change (what a theme, font, or size change costs).
- Profiles: **defaults** is a new install writing inside a project: prose suggestions on, names highlighted with
  shimmer, typewriter "room", marker dimming on, sentence colors off, focus off. **Everything on** adds every
  sentence-color class, gradient paragraph focus, smart typography, and typewriter "center".

Run it yourself with the commands in [CONTRIBUTING.md](../../CONTRIBUTING.md). Compare numbers only against runs on the
same Mac.

Machine: Mac16,8, Apple M4 Pro, 24 GB, macOS 26.6 (25G5065a), 12 cores. Built with `-O`. (This run used
`swiftc` against the macOS 26.5 SDK, because SwiftPM in Command Line Tools 27 can't build the package
locally. CI is unaffected.)

## Results

### Per keystroke, defaults (ms)

| Words | Characters | Edit (median) | Layout (median) | Draw (median) | Total median | Total p90 | Total max | Full restyle |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,177 | 60,551 | 46.7 | 0.20 | 2.68 | **49.5** | 51.0 | 63.5 | 52.6 |
| 50,140 | 298,071 | 217.1 | 0.71 | 2.37 | **220.2** | 220.7 | 221.5 | 264.6 |
| 100,304 | 596,110 | 430.0 | 0.71 | 2.13 | **432.8** | 435.9 | 438.8 | 542.9 |

### Per keystroke, everything on (ms)

| Words | Characters | Edit (median) | Layout (median) | Draw (median) | Total median | Total p90 | Total max | Full restyle |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,177 | 60,551 | 132.6 | 0.36 | 3.47 | **136.6** | 138.1 | 149.5 | 137.3 |
| 50,140 | 298,071 | 791.9 | 1.80 | 3.44 | **797.1** | 801.8 | 846.0 | 800.3 |
| 100,304 | 596,110 | 1,793.8 | 1.94 | 3.39 | **1,799.0** | 1,808.1 | 1,808.9 | 1,817.2 |

### Whole-document passes behind each keystroke (ms, median)

| Words | Markdown spans | Sentence colors (all) | Names | Prose suggestions | Focus paragraph | Word count | Binding compare + copy |
|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,177 | 25.1 | 58.9 | 3.05 | 2.49 | 1.25 | 2.92 | 2.44 |
| 50,140 | 123.4 | 306.4 | 15.1 | 10.8 | 5.98 | 14.4 | 12.4 |
| 100,304 | 244.8 | 644.5 | 29.4 | 21.2 | 13.1 | 29.0 | 24.6 |

## What the numbers say

- **A keystroke costs the same as a full restyle.** It already misses a 60 Hz frame (16.7 ms) at 10k words with
  the default settings. At 100k words it takes 433 ms, so typing visibly stalls. With everything on it takes 1.8 s.
- **Cost grows linearly with the document.** Every column scales about 10× from 10k to 100k words, so the cause is
  whole-document work on every keystroke. Nothing here is quadratic.
- **Parsing Markdown is most of the default cost.** `MarkdownSyntax.spans` takes 245 of the 433 ms at 100k words.
  The rest is applying the attributes and invalidating layout across the whole storage (`setAttributes` over
  everything), name matching (29), prose suggestions (21), the binding compare and copy (25), and clearing focus
  attributes over the whole document.
- **Sentence colors are the most expensive feature.** `SentenceStructure.words` takes 645 ms at 100k words. It runs
  NLTagger over the whole text and also calls `MarkdownSyntax.spans` a second time, so "everything on" pays for
  spans twice.
- **Layout and drawing are already cheap** (under 4 ms), because only the visible page is laid out and drawn. The
  AppKit layout that happens inside the edit is small next to the styling work.

### Not captured by this benchmark

The benchmark has no SwiftUI view tree, so per-keystroke work on the SwiftUI side isn't in the tables. Estimated from
the pass timings at 100k words, it adds roughly **130 ms** more per keystroke in the real app:

- `QuillApp.swift`: the status bar's `count` (`Prose.wordCount`), `sessionWords` (a second count), and
  `onChange(of: document.text)` → `recordWritingProgress` (a third count): about 3 × 29 ms.
- The status bar's "cuts" label runs `Prose.suggestions` over the whole text: about 21 ms.
- `NativeEditor.updateNSView` compares `editor.string != text` again: about 25 ms.
- SwiftUI's own diffing of views that depend on `document.text`, and `FileDocument` change tracking.

Also not measured: the continuous spell and grammar checker (it runs asynchronously on AppKit's schedule), shimmer
ticks (24 per second, visible names only), and key-event dispatch.

## The bar for Session B

Session B (incremental restyling and coalesced binding updates) passes when:

1. `scripts/check-incremental-styling.swift` stays green. It makes about 2,900 random edits across three
   configurations, and after each one the attributes must match a from-scratch restyle run by run. It passes
   against the code measured here.
2. At 100k words, the median **total per keystroke is under 16 ms for the defaults profile**. Everything on should
   be close to its 10k-word time. Cost should track the edited paragraph, not the document: the 10k, 50k, and 100k
   rows should be about equal.
3. Full restyles on setting changes may stay whole-document, but shouldn't get slower.
4. The SwiftUI-side whole-document passes listed above are coalesced, so they stop running on every keystroke.

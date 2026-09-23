# Typing in a long manuscript: baseline and after

This records how long one keystroke takes in a single-file manuscript, before the incremental-styling work (the
baseline, measured on the commit that added `scripts/bench-typing.swift`) and after it ([After incremental
styling](#after-incremental-styling)).

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

## Baseline results

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

Session B (incremental restyling and coalesced binding updates) passes when the following hold. See [After incremental
styling](#after-incremental-styling) for the result: all four are met for the defaults profile. "Everything on" came
down from 1.8 s to 23.5 ms at 100k words, but still grows with length, for the reasons listed there.

1. `scripts/check-incremental-styling.swift` stays green. It makes about 2,900 random edits across three
   configurations, and after each one the attributes must match a from-scratch restyle run by run. It passes
   against the code measured here.
2. At 100k words, the median **total per keystroke is under 16 ms for the defaults profile**. Everything on should
   be close to its 10k-word time. Cost should track the edited paragraph, not the document: the 10k, 50k, and 100k
   rows should be about equal.
3. Full restyles on setting changes may stay whole-document, but shouldn't get slower.
4. The SwiftUI-side whole-document passes listed above are coalesced, so they stop running on every keystroke.

## After incremental styling

Same Mac, same fixture, same `-O` build and `swiftc` against the macOS 26.5 SDK, measured on the commit that added
incremental styling. The benchmark now also reports the *binding flush* (handing typing to SwiftUI's copy of the
text, with the status bar's counts; it happens after a pause, not per keystroke, so it isn't in the total) and how
many measured keystrokes restyled only a region.

### Before and after, total median per keystroke (ms)

| Words | Defaults before | Defaults after | Everything on before | Everything on after |
|---:|---:|---:|---:|---:|
| 10,177 | 49.5 | **4.63** | 136.6 | **10.4** |
| 50,140 | 220.2 | **4.94** | 797.1 | **15.0** |
| 100,304 | 432.8 | **5.11** | 1,799.0 | **23.5** |

### Full restyle (a theme, font, size, or setting change), before and after (ms)

| Words | Defaults before | Defaults after | Everything on before | Everything on after |
|---:|---:|---:|---:|---:|
| 10,177 | 52.6 | 23.5 | 137.3 | 82.6 |
| 50,140 | 264.6 | 134.5 | 800.3 | 487.6 |
| 100,304 | 542.9 | 284.5 | 1,817.2 | 1,156.4 |

Full restyles got faster because the Markdown grammar's regular expressions are now compiled once instead of on every
pass, sentence colors reuse the spans the styling pass already found instead of parsing the text a second time, and
the check for words inside code and markers is a binary search instead of a scan of every marker per word.

### Per keystroke, defaults (ms)

| Words | Characters | Edit (median) | Layout (median) | Draw (median) | Total median | Total p90 | Total max | Binding flush (median) | Region passes | Full restyle |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,177 | 60,551 | 1.59 | 0.60 | 2.43 | **4.63** | 5.02 | 5.58 | 0.01 | 30 of 30 | 23.5 |
| 50,140 | 298,071 | 1.59 | 0.70 | 2.62 | **4.94** | 5.16 | 5.29 | 0.01 | 15 of 15 | 134.5 |
| 100,304 | 596,110 | 2.00 | 0.76 | 2.34 | **5.11** | 5.19 | 5.81 | 0.02 | 10 of 10 | 284.5 |

### Per keystroke, everything on (ms)

| Words | Characters | Edit (median) | Layout (median) | Draw (median) | Total median | Total p90 | Total max | Binding flush (median) | Region passes | Full restyle |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 10,177 | 60,551 | 6.31 | 0.00 | 3.83 | **10.4** | 11.7 | 12.1 | 0.02 | 30 of 30 | 82.6 |
| 50,140 | 298,071 | 9.24 | 1.84 | 3.69 | **15.0** | 15.5 | 15.6 | 0.02 | 15 of 15 | 487.6 |
| 100,304 | 596,110 | 20.3 | 0.01 | 3.22 | **23.5** | 23.9 | 23.9 | 0.02 | 10 of 10 | 1,156.4 |

The whole-document pass timings are unchanged (they measure the passes themselves), except the focus paragraph, which
now reads only the lines around the caret: 13.1 ms at 100k words before, under 0.01 ms after.

### What changed

- **The editor restyles only the lines around an edit.** The text storage reports where characters changed.
  `IncrementalStyling.plan` widens that to whole lines plus one neighbor on each side and restyles just that region:
  attributes, Markdown spans, sentence colors, names, and prose suggestions. A full restyle is the same code run
  over the whole text, so the two can't drift apart. This works because every pattern in the grammar stops at a
  line break, except fenced code and `<!-- -->` notes. Those are remembered between passes and moved with each edit.
- **Some edits still restyle everything,** because they can change meaning far away:
  - a changed line that holds `` ``` `` or `~~~` (before or after the edit)
  - a `<!--` or `-->` within three characters of the change
  - in a file that starts with `---`: any edit up to the end of the front matter, or a changed line holding `---`
  - a setting change (theme, font, size, spacing, colors, names, marker dimming)

  Setext-shaped lines (`===`, `---` under text) need no special case: this grammar treats them line by line, and the
  neighboring lines are always restyled together anyway.
- **Paragraph focus reads only the paragraph around the caret,** and it no longer clears dimming across the whole
  text on every keystroke when focus is off. That clearing was also why AppKit's own edit processing had grown with
  document length.
- **Typing reaches SwiftUI in batches.** The binding gets the text 0.3 s after typing pauses, and at least every 1.5 s
  during continuous typing. It is also handed over at once before anything else can read it:
  - saving, closing, duplicating, or printing (the editor registers with the document as an `NSEditor`)
  - any click, any ⌘ or ⌃ shortcut, or a menu opening
  - the editor losing focus or leaving its window
  - the app going to the background or quitting
  - every SwiftUI handler that reads or replaces the document's text

  A SwiftUI redraw with the binding's older text never overwrites pending typing. An autosave that runs while typing
  is pending leaves the document marked as changed.
- **The status bar stops counting.** The editor keeps the word count up to date region by region, and keeps the
  prose suggestions it already found. It publishes both with each flush, so the word count, the "cuts" label, and the
  writing record no longer run whole-document passes. "Unsaved changes" and fading scene tags follow a per-keystroke
  typing signal instead of the text, so they still react to the first keystroke.

### Found by profiling the app itself

The benchmark hosts the editor without SwiftUI, so two problems only showed up in the running app, with a 100k-word
file and the maintainer's own settings (all sentence colors, center typing, 145% zoom). Both are fixed:

- **Hiccups when typing paused.** Each time the editor handed the text over, SwiftUI compared the old and new
  manuscript, character by character with Unicode normalization. It did this in every view that took the text as an
  input: the writing desk, the cards, the scene-tag strip, and the writing-progress `onChange`. Each compare took
  tens of milliseconds. Those views now take `LiveText`, which compares by a revision number the editor bumps on each
  flush.
- **Gradient focus dimmed the paragraph being written.** It read the scroll position in the clip view's coordinates
  but treated it as the text view's, which is wrong whenever AppKit leaves the text view's frame origin away from
  zero (center typing does). Restyling the whole document on every keystroke used to hide this, by laying the page out
  again each time. It now converts between the two, as `centerCaretIfNeeded` already did.

  `check-incremental-styling.swift` now also requires that the paragraph being written is never dimmed. The
  comparison with a fresh view couldn't catch this, because both views run the same focus code. The new
  requirement fails against the old focus code.

### Where the remaining time goes

The defaults profile no longer depends on document length: the 10k, 50k, and 100k rows are within 0.5 ms of each
other. "Everything on" still grows with length. Measured one piece at a time at 100k words, a keystroke with
everything on spends about:

- 2.7 ms restyling the region, the same as at 10k.
- 3–5 ms in paragraph focus dimming, which paints temporary colors over the whole text on each keystroke: two large
  ranges in classic mode, the floor ranges plus nearby lines with the gradient.
- About 4 ms in AppKit's own edit processing, which slows down in proportion to the number of temporary-attribute
  runs that dimming leaves.
- About 5 ms in "center" typewriter mode, whose caret centering lays out the rest of the document after each edit
  (`ensureLayout(for:)` in `centerCaretIfNeeded`) so it can clamp to the true end of the page.

### Not optimized, and why

- **Paragraph focus dimming over the whole text.** Painting only the lines near the screen, and repainting on scroll,
  would make it constant. But it changes what the dimming covers, and that is what the random-edit check compares
  against. It deserves its own change with its own check.
- **"Center" mode's full layout after each edit.** Laying out only up to the target line would do. But this is the
  scrolling code that was tuned by hand with the centering debug log, and it should be changed where it can be
  tested by hand on its own.
- **AppKit's layout, drawing, and spell and grammar checking.** These are unchanged and already cheap per keystroke
  (under 4 ms together). Spell checking runs on AppKit's own schedule.
- **Full restyles stay whole-document.** They are faster than before, but still proportional to the text: about
  285 ms at 100k words with the defaults, 1.2 s with everything on. They happen when a file opens or a setting
  changes.
- **The text snapshot.** Each styling pass copies the text once (an immutable copy AppKit caches; about 0.05 ms at
  100k words). That is how an edit's old lines are compared with its new ones.
- **SwiftUI views that take the document's text.** The writing desk's outline, the manuscript tab's count, and the
  cards now run once per flush instead of per keystroke, but aren't incremental. The outline itself got cheaper:
  `MarkdownSyntax.headings` now parses only lines that start like a heading.

### How correctness is checked

- `scripts/check-styling-ranges.swift` compares every range-limited function with a verbatim copy of the
  whole-text code it replaced. It runs on random Markdown built to hit fences, notes, front matter, `\r`, and U+2028.
  For every edit the planner would restyle as a region, it proves that nothing outside the region changed.
- `scripts/check-incremental-styling.swift` requires every attribute to match a from-scratch restyle after each
  random edit, including right after an IME composition is unmarked without a commit. (The editor now restyles
  that composition when it's unmarked, so the check no longer skips it.) It settles the binding each of the ways the
  app does, including real `NSDocument` saves, and requires the binding and status bar counts to match the editor.

This change was run with 5 extra seeds and a 20,000-edit soak (`QUILL_FUZZ_SEED=987654 QUILL_FUZZ_EDITS=20000`,
about 28,700 edits across the three configurations), all passing. `QUILL_FUZZ_SABOTAGE=1` still fails as it should.

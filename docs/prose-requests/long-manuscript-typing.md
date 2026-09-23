# Prose request: fast typing in long manuscripts

> How this works: each "##" heading is one piece of text Sable needs.
> Write your version under "Your text" and leave the heading alone. The
> drafts are deliberately over the top so they can never ship by accident.
> Claude uses only what's under "Your text", exactly as you wrote it.

## Release notes · next release · Typing in long manuscripts
- Where: docs/release-notes.md, one bullet in the next release's notes. The file
  still holds the 0.9.0 notes and has no section for the next release yet, so no
  PROSE-TODO marker was placed; paste this in when the next release's notes are written.
- Length: 1–2 sentences
- Must get across: typing stays instant however long the file is; a whole novel
  in one file no longer makes the editor lag. Nothing about how the page looks changed.
- Verified facts (measured on an M4 Pro, default settings, one keystroke from key to
  drawn page): a 100,000-word file went from about 430 ms to about 5 ms, and 10,000
  words from about 50 ms to about 5 ms; it now takes the same time at any length. With
  every feature on (sentence colors, paragraph focus, smart typography, centered typing)
  100,000 words went from about 1.8 s to about 24 ms. Changing a theme, font, or size in a
  100,000-word file also got faster (about 540 ms to about 285 ms with default settings).
  See docs/performance/typing-baseline.md for the exact numbers.
- Also true, if you want to mention it: the word count and "cuts" in the status bar,
  and the writing record, now update when you pause (within a third of a second, and at
  least every second and a half while you keep typing) instead of on every keystroke.
  "Unsaved changes" still appears on the first keystroke.

Draft (rewrite me):
> WARP SPEED TYPING!!! Your 100,000-word EPIC now flies faster than a caffeinated
> hummingbird on a rocket sled!!! Lag has been DESTROYED, OBLITERATED, SENT TO THE SHADOW REALM!!!

Your text:
>

## README · Where to customize · New source files
- Where: README.md, the "Where to customize" file list (near the
  `Sources/Quill/NativeEditor.swift` line). No marker placed, since the list is optional
  reading and CI would block on it.
- Length: two list items, one short phrase each, matching the list's style
- Must get across: `Sources/Quill/EditorStyling.swift` is where the editor applies
  Markdown styling, names, sentence colors, and prose suggestions (and restyles only the
  lines you're editing); `Sources/QuillCore/IncrementalStyling.swift` decides how much of
  the text an edit needs restyled.
- Verified facts: both files are new in this change; nothing else in the list moved.

Draft (rewrite me):
> - `Sources/Quill/EditorStyling.swift`: THE BEATING HEART OF ALL BEAUTIFUL TEXT!!!
> - `Sources/QuillCore/IncrementalStyling.swift`: a genius oracle that KNOWS which lines matter!!!

Your text:
>

## Note, no text needed · Sable Guide · "updating as you type"
- Where: docs/Sable Guide.md, line 29 ("your total word count (updating as you type)").
- Nothing to write unless you want to: the manuscript total still updates while you
  write, now at each pause (within a third of a second) rather than on every keystroke.
  Flagging it only in case "as you type" now reads as too strong to you.

Your text (leave empty to keep the Guide as it is):
>

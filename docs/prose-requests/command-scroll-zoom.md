# Prose request: zoom with Command and the mouse wheel

> How this works: each "##" heading is one piece of text Sable needs.
> Write your version under "Your text" and leave the heading alone. The
> drafts are deliberately over the top so they can never ship by accident.
> Claude uses only what's under "Your text", exactly as you wrote it.

Facts that hold for every item below:

- Hold ⌘ (Command) and turn a mouse's scroll wheel over the page: away from you zooms
  in, toward you zooms out, whatever the Scroll direction setting in System Settings.
- Each notch is 5%. Zoom snaps to whole 5% steps, stays between 65% and 200% (the
  same limits as ⌘+ / ⌘− and pinch), and the wheel stops at either end.
- It zooms the pane under the pointer, so with a document open beside the draft, each
  side zooms on its own (same as pinch and ⌘+ / ⌘−).
- Only a notched mouse wheel zooms. On a trackpad or Magic Mouse, ⌘ plus a two-finger
  scroll still just scrolls; pinch is the trackpad's way to zoom.
- The "Pinch to zoom" switch in Writing Style does not turn this off (it's only for
  pinching). There is no setting for it.
- A fast spin is applied in small batches (at most about 7 times a second) rather than
  on every notch, so it stays responsive in a long manuscript.
- Zoom changes the display only, never the Markdown.

## Sable Guide · Keyboard and gestures · Command-scroll zoom
- Where: docs/Sable Guide.md, after the "Pinch the trackpad to zoom…" paragraph
  (marked PROSE-TODO: guide-wheel-zoom). You may prefer to fold it into that paragraph
  instead; if so, say so and I'll replace the paragraph and drop the marker.
- Length: 1 sentence (or a reworded paragraph)
- Must get across: hold ⌘ and scroll a mouse wheel to zoom

Draft (rewrite me):
> SPIN TO WIN!!! Clamp down on that COMMAND KEY and CRANK your scroll wheel like a
> SLOT MACHINE of TYPOGRAPHY — your words will GROW and SHRINK at your COMMAND!!!

Your text:
>

## Sable Guide · Reading beside your draft · Each side zooms on its own
- Where: docs/Sable Guide.md, the "Open Beside Current Document" paragraph, the sentence
  "Each side scrolls and zooms on its own: pinch, or use ⌘+ and ⌘−, with the pointer over
  the one you want to scale." (marked PROSE-TODO: guide-parallel-zoom)
- Length: rewrite of that one sentence
- Must get across: ⌘-scrolling works per side too

Draft (rewrite me):
> Each side is its OWN SOVEREIGN ZOOM KINGDOM: pinch it, ⌘+ it, ⌘− it, or ⌘-SCROLL it
> into OBLIVION, and its neighbor won't even FLINCH!!!

Your text:
>

## Website · Guide · Command-scroll zoom
- Where: website/guide.html, after the "Pinch the trackpad to zoom…" paragraph under the
  shortcuts table (marked PROSE-TODO: site-wheel-zoom). Could also be a new table row
  ("⌘ + scroll" / "Zoom in or out") if you'd rather; say which.
- Length: 1 sentence, or one table row
- Must get across: hold ⌘ and scroll a mouse wheel to zoom

Draft (rewrite me):
> Your mouse wheel has been SECRETLY WAITING its whole life for this: hold ⌘ and
> UNLEASH THE ZOOM!!!

Your text:
>

## README · Features list · Command-scroll zoom
- Where: README.md, the bullet "Zoom with Command-Plus/Minus, reset with Command-0, or
  pinch the trackpad. Pinch zoom can be disabled in Writing Style."
  (marked PROSE-TODO: readme-wheel-zoom)
- Length: rewrite of that bullet, 1–2 sentences
- Must get across: ⌘-scroll with a mouse wheel is a fourth way to zoom

Draft (rewrite me):
> Zoom with Command-Plus! Command-Minus! Command-0! PINCH! And NOW — COMMAND-SCROLL,
> the zoom method your INDEX FINGER has been DREAMING OF!!!

Your text:
>

## Release notes · next release · Command-scroll zoom
- Where: docs/release-notes.md, one bullet in the next release's notes. The file still
  holds the 0.9.0 notes and has no section for the next release yet, so no PROSE-TODO
  marker was placed; paste this in when the next release's notes are written.
- Length: 1 sentence
- Must get across: hold ⌘ and turn a mouse wheel to zoom the page; trackpads keep pinch

Draft (rewrite me):
> BREAKING: Mouse owners EVERYWHERE rejoice as ⌘-SCROLL ZOOM finally ARRIVES to end
> centuries of SQUINTING!!!

Your text:
>

## README · Where to customize · New source file
- Where: README.md, the "Where to customize" file list. No marker placed, since the list
  is optional reading and CI would block on it.
- Length: one list item, one short phrase, matching the list's style
- Must get across: `Sources/Quill/ZoomSteps.swift` holds the zoom limits and how the
  mouse wheel steps through them

Draft (rewrite me):
> - `Sources/Quill/ZoomSteps.swift`: the SACRED MATHEMATICS of ZOOM!!!

Your text:
>

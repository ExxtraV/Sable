# CLAUDE.md

Sable Markdown Writer is a native macOS (14+) SwiftUI/AppKit Markdown editor
for fiction writers. The module names Quill/QuillCore and the executable name
are intentionally unchanged from the old project name — don't rename them.

## Design philosophy

Sable isn't minimal for minimalism's sake. It's built against multitasking.
People believe multitasking makes them more productive, but in writing it only
distracts; a writer needs to stay on one task. Judge every feature by whether
it keeps the writer on the page. Story tools stay out of the way until called:
no notifications, badges, or panels competing for attention while writing.
Describe Sable in terms of focus and single-tasking, never as "minimalist".

## Public-facing prose

The maintainer writes all public-facing prose: README, website, release notes,
the Sable Guide, App Store and launch copy, the sample project's story text,
and longer in-app explanations. Claude never writes final copy for these.
Instead:

- Create `docs/prose-requests/<task>.md` from `docs/prose-requests/TEMPLATE.md`:
  one `##` heading per item, each with where it appears, a length limit, what
  it must get across, verified facts, a deliberately over-the-top "Draft
  (rewrite me)", and an empty "Your text" slot.
- Mark each spot in the real files with `PROSE-TODO: <item-id>`. CI fails if a
  marker is left in README.md, website/, docs/ (outside prose-requests/), or
  Sources/.
- When the maintainer returns the file, paste their text exactly as written,
  remove the markers, and delete the request file. Never polish or rewrite
  their prose; only flag factual errors or length overruns, and ask first.
- Claude may write short UI labels, menu items, and error messages, but lists
  them in the task summary for review. Technical and contributor docs
  (CONTRIBUTING, ARCHITECTURE, format specs) are Claude's to write.

## Build

```
sh scripts/build-app.sh
```

Output: `build/Sable Markdown Writer.app`. If the module cache complains, run
`rm -rf .build/module-cache`.

## Checks

Standalone checks live in `scripts/check-*.swift`, listed in both
`.github/workflows/check.yml` and the README. A check's compile file list
must not depend on files outside that list. New logic needs a check (or an
XCTest once test targets exist).

## User data & privacy

Users' files are sacred: everything stays plain Markdown and ordinary
folders. Never introduce a proprietary format. Any operation that rewrites or
moves several user files takes a safety snapshot first (see `Revisions.swift`).
No telemetry, analytics, accounts, or network calls besides the Sparkle
update feed. No generative-AI features.

## Naming

Never add the maintainer's personal name, portfolio, or personal domain
anywhere — code, docs, website, metadata, bundle IDs. Credit the project as
"Sable" or the GitHub account ExxtraV.

## Dependencies and secrets

Sparkle is the only dependency; ask before adding another. Its private key
never goes in the repo, chat, logs, or a file Claude reads.

## Style

Match the surrounding code's style, comment density, and naming. Prefer
small focused files. Respect Reduce Motion, keyboard access, and VoiceOver
labels in any new UI.

## Untrusted input

Treat every file Sable opens or imports (Markdown, Word/RTF/HTML, pasted
content, Scrivener packages, theme files) as untrusted: no network loads, no
scripts, only http/https/mailto links, malformed input fails gracefully.

## Docs

When user-visible behavior changes, create a prose request (see Public-facing
prose) instead of updating the README, website/, release notes, or Guide
directly.

## Testing & wrap-up

After a significant change, build the app and open it so the maintainer can
test by hand (tell them to quit any older running copy first). End every task
with a plain-language summary: what changed, what could go wrong, how it was
tested.

## Git

gh isn't installed. When asked for a PR, push the feature branch and give the
github.com/ExxtraV/Sable/pull/new/<branch> link. main is protected; never push
to it. Never merge, publish a release, or change GitHub settings without
asking first.

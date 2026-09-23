# CLAUDE.md

Sable Markdown Writer is a native macOS (14+) SwiftUI/AppKit Markdown editor
for fiction writers. The module names Quill/QuillCore and the executable name
are intentionally unchanged from the old project name — don't rename them.

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
"Sable" or the GitHub account ExxtraV. Sparkle is the only dependency; ask
before adding another, and never let its private key land in the repo, chat,
logs, or a file Claude reads.

## Style

Match the surrounding code's style, comment density, and naming. Prefer
small focused files. Respect Reduce Motion, keyboard access, and VoiceOver
labels in any new UI.

## Untrusted input

Treat every file Sable opens or imports (Markdown, Word/RTF/HTML, pasted
content, Scrivener packages, theme files) as untrusted: no network loads, no
scripts, only http/https/mailto links, malformed input fails gracefully.

## Docs

When user-visible behavior changes, update `docs/release-notes.md`, the
README feature text, and `website/` if it mentions that feature.

## Testing & wrap-up

After a significant change, build the app and open it so the maintainer can
test by hand (tell them to quit any older running copy first). End every task
with a plain-language summary: what changed, what could go wrong, how it was
tested.

## Never without asking

Never push, merge, publish a release, or change GitHub settings without
asking first.

gh isn't installed. When asked for a PR, push the feature branch and 
give the pull/new link. main is protected, so never push to it.

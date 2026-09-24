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

Who writes what:

- **Claude writes GitHub-facing material and the app's own text:** the
  README, release notes (`docs/release-notes.md`, which also become the
  GitHub release text), CHANGELOG, CONTRIBUTING and other repo docs, issue
  templates, the Sable Guide (`docs/Sable Guide.md` and the website's guide
  page), the website's privacy page, the Markdown Cheat Sheet, sample and
  example story text, and in-app explanatory text. The maintainer may rewrite
  any of these later.
- **Every Claude-written piece is labeled, for transparency.** The README ends
  with "_This README is written by Claude Code._" Each version's release notes
  end with "_Release notes written by Claude Code._" The Sable Guide, sample
  and example files, the privacy page, and the Cheat Sheet open with a
  "written by Claude Code" line. The About panel (`NSHumanReadableCopyright`
  in Info.plist) covers the scattered in-app help text. Keep these labels
  when editing, and add one to any new Claude-written document. When the
  maintainer rewrites a piece in their own words, remove its label.
- **The maintainer writes everything else on the website** (every page except
  the guide, privacy page, blog posts, FAQ, meta descriptions, the press
  kit), plus launch and social posts, press emails, and App Store listings.
  Claude never writes final copy for any of these. Instead:

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

When user-visible behavior changes, update the README, release notes, Sable
Guide (both copies), and in-app text directly, keeping their "written by
Claude Code" labels. Create a prose request (see Public-facing prose) for
anything else in website/.

## Testing & wrap-up

After a significant change, build the app and open it so the maintainer can
test by hand (tell them to quit any older running copy first). End every task
with a plain-language summary: what changed, what could go wrong, how it was
tested.

## Git

gh is installed and signed in (Homebrew, /opt/homebrew/bin). When asked for a
PR, push the feature branch, open it with `gh pr create`, and check CI with
`gh pr checks`. main is protected; never push to it. Never merge, publish a release, or change GitHub settings without
asking first.

# Contributing to Sable Markdown Writer

Sable is a SwiftPM package (`Quill`/`QuillCore`) plus a set of shell and Python scripts under `scripts/`. This guide covers building it, running the checks, and how a change gets from a branch into `main`.

## Prerequisites

- macOS, with Apple Swift 6 tools (Xcode or the Command Line Tools) and a macOS SDK.
- Sparkle is the only third-party dependency; SwiftPM downloads its pinned binary framework, so local editing needs no service keys or accounts.

## Build

```sh
sh scripts/build-app.sh
swift test
```

`scripts/build-app.sh` builds a release binary with SwiftPM, packages it with Sparkle into `build/Sable Markdown Writer.app`, and ad-hoc signs it — no Apple Developer account needed. If the module cache complains on a clean checkout, clear it with `rm -rf .build/module-cache` and rebuild.

`swift test` runs `Tests/QuillCoreTests` and requires Xcode's XCTest framework. If you only have the Command Line Tools, use the standalone checks below instead.

### Command Line Tools 27.0

Command Line Tools 27.0 (Swift 6.4, macOS 27 SDK) without Xcode can't build Sable out of the box. `scripts/build-app.sh` works around the two problems below, but only when `xcode-select -p` points at the Command Line Tools. CI and anyone with Xcode are unaffected.

- **The macOS 27 SDK needs Xcode's SwiftUI macros.** In that SDK, SwiftUI's `@State` is a macro implemented by the `SwiftUIMacros` compiler plugin. Xcode ships that plugin; the Command Line Tools don't (their `usr/lib/swift/host/plugins` has only the Observation, Swift, and Testing macros). Every `@State` then fails with "plugin for module 'SwiftUIMacros' not found". The script picks the newest installed SDK whose SwiftUI doesn't need the plugin (26.5 today) and prints a `note:` naming it. You can override it by setting `SDKROOT` yourself. The real fix is to install Xcode or wait for a Command Line Tools release that includes the plugin. Once `usr/lib/swift/host/plugins/libSwiftUIMacros.dylib` exists, the script stops pinning.
- **A leftover SDK folder stops Swift Build.** Swift 6.4's default build system, Swift Build, reads every `SDKs/*.sdk` folder when it starts. If any of them has no `SDKSettings.plist`, it fails before compiling anything with "Could not initialize build system … Unknown error parsing property list", and setting `SDKROOT` doesn't help. The native build system never reads them. The one seen so far was a partial `MacOSX26.0.sdk` that no installer package owns (`pkgutil --file-info` lists none). When the script finds a folder like that, it prints the command to delete it (`sudo rm -rf …`) and falls back to `--build-system native`. That build system is deprecated and will be removed in a future SwiftPM, so treat it as a stopgap and delete the folder.

The standalone checks compile SwiftUI sources with `swiftc`, so on these tools, export the same SDK before running them. With Swift 6.4, also build the checks' release output with the native build system, because Swift Build uses a different output layout (`.build/out/Products/Release`, no `Modules/` or `QuillCore.build/`):

```sh
export SDKROOT=$(xcrun --sdk macosx26.5 --show-sdk-path)
QUILL_CHECK_BUILD=$(swift build -c release --build-system native --show-bin-path)
```

## How the check scripts work

Most of Sable's regression coverage lives outside XCTest, in `scripts/check-*.swift`. Each one is a small, self-contained `main`-style Swift file that exercises one area of the app (Markdown parsing, the folder browser, export, and so on) with plain assertions. You compile a check together with the exact source files it depends on using `swiftc`, then run the resulting binary directly — no test framework or simulator required, which is also why these checks can run with just the Command Line Tools.

Two things to know before adding or changing one:

- **A check's compile list is exact.** `swiftc` is given only the source files a check needs; a file outside that list can't be referenced. If you add a dependency to code under test, add the new file to every check command (here, in `.github/workflows/check.yml`, and in `Where to customize` in the README) that compiles it.
- **Some checks need release build artifacts.** Checks that exercise `Quill` app code (not just `QuillCore`) link against `.o` files or `Modules` from a `swift build -c release` output directory, because they use types built as part of the app target. Build first, then point `-I`/the `.o` glob at that directory (see the commands below — substitute `x86_64-apple-macosx` for `arm64-apple-macosx` on Intel).

`.github/workflows/check.yml` is the source of truth for exactly which checks run in CI and in what order; the first block below mirrors it exactly.

### Core checks (no build required, run in CI)

```sh
swiftc -O Sources/QuillCore/MarkdownSyntax.swift Sources/QuillCore/MarkdownEditing.swift Sources/QuillCore/MarkdownDocument.swift Sources/QuillCore/IncrementalStyling.swift Sources/QuillCore/Prose.swift Sources/QuillCore/FocusParagraph.swift Sources/QuillCore/SentenceStructure.swift scripts/check-styling-ranges.swift -o /tmp/quill-styling-range-checks && /tmp/quill-styling-range-checks
swiftc Sources/QuillCore/MarkdownEditing.swift Sources/QuillCore/MarkdownDocument.swift scripts/check-markdown-editing.swift -o /tmp/quill-markdown-editing-checks && /tmp/quill-markdown-editing-checks
swiftc Sources/Quill/Import.swift scripts/check-import.swift -o /tmp/quill-import-checks && /tmp/quill-import-checks
swiftc Sources/Quill/SafeFile.swift Sources/Quill/ProjectSearch.swift scripts/check-project-search.swift -o /tmp/quill-search-checks && /tmp/quill-search-checks
swiftc Sources/Quill/ZoomSteps.swift scripts/check-zoom-steps.swift -o /tmp/quill-zoom-step-checks && /tmp/quill-zoom-step-checks
swiftc Sources/Quill/SafeFile.swift scripts/check-file-safety.swift -o /tmp/quill-file-safety-checks && /tmp/quill-file-safety-checks
swiftc Sources/Quill/SafeFile.swift Sources/Quill/Revisions.swift scripts/check-revisions.swift -o /tmp/quill-revision-checks && /tmp/quill-revision-checks
swiftc Sources/Quill/ToolbarTools.swift scripts/check-toolbar.swift -o /tmp/quill-toolbar-checks && /tmp/quill-toolbar-checks
swiftc Sources/Quill/WritingHistory.swift scripts/check-writing-history.swift -o /tmp/quill-writing-history-checks && /tmp/quill-writing-history-checks

swiftc Sources/Quill/FolderBrowser.swift Sources/Quill/FictionProject.swift scripts/check-folder.swift -o /tmp/quill-folder-checks
/tmp/quill-folder-checks
swiftc Sources/Quill/FolderBrowser.swift Sources/Quill/FictionProject.swift scripts/check-fiction.swift -o /tmp/quill-fiction-checks
/tmp/quill-fiction-checks
swiftc -parse-as-library Sources/Quill/FolderBrowser.swift Sources/Quill/FictionProject.swift scripts/check-project-browser.swift -o /tmp/quill-project-browser-checks
/tmp/quill-project-browser-checks
```

Sample manuscript and world-note files these checks read are in `Examples/`.

### Additional local-only checks (not run in CI)

`check-editor.swift` and `check-reading-reference.swift` below cover most of `MarkdownSyntax.swift` and `Prose.swift` indirectly, but these two exercise them directly and are useful in isolation:

```sh
swiftc Sources/QuillCore/Prose.swift scripts/check-prose.swift -o /tmp/quill-prose-checks
/tmp/quill-prose-checks

swiftc Sources/QuillCore/MarkdownSyntax.swift Sources/QuillCore/MarkdownEditing.swift Sources/QuillCore/MarkdownDocument.swift Sources/QuillCore/IncrementalStyling.swift scripts/check-markdown.swift -o /tmp/quill-markdown-checks
/tmp/quill-markdown-checks
```

### Checks that need a release build (run in CI)

Build once, then run all of these against the same output directory:

```sh
QUILL_CHECK_BUILD=$(swift build -c release --show-bin-path)

swiftc -I "$QUILL_CHECK_BUILD/Modules" Sources/Quill/NativeEditor.swift Sources/Quill/EditorStyling.swift Sources/Quill/Import.swift Sources/Quill/WorkspaceExperience.swift Sources/Quill/ZoomSteps.swift Sources/Quill/FolderBrowser.swift Sources/Quill/FictionProject.swift Sources/Quill/WorldSidebar.swift Sources/Quill/WritingStyle.swift scripts/check-editor.swift "$QUILL_CHECK_BUILD"/QuillCore.build/*.o -o /tmp/quill-editor-checks
/tmp/quill-editor-checks

swiftc -O -I "$QUILL_CHECK_BUILD/Modules" Sources/Quill/NativeEditor.swift Sources/Quill/EditorStyling.swift Sources/Quill/Import.swift Sources/Quill/WorkspaceExperience.swift Sources/Quill/ZoomSteps.swift Sources/Quill/FolderBrowser.swift Sources/Quill/FictionProject.swift Sources/Quill/WorldSidebar.swift Sources/Quill/WritingStyle.swift scripts/typing-fixture.swift scripts/check-incremental-styling.swift "$QUILL_CHECK_BUILD"/QuillCore.build/*.o -o /tmp/quill-incremental-styling-checks
/tmp/quill-incremental-styling-checks

swiftc -O -I "$QUILL_CHECK_BUILD/Modules" Sources/Quill/NativeEditor.swift Sources/Quill/EditorStyling.swift Sources/Quill/Import.swift Sources/Quill/WorkspaceExperience.swift Sources/Quill/ZoomSteps.swift Sources/Quill/FolderBrowser.swift Sources/Quill/FictionProject.swift Sources/Quill/WorldSidebar.swift Sources/Quill/WritingStyle.swift scripts/typing-fixture.swift scripts/bench-typing.swift "$QUILL_CHECK_BUILD"/QuillCore.build/*.o -o /tmp/quill-typing-bench
/tmp/quill-typing-bench --smoke

swiftc -I "$QUILL_CHECK_BUILD/Modules" Sources/Quill/NativeEditor.swift Sources/Quill/EditorStyling.swift Sources/Quill/Import.swift Sources/Quill/ReadingView.swift Sources/Quill/SafeFile.swift Sources/Quill/ReferenceDocument.swift Sources/Quill/ReferencePane.swift Sources/Quill/WorkspaceExperience.swift Sources/Quill/ZoomSteps.swift Sources/Quill/FolderBrowser.swift Sources/Quill/FictionProject.swift Sources/Quill/WorldSidebar.swift Sources/Quill/WritingStyle.swift scripts/check-reading-reference.swift "$QUILL_CHECK_BUILD"/QuillCore.build/*.o -o /tmp/quill-parallel-checks
/tmp/quill-parallel-checks

swiftc -I "$QUILL_CHECK_BUILD/Modules" Sources/Quill/SafeFile.swift Sources/Quill/ProjectSearch.swift Sources/Quill/StoryTimeline.swift scripts/check-outline.swift "$QUILL_CHECK_BUILD"/QuillCore.build/*.o -o /tmp/quill-outline-checks
/tmp/quill-outline-checks

swiftc -I "$QUILL_CHECK_BUILD/Modules" Sources/Quill/Export.swift Sources/Quill/FictionProject.swift Sources/Quill/FolderBrowser.swift scripts/check-export.swift "$QUILL_CHECK_BUILD"/QuillCore.build/*.o -o /tmp/quill-export-checks
/tmp/quill-export-checks
```

`check-incremental-styling.swift` makes thousands of seeded random edits through the editor's real typing path and, after each one, compares every attribute against a from-scratch restyle of the same text. The editor hands typing to SwiftUI's copy of the text in batches, so the check also settles that copy each of the ways the app does (a pause, the idle timer, a real `NSDocument` save, a SwiftUI redraw with the older text, losing focus, an autosave while typing is pending) and then requires it, and the status bar's word and suggestion counts, to match the editor exactly. On a failure it prints the seed, the edit, and the first differing run, and saves the document to `$TMPDIR/quill-fuzz-failure.md`. `QUILL_FUZZ_SEED` and `QUILL_FUZZ_EDITS` change the seed and length for longer local runs; `QUILL_FUZZ_SABOTAGE=1` corrupts one attribute on purpose to confirm the comparison catches it. Random setting changes (theme, fonts, zoom, colors, sentence-color classes, names) are mixed into the edits, and each configuration ends with a run of setting changes that must all repaint from the spans and sentence tags the editor keeps between passes; `QUILL_FUZZ_SABOTAGE=cache` drops one kept span to confirm a stale cache is caught too. Both it and the benchmark share the generated manuscript in `scripts/typing-fixture.swift`.

`check-styling-ranges.swift` is the pure-logic half: on random Markdown built to hit every construct that crosses a line (fences, notes, front matter, `\r`, U+2028), it proves the range-limited grammar, prose review, sentence colors, outline, formatting exit, and focus paragraph find exactly what verbatim copies of the old whole-text code find, and that whenever the editor would restyle only a region, nothing outside it changes. `QUILL_RANGE_SEED` and `QUILL_RANGE_DOCUMENTS` change the seed and size of a run.

`bench-typing.swift` times keystrokes in a generated 10k-, 50k-, and 100k-word manuscript. CI runs it with `--smoke` only to keep it building; run it without flags for real numbers (`--out file.md` saves them, `--write-fixture path.md` writes the 100k-word manuscript to open in the app). [docs/performance/typing-baseline.md](docs/performance/typing-baseline.md) records the baseline.

### Python checks

A few checks validate the release pipeline itself rather than the app, and run with `python3` directly instead of `swiftc`:

```sh
python3 scripts/check-update-signatures.py
python3 scripts/check-release-modes.py
```

`scripts/check-release-config.py` and `scripts/check-appcast.py` run only as part of an actual release (`.github/workflows/release.yml`); they need release-only environment variables and aren't part of the regular check suite. `scripts/verify-update.swift` is invoked by `check-appcast.py`, not run directly.

`scripts/check-updater.swift` (a check that an unconfigured `AppUpdater` stays inactive) isn't currently wired into CI or the README. `AppUpdater` links Sparkle, so this check needs the same release-build/link approach as the checks above rather than a plain `swiftc` invocation. If you touch update-check logic, work out the right compile line for it and add it to `check.yml` alongside your change.

## Preview build

`sh scripts/build-preview.sh` builds a separate **Sable Markdown Writer Preview.app** with its own preferences and copied sample documents (`QUILL_PREVIEW`), so you can exercise first-run UI without disturbing your own writing folder or closing an existing draft.

## Branch and PR flow

1. Branch from `main`.
2. Make your change, adding or updating the relevant `scripts/check-*.swift` (and its compile-list entries above and in `.github/workflows/check.yml`) alongside it.
3. Run `sh scripts/build-app.sh` and the checks that cover the area you touched, at minimum.
4. Open a pull request against `main`. `.github/workflows/check.yml` runs the full build and check suite on every push and pull request; it must pass before merging.
5. Keep PRs focused — one change per PR makes review and rollback easier.

Releases (version bumps, signing, and publishing to GitHub Releases) are cut separately by a maintainer through `.github/workflows/release.yml`; contributors don't need to touch that workflow.

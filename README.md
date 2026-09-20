# New Quill Markdown Editor

A small, native Markdown editor for fiction, for macOS 14 or later. Source is included so the editor can evolve with your writing habits.

## Use

Open `build/Quill.app` after building. Use File → New or File → Open. Choose an existing UTF-8 `.md`, `.markdown`, or `.txt` file from your Mac or iCloud Drive. File → Save writes plain Markdown; prose overlays are never serialized. File coordination and document saving use Apple's SwiftUI `DocumentGroup` and `FileDocument`.

The writing surface now displays bold, italic, combined emphasis, headings, links, quotes, lists, inline code, fenced code, and strikethrough. Markdown markers remain visible in a subdued color. Fonts and visual attributes never become part of the saved text. Supported web/mail links have native link attributes.

Text is centered in a 680-point column by default, including in a maximized window. Settings lets you change the width and text size. The sidebar button (⌃⌘S) toggles the writing desk. Its outline options let you choose Chapters, Episodes, Scenes, Outline, or any custom label and filter to one heading level. Labels and filters are shared across documents and do not rename your actual headings.

The Files section's menu → Choose Writing Folder opens a persistent folder browser for Markdown and text files. Click folders to expand or collapse nested contents inline. The folder context menu can open a folder as the browsing root; use the up arrow to return, and click a file to open or select its native document tab. Each tab retains its document, undo history, and unsaved edits; switching never replaces a draft's contents. The menu also refreshes the listing or returns to the root folder. Search filters loaded, visible file rows, outline, and pinned-note names. Folder listings refresh manually; recursive full-text search is not implemented. Hidden files, symlinks, and packages are excluded.

The writing desk also keeps pinned world documents. Use + or drop `.md`, `.markdown`, or `.txt` files onto the sidebar. Pinned files are remembered between launches; unpinning does not delete the original. Selecting a note shows a bounded, read-only preview, with Reload and Open to edit controls. Use the search field to filter chapter and note names. The split-view button in a note preview opens a full-height, resizable reference pane beside the manuscript. The darker pane starts in a clean formatted reading view. Edit enables in-place Markdown editing beside your manuscript; Read returns to the formatted view. Save or ⌘S while editing saves the reference; returning to Read or closing the pane also requests a save. Native document handling tracks unsaved reference edits. A file already open in a writing tab must be closed there before editing as a reference, avoiding two competing editable copies. File rows also offer Read beside manuscript and Pin as world document in their context menu. An unavailable or moved note can be unpinned and added again. Previews do not update live; reload after external edits.

The Aa toolbar button opens font and style controls: five presets (Everyday / Georgia, Literary / Charter, Classic / Baskerville, Science fiction / Menlo, Manuscript / Courier New), a custom installed-font choice, size, page width, line spacing, and Dark / Light / Follow system appearance. Dark is the default. Styles are shared across documents; Markdown itself is unchanged. Some installed fonts do not include bold or italic faces, so available styles depend on the font.

Paragraph focus (target icon, ⇧⌘F) dims text outside the paragraph containing the cursor. It follows clicking, keyboard navigation, and typing. Paragraphs are separated by blank lines; soft line breaks stay in the same paragraph. Focus is per document window and never dims the reference pane or modifies text.

A session goal shows net words added since the document window opened. Set the goal in Settings, or set it to 0 to hide it. This is a per-window session count, not a daily history or a cross-device statistic.

The toolbar toggles prose suggestions. A light strikethrough marks words you may want to cut; the underlying text is unchanged. Right-click a suggestion to remove it explicitly or stop flagging that word. Settings lets you edit the comma-separated word/phrase list and font size. Ignoring a word updates this list for all documents.

macOS checks spelling and basic grammar. Right-click flagged text for available corrections. Automatic spelling replacement is disabled to protect intentional fiction wording and invented names. Availability and quality of grammar suggestions depend on macOS and language.

| Shortcut | Action |
| --- | --- |
| ⌘B | Wrap/unwrap selection in bold markers |
| ⌘I | Wrap/unwrap selection in italic markers |
| ⌘K | Insert Markdown link and select its URL |
| ⇧⌘H | Insert level-two heading at start of line |
| Tab or Escape | Move past closing formatting marks when the caret is at the end of a formatted run; also exit a link URL |
| Return | Move past closing formatting marks and insert a newline |
| ⌘\ | Leave formatting (same behavior as Tab) |
| ⌃⌘S | Toggle the writing desk sidebar |
| ⇧⌘F | Toggle paragraph focus |
| ⌘F | Find in manuscript |
| ⌘Z | Undo text changes |
| ⌘S | Save |
| ⌘, | Settings |

## Build

Requires Apple Swift 6 tools (Xcode or Command Line Tools) and a macOS SDK. Sparkle is the only third-party dependency; SwiftPM downloads its pinned binary framework. Local editing needs no service keys. Community updates require a Sparkle signing key and public release feed; Apple signing is optional.

```sh
sh scripts/build-app.sh
swift test
```

`swift test` requires Xcode's XCTest framework. With Command Line Tools only, run the equivalent standalone core checks:

```sh
swiftc Sources/QuillCore/Prose.swift scripts/check-prose.swift -o /tmp/quill-prose-checks
/tmp/quill-prose-checks
```

The build script creates a locally ad-hoc-signed app in `build/`. Community builds can be shared without Apple notarization, with a first-launch approval step on macOS. Optional Developer ID signing and notarization are supported.

## Scope and next steps

Validation: release build, prose checks, Markdown checks, folder-listing checks, and native editor checks pass. Native checks include focus tracking/clearing, font changes, source preservation, margins, Unicode, and formatting exits. Live UI verification in an isolated preview app confirmed custom outline naming and level filtering, folder-to-tab opening, switching back with edits and undo preserved, a styled side-by-side reference, paragraph dimming, font selection, and saving an existing document. The saved file was compared to the expected plain Markdown. System Save/Open confirmation buttons have appeared disabled during automated tests, so creating a new file through Save As and choosing a folder through the system picker still need direct-use verification. Cross-device iCloud syncing remains untested.

This is a first Mac prototype, not a finished cross-platform release. Prose review uses an editable list, not semantic judgment: a flagged word is not necessarily needless. The lightweight matcher excludes common fenced code, inline code, YAML front matter, URLs and inline link destinations; it is not a complete Markdown parser. The source highlighter is also a lightweight grammar, not a full CommonMark renderer; complex nesting, tables, images, and footnotes do not have a rich rendered view. Source mode retains Markdown markers; the Play button (⇧⌘R) switches to a formatted reading view. This reading view supports headings, emphasis, links, lists, quotes, and code, but is not a full CommonMark renderer. Word count is whitespace-based. Large-manuscript performance is not yet benchmarked.

iCloud access uses the system file picker and ordinary files, with no custom cloud database. Actual cross-device sync and conflict behavior still need testing with your iCloud account.

For an iPad edition, reuse `QuillCore` and the document model, add a UIKit text view and document-browser target, keyboard commands, and platform-specific spelling/review menus. The current package and editor are Mac-only; building and testing the iPad app requires full Xcode.

## Where to customize

- `Sources/QuillCore/Prose.swift`: prose matching and default word list.
- `Sources/QuillCore/FocusParagraph.swift`: Markdown paragraph boundaries for focus mode.
- `Sources/Quill/FolderBrowser.swift`: folder access, file filtering, navigation, and file menu.
- `Sources/Quill/ReferencePane.swift`: reference reading and editing split pane.
- `Sources/Quill/ReferenceDocument.swift`: tracked reference documents and saving.
- `Sources/Quill/ReadingView.swift`: native formatted reading view.
- `Sources/QuillCore/SentenceStructure.swift`: local parts-of-speech tagging.
- `Sources/Quill/WritingStyle.swift`: font, style, and outline controls.
- `Sources/QuillCore/MarkdownSyntax.swift`: source highlighting spans, chapter outline, and formatting exit logic.
- `Sources/Quill/WorldSidebar.swift`: pinned references and note previews.
- `Sources/Quill/NativeEditor.swift`: visual overlays, text behavior, context menu, and shortcuts.
- `Sources/Quill/QuillApp.swift`: document handling, settings, and interface.
- `Tests/QuillCoreTests`: Unicode and Markdown-protection checks.

Apple references: [document-based apps](https://developer.apple.com/documentation/swiftui/building-a-document-based-app/) and [native grammar checking](https://developer.apple.com/documentation/appkit/nstextview/isgrammarcheckingenabled).

## Additional checks

After building, the standalone Markdown and native editor checks can run without XCTest:

```sh
swiftc Sources/QuillCore/MarkdownSyntax.swift scripts/check-markdown.swift -o /tmp/quill-markdown-checks
/tmp/quill-markdown-checks
swiftc -I .build/arm64-apple-macosx/release/Modules Sources/Quill/NativeEditor.swift scripts/check-editor.swift .build/arm64-apple-macosx/release/QuillCore.build/*.o -o /tmp/quill-editor-checks
/tmp/quill-editor-checks
```

The last command uses the Apple Silicon build path; substitute `x86_64-apple-macosx` on Intel. Sample manuscript and world-note files are in `Examples/`.

For folder-listing checks:

```sh
swiftc Sources/Quill/FolderBrowser.swift scripts/check-folder.swift -o /tmp/quill-folder-checks
/tmp/quill-folder-checks
```

`sh scripts/build-preview.sh` builds a separate **New Quill Preview.app** with its own preferences and copied sample documents. Its `QUILL_PREVIEW` fixture setup is excluded from the normal app, allowing UI checks without closing an existing draft. Normal app updates take effect after saving work and restarting Quill.

## New in 0.4

Optional sentence coloring highlights nouns, verbs, adjectives, adverbs, and pronouns using macOS Natural Language locally. These are estimates, particularly for invented names, and are shown in source mode only. Color selections never alter your text. The toolbar now uses neutral colors and the reference pane stays dark. PDF and ebook export are deferred.

Standalone checks additionally verified clean reading, bold rendering, list rendering, icon decoding, parts-of-speech/code exclusions, reference document reuse, and exact native reference saves. Native document checks require access to macOS document services outside a restricted shell sandbox.

The generated logo and its prompt are in `Assets/LOGO.md`; the icon is packaged with the app.

Live 0.4 preview verification: expanded World → Places → Harbor.md without leaving the root; opened Northwatch beside an empty manuscript; edited its copied fixture and saved with ⌘S; switched reference and manuscript to formatted reading. The saved reference contained the exact Markdown edit. Existing user documents were left untouched.

## In-app updates (0.5)

The app now includes Sparkle, a Check for Updates menu item, and automatic-check settings. The public feed and signing key are configured in UpdateConfig.json; checks require a published release to succeed. Installation is manual. The GitHub workflow prepares Sparkle-signed community draft releases by default, with an optional Apple-notarized mode; pushing code does not release an update. See [the setup and release guide](docs/UPDATES.md). The GitHub signing secret and an end-to-end install/relaunch test are still required before relying on updates.

## License

[MIT](LICENSE). Bundled Sparkle retains its own license notice.

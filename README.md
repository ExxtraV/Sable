# Sable Markdown Writer

A small, native Markdown editor for fiction, for macOS 14 or later. Source is included so the editor can evolve with your writing habits.

## Use

Open `build/Sable Markdown Writer.app` after building. Use File → New or File → Open. Choose an existing UTF-8 `.md`, `.markdown`, or `.txt` file from your Mac or iCloud Drive. File → Save writes plain Markdown; prose overlays are never serialized. File coordination and document saving use Apple's SwiftUI `DocumentGroup` and `FileDocument`.

The writing surface now displays bold, italic, combined emphasis, headings, links, quotes, lists, inline code, fenced code, and strikethrough. Markdown markers remain visible in a subdued color. Fonts and visual attributes never become part of the saved text. Supported web/mail links have native link attributes.

Text is centered in a 680-point column by default, including in a maximized window. Settings lets you change the width and text size. A two-finger horizontal swipe or the sidebar button (⌃⌘S) toggles the writing desk. Its outline options let you choose Chapters, Episodes, Scenes, Outline, or any custom label and filter to one heading level. Labels and filters are shared across documents and do not rename your actual headings.

The Files section's menu → Choose Writing Folder opens a persistent folder browser for Markdown and text files. Click folders to expand or collapse nested contents inline. Use the up arrow to return, and click a file to switch the active document. Sable asks macOS to save, discard, or cancel when the active document has unsaved edits, then opens the selected file in the same writing window. Automatic window tabs are disabled. The menu also refreshes the listing or returns to the root folder. Search filters loaded, visible file rows and outline headings. Folder listings refresh manually; recursive full-text search is not implemented. Hidden files, symlinks, and packages are excluded.

Any Markdown file in the writing folder can be opened beside the active document from its context menu. The split pane begins in a clean formatted reading view. Edit enables in-place Markdown editing beside the draft; Read returns to the formatted view. The secondary document saves separately and closes with the split pane. It is general-purpose for now; fiction-specific world-document pinning is deferred to the Fiction Projects milestone.

Move the pointer to the top edge to reveal the quiet toolbar. Its Aa button opens font and style controls: five presets (Everyday / Georgia, Literary / Charter, Classic / Baskerville, Science fiction / Menlo, Manuscript / Courier New), a custom installed-font choice, size, page width, line spacing, and five themes. Styles are shared across documents; Markdown itself is unchanged. Some installed fonts do not include bold or italic faces, so available styles depend on the font.

Paragraph focus (target icon, ⇧⌘F) dims text outside the paragraph containing the cursor. It follows clicking, keyboard navigation, and typing. Paragraphs are separated by blank lines; soft line breaks stay in the same paragraph. Focus is per writing window and never modifies text.

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

Validation covers release builds, prose checks, Markdown checks, folder-listing checks, and native-editor checks. Native checks include focus tracking/clearing, font changes, source preservation, margins, Unicode, and formatting exits. The focused workflow also exercises first-run folder setup, saving and canceling a first save, sentence-color settings, and the parallel reading surface. Cross-device iCloud syncing remains untested.

This is a first Mac prototype, not a finished cross-platform release. Prose review uses an editable list, not semantic judgment: a flagged word is not necessarily needless. The lightweight matcher excludes common fenced code, inline code, YAML front matter, URLs and inline link destinations; it is not a complete Markdown parser. The source highlighter is also a lightweight grammar, not a full CommonMark renderer; complex nesting, tables, images, and footnotes do not have a rich rendered view. Source mode retains Markdown markers; the Play button (⇧⌘R) switches to a formatted reading view. This reading view supports headings, emphasis, links, lists, quotes, and code, but is not a full CommonMark renderer. Word count is whitespace-based. Large-manuscript performance is not yet benchmarked.

iCloud access uses the system file picker and ordinary files, with no custom cloud database. Actual cross-device sync and conflict behavior still need testing with your iCloud account.

For an iPad edition, reuse `QuillCore` and the document model, add a UIKit text view and document-browser target, keyboard commands, and platform-specific spelling/review menus. The current package and editor are Mac-only; building and testing the iPad app requires full Xcode.

## Where to customize

- `Sources/QuillCore/Prose.swift`: prose matching and default word list.
- `Sources/QuillCore/FocusParagraph.swift`: Markdown paragraph boundaries for focus mode.
- `Sources/Quill/FolderBrowser.swift`: folder access, file filtering, navigation, and file menu.
- `Sources/Quill/ReferencePane.swift`: general parallel Markdown reading and editing pane.
- `Sources/Quill/ReferenceDocument.swift`: tracked parallel document saving.
- `Sources/Quill/ReadingView.swift`: native formatted reading view.
- `Sources/QuillCore/SentenceStructure.swift`: local parts-of-speech tagging.
- `Sources/Quill/WritingStyle.swift`: font, style, and outline controls.
- `Sources/QuillCore/MarkdownSyntax.swift`: source highlighting spans, chapter outline, and formatting exit logic.
- `Sources/Quill/WorldSidebar.swift`: writing desk with file browser and outline.
- `Sources/Quill/NativeEditor.swift`: visual overlays, text behavior, context menu, and shortcuts.
- `Sources/Quill/QuillApp.swift`: document handling, settings, and interface.
- `Tests/QuillCoreTests`: Unicode and Markdown-protection checks.

Apple references: [document-based apps](https://developer.apple.com/documentation/swiftui/building-a-document-based-app/) and [native grammar checking](https://developer.apple.com/documentation/appkit/nstextview/isgrammarcheckingenabled).

## Additional checks

After building, the standalone Markdown and native editor checks can run without XCTest:

```sh
swiftc Sources/QuillCore/MarkdownSyntax.swift scripts/check-markdown.swift -o /tmp/quill-markdown-checks
/tmp/quill-markdown-checks
swiftc -I .build/arm64-apple-macosx/release/Modules Sources/Quill/NativeEditor.swift Sources/Quill/Import.swift Sources/Quill/WorkspaceExperience.swift Sources/Quill/FolderBrowser.swift Sources/Quill/FictionProject.swift Sources/Quill/WorldSidebar.swift Sources/Quill/WritingStyle.swift scripts/check-editor.swift .build/arm64-apple-macosx/release/QuillCore.build/*.o -o /tmp/quill-editor-checks
/tmp/quill-editor-checks
```

The last command uses the Apple Silicon build path; substitute `x86_64-apple-macosx` on Intel. Sample manuscript and world-note files are in `Examples/`.

For the list, heading, and smart-typography rules, document import, and project-wide find and replace:

```sh
swiftc Sources/QuillCore/MarkdownEditing.swift scripts/check-markdown-editing.swift -o /tmp/quill-markdown-editing-checks && /tmp/quill-markdown-editing-checks
swiftc Sources/Quill/Import.swift scripts/check-import.swift -o /tmp/quill-import-checks && /tmp/quill-import-checks
swiftc Sources/Quill/ProjectSearch.swift scripts/check-project-search.swift -o /tmp/quill-search-checks && /tmp/quill-search-checks
```

For manuscript export checks (PDF, EPUB, Word, Markdown):

```sh
swiftc Sources/Quill/Export.swift Sources/Quill/FictionProject.swift Sources/Quill/FolderBrowser.swift scripts/check-export.swift -o /tmp/quill-export-checks
/tmp/quill-export-checks
```

For folder-listing checks:

```sh
swiftc Sources/Quill/FolderBrowser.swift Sources/Quill/FictionProject.swift scripts/check-folder.swift -o /tmp/quill-folder-checks
/tmp/quill-folder-checks
swiftc Sources/Quill/FolderBrowser.swift Sources/Quill/FictionProject.swift scripts/check-fiction.swift -o /tmp/quill-fiction-checks
/tmp/quill-fiction-checks
```

`sh scripts/build-preview.sh` builds a separate **Sable Markdown Writer Preview.app** with its own preferences and copied sample documents. Its `QUILL_PREVIEW` fixture setup is excluded from the normal app, allowing UI checks without closing an existing draft. Normal app updates take effect after saving work and restarting Quill.

## New in 0.4

Optional sentence coloring highlights nouns, verbs, adjectives, adverbs, and pronouns using macOS Natural Language locally. These are estimates, particularly for invented names, and are shown in source mode only. Color selections never alter your text. The toolbar stays hidden until the pointer reaches the top edge. PDF and ebook export are deferred.

Standalone checks additionally verified clean reading, bold rendering, list rendering, icon decoding, parts-of-speech/code exclusions, parallel document reuse, and exact native parallel saves. Native document checks require access to macOS document services outside a restricted shell sandbox.

The generated logo and its prompt are in `Assets/LOGO.md`; the icon is packaged with the app.

The app keeps ordinary Markdown files and has no custom cloud database. Fiction-specific project templates and export stay on the roadmap.

## In-app updates (0.5)

The app now includes Sparkle, a Check for Updates menu item, and automatic-check settings. The public feed and signing key are configured in UpdateConfig.json; checks require a published release to succeed. Installation is manual. The GitHub workflow prepares Sparkle-signed community draft releases by default, with an optional Apple-notarized mode; pushing code does not release an update. See [the setup and release guide](docs/UPDATES.md). The GitHub signing secret and an end-to-end install/relaunch test are still required before relying on updates.

## License

[MIT](LICENSE). Bundled Sparkle retains its own license notice.

## Minimalist editor update (in development)

- First launch opens a blank document and asks you to choose or create a writing folder. Cloud folders are recommended; normal files elsewhere remain supported.
- Setup can include an editable **Sable Guide.md**. Open it again from Help; existing guide edits are never overwritten.
- Writing Style includes Graphite, Midnight, Forest, Parchment, and Paper themes.
- Zoom with Command-Plus/Minus, reset with Command-0, or pinch the trackpad. Pinch zoom can be disabled in Writing Style.
- Move the pointer to the top edge to reveal the toolbar. Reading mode, focus, sidebar, styling, and sentence colors remain available from the View menu.
- The footer shows save state. Explicit saves through the editor show completion time; cancellation never reports success. “Saved” refers to the local file, not a cloud-sync confirmation.
- The sentence-color crash is addressed by preventing AppKit's shared color panel from modifying the plain-text manuscript and ignoring text-change notifications with unchanged content.

See [the roadmap](docs/ROADMAP.md) for Fiction Projects and export plans.

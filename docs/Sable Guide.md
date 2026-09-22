# Welcome to Sable Markdown Writer

Your words live in ordinary Markdown files. They are plain text, so you can open them in other editors and keep them in a folder you control.

## Your writing folder

Choose a writing folder during setup. We recommend iCloud Drive, Dropbox, or OneDrive for access across devices. Your cloud service handles synchronization; let it finish before editing the same file on another device.

The writing desk has two tabs: **Files** and your **Outline**. Click a file to open it in the same window (full screen stays on); Sable asks you to save or discard unsaved changes first.

- **Create:** the **+** button makes a new file or folder. Control-click a folder to create inside it.
- **Rearrange:** drag files and folders onto folders to nest them. Drop on the path above the list to move things back up.
- **Rename and trash:** Control-click for Rename and Move to Trash, with an Undo shortcut just after trashing.
- **Colors and pins:** give any file or folder a color or pin it to the top. Name your colors (Draft, Revised…) in the list options. Chips above the list filter by color or pin.
- **Focus:** Control-click a folder and choose Focus on This Folder to see only that folder. The path above the list takes you back out.
- **Search:** the search box looks through every folder beneath the one you're viewing, not only the ones that are open.
- **Keyboard:** arrow keys move through the list, → and ← open and close folders, Return opens, ⇧Return renames, ⌘Delete moves to the Trash.
- **Make it yours:** the sliders button sets sorting, icons, file extensions, last-modified dates, word counts and compact rows. Drag the desk's right edge to resize it.

Choose another folder from the ⋯ menu at any time.

## Fiction Projects

A **Fiction Project** is a folder that Sable treats as one story world. Every new project opens on a **Start Here** note that explains how it works and how to customize it; bring it back any time from the project's ⋯ menu, which also has a **Concept** note to help you think the story through before you draft. Create a project from the **+** button → **New Fiction Project…**. It sets up **Manuscript**, **Characters**, **Locations**, **World**, **Outline**, **Notes**, and **Images** folders, with an optional sample chapter, character, and location. You can also turn any existing folder into a project: Control-click it and choose **Make Fiction Project…**. Nothing in it is moved or renamed.

- **Projects stand apart.** In a folder that holds projects, the desk lists **Fiction Projects** in their own section, above your ordinary folders and files.
- **Only the project.** Once you're inside a project, the writing desk shows only what's in it. Its header names the project and has a **Leave** button that takes you back to all your files.
- **Manuscript first.** The **Manuscript** folder is always pinned to the top and red by default, since it's where you'll spend the most time. Give it another color from its Control-click menu if you like. Opening a file that belongs to a project brings the desk into that project automatically.
- **Manuscript overview.** Inside a project the desk gains a **Manuscript** tab: your total word count (updating as you type), an optional goal with a progress bar, and every chapter with its own count and a length bar. Drag chapters to rearrange them, or Control-click for Move Up, Down, Top, and End. The order is saved in the project, and your files are never renamed or changed. The Files tab shows the Manuscript folder in the same order, and you can drag chapters there to rearrange them too.
- **Scene tags.** In a chapter, a quiet strip of chips shows the scene's location and characters. Click **Tag this scene** (or press ⌃⌘T) to choose them from your cards, and click a chip to open its card without leaving the page. Chips take the card's color (set it from the card's ⋯ menu → **Color**, or by coloring the file in the desk), which you can turn off in Writing Style. The strip fades while you type, and in paragraph focus it and any collapsed card tabs dim until you point at them. Writing Style moves the strip to a corner or turns it off. Tags are saved at the top of the chapter (`location:`, `characters:`, `world:`), and a name matches a card by file name, title, or `aliases:`.
- **The + buttons.** Point at the Manuscript, Characters, Locations, or World folder and click the **+**: it adds the next chapter, or asks for a character, location, or world note's name. It also works on folders inside them. Every other folder — Outline, Notes, Images, one of your own, or any folder outside a project at all — gets a plainer **+** for a new Markdown file.
- **Quick creation.** Inside a project, **+** adds a chapter (numbered for you), character, location, or world note from a ready-made template.
- **Planning.** The **Outline** folder holds your own headings — acts, chapters, beats. Tag one in parentheses, like "(Climax)", and it takes its place on the **Story Timeline** (File menu, ⌥⌘Y): Inciting Incident, Rising Action, Midpoint, Climax, Falling Action, or Resolution. Untagged headings spread evenly along the arc, so even a rough outline shows a shape, and clicking a point jumps straight to it.
- **Cards.** Files in Characters, Locations, and World can float over your page as cards while you write. Hover a file and click the card icon, or Control-click → **Show as Card**. Drag a card and it snaps to the nearest corner. Pin it to keep it open, or unpin it to shrink to a small tab that opens when you point at it. Cards update as the file changes. Drag a card's corner grip to make it as large or small as you like (everything inside scales with it); double-click the grip to reset it.
- **Pictures.** Click a card's portrait (or drop an image on the card) to tag a picture. A framing window lets you drag and zoom to crop the portrait, and you can reopen it any time from the card's ⋯ menu with **Adjust Crop…**. Sable copies the picture into **Images** and adds `image:` and `image-crop:` lines to the file. Your original picture is never altered.
- **Just Markdown.** Everything is ordinary Markdown. Card details live in a small block at the top of each file (`type`, `role`, `image`, `tags`), so any other editor can open, read, and edit it all. The only extra is a hidden marker file named `.sable-project.json`.
- **Convert back.** From the project's ⋯ menu choose **Convert to Regular Folder…**. That removes only the marker; every file and folder stays exactly as it is.
- **Names & places.** Character, location, and world names take a color and a soft shimmer as you write: full names, first and last names, file names, and `aliases:`. Turn it on or off in View → Highlight Names & Places, or pick the color in Writing Style. Right-click a highlighted name to open its file or show its card.
- **Export.** On the Manuscript tab press **Export…** (⇧⌘E) to make one PDF, EPUB, Word, or Markdown file from your chapters, in your order. Choose the chapters, a title page, and a Manuscript or Book look. File → Export This Document… exports only the open page.

## A little Markdown

Use **two asterisks for bold**, *one for italics*, and [a link label](https://www.markdownguide.org). Start a line with # for a heading, or ## for a smaller heading.

- A dash starts a list item.
- A blank line starts a new paragraph.

> A greater-than sign starts a quotation.

Use `backticks` for inline code and ~~two tildes~~ for a strikethrough.

## Markdown helpers

- **Lists:** press Return to continue a list, Return on an empty item to end it, and Tab or Shift-Tab to indent or outdent. ⇧⌘8 makes a bulleted list, ⇧⌘7 a numbered one, and ⇧⌘9 a task list.
- **Headings:** ⇧⌘H cycles the line through #, ##, ###, and plain. **Scene break:** ⇧⌘L. **Strikethrough** ⇧⌘X, **inline code** ⇧⌘K.
- **Notes to yourself:** `<!-- like this -->` is dimmed while you write, hidden in Reading Mode, and left out of exports.
- **Find & Replace in Project** (⌥⇧⌘F) searches every Markdown file, shows what will change, and can undo the replacement.
- **Import Document…** in the File menu converts a Word, RTF, or HTML file into Markdown, and **Paste as Markdown** (⌃⌘V) does the same for whatever you copied.
- Settings → Writing can turn on curly quotes and dashes as you type. The Help menu has a Markdown cheat sheet.

## Revisions

Before a big rewrite, save a snapshot: **File → Save Snapshot** (⌥⌘S), or the Revisions button at the bottom of the writing desk. A snapshot keeps a copy of every chapter as it is right now. **Revision History** (⌥⌘R) lists your snapshots and shows, for any of them, which chapters changed and how: words you have added are underlined green and words you have removed are struck through red. From there you can restore one chapter or the whole draft. Sable saves a safety snapshot before every restore, so a restore can be undone too. In a Fiction Project it also keeps a daily snapshot when something changed (turn that off in Settings). Snapshots live in a hidden `.sable-revisions` folder as ordinary Markdown files.

## Your writing record

Settings → General charts the words you've added each day for the last 30 days, with your best day and a lifetime total. It only counts progress you keep — deleting words never counts against you — and it isn't a streak, so a quiet day changes nothing. It's kept only on this Mac, and you can clear it any time.

## Your toolbar

The toolbar starts with only the essentials. Click **⋯ → Customize Tools** to add the tools you use (headings, bold, italic, lists, quotes, scene breaks, revisions, and more) and drag them into the order you like. Dark themes shade toward the page edges to keep your eye on the text; Writing Style lets you turn that off or change how deep it is.

## Keep your hands on the story

- Command-N: new document.
- Command-O: open a file.
- Command-S: save.
- Command-B / Command-I / Command-K: bold, italic, link.
- Command-Shift-H: heading.
- Tab or Escape: move past closing formatting markers.
- Command-Backslash: leave formatting.
- Return: leave formatting and start a new line.
- Command-F: find in the manuscript.
- Command-Shift-F: focus on the current paragraph.
- Command-Shift-R: switch between writing and reading mode.
- Command-Control-S: show or hide the writing desk.
- Command-Option-Comma: fonts, themes, and writing style.
- Command-Option-J: sentence-structure colors.
- Command-Plus (the = key) / Command-Minus: zoom in or out.
- Command-0: reset zoom to 100%.

Pinch the trackpad to zoom. You can turn this off in Writing Style. A two-finger horizontal swipe shows or hides the writing desk. Zoom changes the display, not your Markdown.

## A quiet writing space

Try Graphite, Midnight, Chalk, Forest, Obsidian, Arcane, Parchment, or Paper in Writing Style. Obsidian is nearly black, for a room with the lights all the way down. Arcane is a dark purple for fantasy writing, with faint particles of light drifting behind the text (turn them off if they're not your thing). Every dark theme shades toward the page's edges so your eye settles on the middle; Graphite, Midnight, Chalk, and Obsidian also darken the bar at the bottom. Pick one of five writing fonts or choose your own. The toolbar slides in when you move the pointer near its edge and never shifts your page. Put it on the top, left or right, keep it visible, or turn it off entirely with ⌥⌘T. Rest the pointer on any tool to see its name and what it does; the writing desk can be shown or hidden with its shortcut or a two-finger horizontal swipe.

**Scrolling** in Writing Style lets you scroll past the end of your text so the line you're writing can sit in the middle of the window, or, in its third setting, keeps that line centered for you as you type. Paragraph Focus fades the text above and below the paragraph you're writing, a little more with each line of distance. In Writing Style you can switch it to dim everything evenly. Reading Mode hides Markdown marks. Prose suggestions cross out possible cuts only on screen. Sentence Structure colors nouns, verbs, and other word classes on your Mac; invented names can be misclassified. None of these display features changes your saved text.

## A second file beside your draft

Control-click any Markdown file in the writing desk and choose **Open Beside Current Document**. It opens as a formatted reading view next to your draft. Each side scrolls and zooms on its own: pinch, or use ⌘+ and ⌘−, with the pointer over the one you want to scale. Choose Edit to work on it in place, then Read to return to the clean view. This stays within one focused document window: Sable does not use writing tabs.

## What comes next

Sable is a focused Markdown editor first, with Fiction Projects for writers who want one home for a whole story. PDF and ebook export, plus an iPad edition, are on the roadmap.

You can edit this guide freely. Help → Sable Guide opens it again without overwriting your changes.

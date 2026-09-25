# Prose request: website redesign (what's still open)

> Everything you wrote so far is on the site, word for word. These are the
> things left. Answer under "Your text" and hand the file back.
>
> The six tour lines below block the pull request: each spot shows a
> PROSE-TODO marker on the preview, and CI fails until your lines replace
> them. The trademark line doesn't block anything; the footer simply
> leaves it out until you answer.
>
> The tour names ("Paragraph Focus", "The writing desk", and so on) are
> short labels Claude wrote. Change any of them here if you like.

## Footer · Trademark line (every page)
- Where: the footer of every page (id: `footer-trademark`)
- Length: 1 short sentence, plus a link to the trademark policy
- Must get across: the name "Sable Markdown Writer" and the logo are
  protected; the code is free to use under MIT
- Verified facts: TRADEMARK.md reserves "Sable Markdown Writer" and the
  Sable logo for the Sable project maintainer (GitHub: ExxtraV); forks are
  welcome under their own name and icon; ™ can be used, ® can't (not
  registered). The policy says "the Sable logo" without picturing it, so it
  covers the new sleeping-curl logo too.
- Status: left blank last round, so the footer has no trademark line yet.
  Write "skip" if you don't want one.

Draft (rewrite me):
> SABLE™®©℠ IS OURS AND OURS ALONE, BACK OFF, IMPOSTORS!!!

Your text:
>

## Tour · Paragraph Focus
- Where: website/index.html, the first tour step, beside the clip of a sentence being typed while the paragraphs around it dim (marked PROSE-TODO: tour-focus)
- Length: one line, up to about 20 words
- Must get across: Sable keeps your attention on the paragraph you're writing, and nothing else competes for it.
- Verified facts: View → Paragraph Focus or ⇧⌘F; two styles: fade gradually or dim evenly; typewriter scrolling can keep the line you're writing centered; the dimming is display only and never changes your file
- Current wording: none (new)

Draft (rewrite me):
> THE PARAGRAPH SPOTLIGHT OF DESTINY!!! Every other sentence BOWS before the one you are writing!!!

Your text:
>

## Tour · The writing desk
- Where: website/index.html, the second tour step, beside the clip of the desk sliding in and back out (marked PROSE-TODO: tour-desk)
- Length: one line, up to about 20 words
- Must get across: Your files and folders are one click away when you need them and gone when you don't, so the page is all you see while you write.
- Verified facts: the desk shows the writing folder or Fiction Project; toggle it from View → Show Writing Desk, the toolbar, or a two-finger horizontal swipe; drag its edge to resize; the toolbar also hides until the pointer nears its edge
- Current wording: none (new)

Draft (rewrite me):
> WITNESS the MAGICAL VANISHING SIDEBAR!!! Now you see it, now you DON'T, and your novel is BETTER for it!!!

Your text:
>

## Tour · Eight themes
- Where: website/index.html, the third tour step, beside the clip of one chapter switching through the themes (marked PROSE-TODO: tour-themes)
- Length: one line, up to about 20 words
- Must get across: Make the page yours: a mood for every kind of writing session, with the app's typography.
- Verified facts: eight themes (Graphite, Midnight, Chalk, Forest, Obsidian, Arcane, Parchment, Paper); dark themes shade toward the edges (adjustable); Arcane has faint drifting motes (can be turned off); five font presets or any installed font; size, page width, and line spacing
- Current wording: none (new)

Draft (rewrite me):
> EIGHT DIMENSIONS OF WRITERLY BLISS!!! Purple!!! Parchment!!! The VOID ITSELF (Obsidian)!!!

Your text:
>

## Tour · Character cards and scene tags
- Where: website/index.html, the fourth tour step, beside the clip of scene tags opening a character card and a location card (marked PROSE-TODO: tour-cards)
- Length: one line, up to about 20 words
- Must get across: Your characters, places, and world notes open beside the chapter you're writing, then get out of the way.
- Verified facts: cards are ordinary Markdown files in the project's Characters, Locations, and World folders; add a portrait, pin a card, or let it collapse; scene tags come from the chapter's front matter and fade while you type; names can be highlighted in the text
- Current wording: none (new)

Draft (rewrite me):
> Your ENTIRE CAST, SUMMONED at a SINGLE CLICK like a WIZARD'S FAMILIARS!!!

Your text:
>

## Tour · The Manuscript tab
- Where: website/index.html, the fifth tour step, beside the clip of the Manuscript tab and chapters opening (marked PROSE-TODO: tour-manuscript)
- Length: one line, up to about 20 words
- Must get across: The whole book at a glance: total words, an optional goal, and every chapter in reading order.
- Verified facts: Manuscript tab in a Fiction Project; total words, optional word goal with progress, chapter lengths; drag to reorder the reading order without renaming files; New Chapter; Export from here
- Current wording: none (new)

Draft (rewrite me):
> BEHOLD YOUR NOVEL'S MIGHTY SKELETON!!! Twenty thousand words of GLORY, tracked to the LAST SYLLABLE!!!

Your text:
>

## Tour · Export (no action needed)
- Where: the sixth tour step, beside the clip of the Export Manuscript sheet
- Its line is your existing export text, already in place: "Turn your markdown into usable formats for publication, editing, and other use (PDF, EPUB, Word, Markdown). More export features are being crafted to suit your needs."
- Write a new line here only if you want to replace it.

Your text:
>

## Check · The clips
- Where: the six tour steps (files in website/clips/)
- Claude recorded them from the Preview build with sample text: typing
  with Paragraph Focus, the writing desk, a theme cycle, scene tags opening
  cards, the Manuscript tab, and the export sheet. They're silent, 7–12
  seconds each, and each under 1.4 MB. The sample text in them was written by
  Claude Code, like the screenshots.
- Approve them, or name any you'd like redone (or record your own and
  say where the files are).

Your text:
>

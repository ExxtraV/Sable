# Prose request: SEO titles and descriptions

> How this works: each "##" heading is one page. Write your version under
> "Your text" and leave the heading alone. The drafts are deliberately over
> the top so they can never ship by accident. Claude uses only what's under
> "Your text", exactly as you wrote it.
>
> There are no PROSE-TODO markers in the site for this request: every page
> already has a working title and description, so nothing blocks a merge.
> Answer whenever you like; Claude swaps your text in and deletes this file.
>
> Three pieces of text per page:
> - **Title**: the browser tab and the blue link in search results. Aim for
>   60 characters or fewer, or search engines cut it off.
> - **Description**: the grey text under the link in search results. Aim for
>   155 characters or fewer. Search engines may rewrite it, but a good one
>   usually stays.
> - **Social description**: the line under the image when the page is shared
>   on X or Bluesky. About 100 characters is plenty.
>
> **Phrases writers search for.** The titles and descriptions work best if
> they honestly match how people look for an app like Sable. Use a phrase
> only where it's true of that page, and only if it sounds like you:
>
> | Phrase | Is it honest? |
> |---|---|
> | markdown editor for Mac | Yes. Sable is a native Mac app (macOS 14+) that reads and writes plain Markdown. |
> | writing app for novelists | Yes. Fiction Projects, character cards, scene tags, and manuscript export are built for it. |
> | focus writing app | Yes. Paragraph Focus, a hiding toolbar, and no competing panels are the point. |
> | free Scrivener alternative | Partly. Sable is free and made for fiction, but it isn't a full Scrivener replacement (no corkboard yet; it's on the roadmap). Say "alternative for writers who want less", not "replacement" or "better than". "Scrivener" is another company's name, so use it plainly and never imply a connection. |
> | free, open-source, no account | Yes, and a real differentiator: MIT licensed, no account, nothing collected. |
> | export a manuscript to PDF, EPUB, or Word | Yes, from a Fiction Project. |
> | writing app for iPhone, iPad, or Windows | No. Mac only today. Leave these out. |

## Website · Home page · Title, description, social description
- Where: `website/index.html` (`<title>`, `meta name="description"`, `og:title`/`og:description`, `twitter:title`/`twitter:description`)
- Current title (61 characters, one over): Sable Markdown Writer — Eliminate Clutter, Focus on the Words
- Current description (152 characters): Sable is a free, open-source Markdown editor for Mac. Focus on the page, build Fiction Projects, and export manuscripts to PDF, EPUB, Word, or Markdown.
- Current social description (116 characters): A native Mac Markdown editor for focused writing, fiction projects, and finished manuscripts. Your files stay yours.
- Length: title up to 60, description up to 155, social description about 100
- Must get across: what Sable is (a Mac Markdown editor), who it's for (fiction writers, but anyone who likes Markdown), and that it's free
- Phrases it honestly matches: markdown editor for Mac, writing app for novelists, focus writing app, free Scrivener alternative (with the caveat above), free open-source writing app
- Verified facts: free, MIT licensed, macOS 14+, Apple Silicon and Intel, exports PDF/EPUB/Word/Markdown from a Fiction Project

Draft (rewrite me):
> Title: SABLE!!! The ULTIMATE Novel-Crushing Mac Machine That Will Make You a BESTSELLER
> Description: Throw away EVERY other app!!! Sable is the one and only writing tool that has EVER mattered, and it costs NOTHING!!! Your future readers are already CHEERING!!!
> Social: You will not BELIEVE what happens when you open this app!!!

Your text:
> Title:
> Description:
> Social:

## Website · Guide · Title, description, social description
- Where: `website/guide.html` (same tags as above)
- Current title (49 characters): Sable Guide — Keyboard Shortcuts and Writing Tips
- Current description (146 characters): Set up Sable’s writing desk, Fiction Projects, manuscript exports, name highlights, Markdown shortcuts, themes, focus mode, and local prose tools.
- Current social description (104 characters): Set up your writing folder, use the writing desk and paragraph focus, and learn every keyboard shortcut.
- Length: title up to 60, description up to 155, social description about 100
- Must get across: this is the how-to for Sable, and what's in it
- Phrases it honestly matches: how to use Sable, Markdown keyboard shortcuts for Mac, fiction project setup, export a manuscript from Markdown
- Verified facts: the guide covers the writing desk, Fiction Projects, export, name highlights, shortcuts, themes, focus modes, and how Sable protects your files

Draft (rewrite me):
> Title: The GUIDE That Will Change EVERYTHING You Know About Keyboards
> Description: Every SECRET shortcut, revealed at last!!! Read this or be forever lost in the darkness of not knowing where Save is!!!
> Social: Master Sable in ONE THRILLING READ!!!

Your text:
> Title:
> Description:
> Social:

## Website · Privacy · Title, description, social description
- Where: `website/privacy.html` (same tags as above)
- Current title (31 characters): Privacy — Sable Markdown Writer
- Current description (120 characters): Sable has no accounts and never sends your writing anywhere. Here is exactly what the app and this website do with data.
- Current social description (61 characters): What Sable and this website do, and don't do, with your data.
- Length: title up to 60, description up to 155, social description about 100
- Must get across: no accounts, writing stays on the Mac, no tracking
- Phrases it honestly matches: private writing app, writing app with no account, local-first Markdown editor
- Verified facts: no accounts, no analytics on the site, the only network use in the app is the update check

Draft (rewrite me):
> Title: PRIVACY!!! Nobody Sees Your Words But YOU (and Possibly Your Cat)
> Description: We collect NOTHING. Not a crumb. Not a byte. Not even your favorite color!!!
> Social: Your words. Your Mac. Nobody else's business!!!

Your text:
> Title:
> Description:
> Social:

## Website · Blog index · Title, description, social description
- Where: `website/blog/index.html` (also the feed description in `scripts/build-blog.py`)
- Current title (28 characters): Blog — Sable Markdown Writer
- Current description (54 characters, written by Claude as a stopgap): News and notes from the Sable Markdown Writer project.
- Current social description: same as the description
- Length: title up to 60, description up to 155, social description about 100
- Must get across: this is where Sable's news and posts live
- Phrases it honestly matches: Sable Markdown Writer blog, Sable updates, writing app release notes
- Verified facts: posts are written by the maintainer and labeled if AI wrote any of a piece; the feed is at /blog/feed.xml

Draft (rewrite me):
> Title: THE BLOG!!! Where Legends Type Words About Typing Words
> Description: Fresh, piping-hot, GROUNDBREAKING posts about Sable, delivered straight to your eyeballs!!!
> Social: Read the latest from Sable!!!

Your text:
> Title:
> Description:
> Social:

## Website · Blog post "Version 0.10.0 is Here!" · Description only
- Where: `docs/blog/posts.json`, as `"description"` on the post's entry (Claude adds it; your post itself is never touched). The post title is yours already.
- Current description (101 characters; Claude used the post's first sentence): After a week, Sable Version 0.10.0 is here, and it is in a better state than I could have ever hoped.
- Length: description up to 155
- Must get across: what's in this release, in a way that makes a searcher click
- Phrases it honestly matches: Sable Markdown Writer 0.10.0, Mac Markdown editor for fiction writers
- Verified facts: 0.10.0 (released 2026-09-24) adds instant typing in long manuscripts, smooth pinch zoom, ⌘ + mouse wheel zoom, faster theme changes, stronger file-safety protections, and an opt-in beta update channel

Draft (rewrite me):
> Version 0.10.0 has DROPPED and the writing world will NEVER BE THE SAME!!!

Your text:
> Description:

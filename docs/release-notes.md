Sable Markdown Writer 0.10.0 keeps typing instant in long manuscripts, makes zooming smooth, and adds safeguards in every place Sable writes, moves, or deletes your files. There's also an optional beta update channel.

- **Instant typing, however long the file.** A whole novel in one file no longer makes the page lag. Sable now restyles only the lines you're editing, so a keystroke takes about the same time at 10,000 words as at 100,000. In a 100,000-word file it went from about 430 ms to about 5 ms, and with sentence colors, Paragraph Focus, smart typography, and centered typing all on, from about 1.8 seconds to about 24 ms. The page looks exactly as before. One small difference: the word count and cuts in the status bar now catch up when you pause, within a third of a second, instead of on every letter.
- **Smooth pinch zoom.** Pinching the trackpad now scales the page smoothly under your fingers, then settles at the new size when you let go, with the line under the pointer still under it. Before, a pinch in a long manuscript stuttered.
- **Zoom with ⌘ and a mouse wheel.** Hold ⌘ and turn a mouse's scroll wheel over the page: away from you zooms in, toward you zooms out, 5% per notch, between 65% and 200%. It works in Reading Mode and in a file open beside your draft, too. Trackpads keep scrolling as before; pinch zooms there.
- **Faster theme and font changes.** Changing the theme, font, size, zoom, or colors in a long manuscript takes well under half as long as it did, because Sable repaints from what it already knows about your text instead of reading all of it again.
- **Your files, better protected.** An audit of every place Sable writes, moves, or deletes files led to these safeguards. The Sable Guide's new section, "How Sable protects your files," has the details.
  - **Find & Replace in Project** won't change anything unless its safety snapshot is saved first. If a replacement stops partway, it puts back the files it already changed.
  - **Undo Replace won't erase newer words.** It puts back only files that still read exactly as the replacement left them, and tells you which ones it left alone.
  - **The file beside your draft** saves your latest words before Find & Replace or a restore touches it. If that file changes somewhere else while you have edits in it, Sable stops and asks: **Keep Mine** or **Use Saved File**. The other version goes to the Trash as a copy.
  - **Export** can't be saved over the chapters it's exporting, over a file open in Sable, or into your Manuscript folder. A file it replaces goes to the Trash as a copy first.
  - **Put Back.** If a file you have open is moved to the Trash or deleted outside Sable, a quiet note appears under the page (or in the side pane). **Put Back** returns a trashed file to its folder, **Save Again** writes a deleted one back, and **Save As…** keeps it somewhere else.
- **Beta updates, if you want them.** Settings → General has a new **Get beta updates** checkbox, off by default. Turn it on to receive early builds as they're published; they may be rougher than stable releases. Leave it off and you only ever see stable ones.

**Fixed**

- Sable no longer keeps saving an open file into the Trash, without a word, after the file was moved there.
- The writing desk no longer moves a file to the Trash while it's open in another window.
- A change made to a file just as you switched to it could be overwritten by the next save. Now Sable asks first.
- Restoring a large draft from Revision History no longer freezes the window. If a restore stops partway, Sable says how many files were restored and where the safety snapshot is.
- Import no longer replaces a file that appears with the same name at the same moment.

_Release notes written by Claude Code._

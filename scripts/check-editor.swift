import AppKit
import QuillCore

@main enum EditorChecks {
    @MainActor static func main() {
        let editor = WritingTextView(frame: NSRect(x: 0, y: 0, width: 1600, height: 900))
        editor.isRichText = false
        editor.pageWidth = 680
        editor.updatePageMargins()
        precondition(editor.textContainerInset.width == 460)
        editor.string = "# Chapter\n**bold** and *italic* and [link](https://example.com). Really."
        let original = editor.string
        editor.decorate()
        precondition(editor.string == original, "Display styling must not change Markdown")
        let source = original as NSString
        let boldIndex = source.range(of: "bold").location
        let italicIndex = source.range(of: "italic").location
        let bold = editor.textStorage!.attribute(.font, at: boldIndex, effectiveRange: nil) as! NSFont
        let italic = editor.textStorage!.attribute(.font, at: italicIndex, effectiveRange: nil) as! NSFont
        precondition(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        precondition(NSFontManager.shared.traits(of: italic).contains(.italicFontMask))
        editor.string = ""
        editor.setSelectedRange(NSRange(location: 0, length: 0))
        editor.markBold(nil)
        precondition(editor.string == "****" && editor.selectedRange().location == 2)
        editor.insertText("promise", replacementRange: editor.selectedRange())
        editor.exitFormatting(nil)
        editor.insertText(" kept", replacementRange: editor.selectedRange())
        precondition(editor.string == "**promise** kept")
        editor.string = "*Tomorrow*"
        editor.setSelectedRange(NSRange(location: 9, length: 0))
        editor.insertNewline(nil)
        editor.insertText("Next", replacementRange: editor.selectedRange())
        precondition(editor.string == "*Tomorrow*\nNext")
        editor.string = "🌙 story"
        editor.setSelectedRange(NSRange(location: 3, length: 5))
        editor.markBold(nil)
        precondition(editor.string == "🌙 **story**")
        editor.markBold(nil)
        precondition(editor.string == "🌙 story")
        editor.string = "First paragraph.\nsoft break.\n\nSecond 🌙 paragraph.\n\nThird."
        editor.setSelectedRange(NSRange(location: 4, length: 0))
        editor.focusParagraph = true
        editor.decorate()
        let layout = editor.layoutManager!
        let second = (editor.string as NSString).range(of: "Second").location
        precondition(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil) == nil)
        precondition(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: second, effectiveRange: nil) != nil)
        editor.setSelectedRange(NSRange(location: second + 2, length: 0))
        editor.updateFocus()
        precondition(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: second, effectiveRange: nil) == nil)
        precondition(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil) != nil)
        editor.focusParagraph = false
        editor.updateFocus()
        precondition(layout.temporaryAttribute(.foregroundColor, atCharacterIndex: 1, effectiveRange: nil) == nil)
        // Gradient focus: text fades with distance from the paragraph being written; classic mode dims evenly.
        let paragraphs = (0..<30).map { "Paragraph \($0) has enough words to wrap onto a second line when the page is a little narrower than usual, so distances are real." }
        editor.string = paragraphs.joined(separator: "\n\n")
        let text = editor.string as NSString
        let middle = text.range(of: "Paragraph 8 ").location + 3
        editor.setSelectedRange(NSRange(location: middle, length: 0))
        editor.focusParagraph = true
        editor.focusGradient = true
        editor.updateFocus()
        func alpha(of label: String) -> CGFloat? {
            let index = text.range(of: label).location + 3
            return (layout.temporaryAttribute(.foregroundColor, atCharacterIndex: index, effectiveRange: nil) as? NSColor)?.alphaComponent
        }
        precondition(alpha(of: "Paragraph 8 ") == nil, "The paragraph being written stays fully visible")
        let neighbor = alpha(of: "Paragraph 9 "), further = alpha(of: "Paragraph 10 "), farthest = alpha(of: "Paragraph 25 ")
        precondition(neighbor != nil && further != nil && farthest != nil)
        precondition(neighbor! > further! && further! > farthest!, "Text fades gradually with distance: \(neighbor!) > \(further!) > \(farthest!)")
        precondition(neighbor! > 0.4 && farthest! < 0.12, "Near text stays readable and far text is quiet")
        precondition(alpha(of: "Paragraph 7 ")! > alpha(of: "Paragraph 4 ")!, "Fades above as well as below")
        editor.focusGradient = false
        editor.updateFocus()
        precondition(alpha(of: "Paragraph 9 ") == alpha(of: "Paragraph 25 ") && alpha(of: "Paragraph 9 ") == 0.25, "Classic focus dims everything evenly")
        editor.focusParagraph = false
        editor.updateFocus()
        precondition(alpha(of: "Paragraph 9 ") == nil)
        // Zoom is per pane: scaling the reference document never resizes the manuscript.
        WritingZoom.set(1, for: WritingZoom.mainKey)
        WritingZoom.set(1.5, for: WritingZoom.parallelKey)
        precondition(WritingZoom.value == 1 && WritingZoom.value(for: WritingZoom.parallelKey) == 1.5)
        WritingZoom.set(1.2, for: WritingZoom.mainKey)
        precondition(WritingZoom.value(for: WritingZoom.parallelKey) == 1.5, "The other pane keeps its own zoom")
        WritingZoom.set(9, for: WritingZoom.parallelKey)
        precondition(WritingZoom.value(for: WritingZoom.parallelKey) == 2, "Zoom is capped")
        let firstPane = WritingScrollView(frame: .zero), secondPane = WritingScrollView(frame: .zero)
        secondPane.zoomKey = WritingZoom.parallelKey
        precondition(firstPane.zoomKey == WritingZoom.mainKey && secondPane.zoomKey == WritingZoom.parallelKey)
        WritingZoom.set(1, for: WritingZoom.mainKey); WritingZoom.set(1, for: WritingZoom.parallelKey)
        // Names and places stand out by color and glow, only where they occur
        func nameCard(_ title: String, _ kind: CardKind) -> IndexedCard {
            IndexedCard(url: URL(fileURLWithPath: "/p/\(title).md"), kind: kind, stem: title, title: title, subtitle: "", aliases: [], modified: nil)
        }
        let namer = NameHighlighter.build(from: [nameCard("Marren Vale", .character), nameCard("The Pier", .location)])
        let named = WritingTextView(frame: NSRect(x: 0, y: 0, width: 900, height: 600))
        named.isRichText = false
        named.nameHighlighter = namer
        named.nameShimmer = true
        named.string = "Marren Vale walked to the Pier. marren said nothing.\n\nVale waited."
        named.decorate()
        let namedText = named.string as NSString
        let marrenAt = namedText.range(of: "Marren Vale").location, walkedAt = namedText.range(of: "walked").location
        let pierAt = namedText.range(of: "Pier").location, lowerAt = namedText.range(of: "marren said").location
        func attr(_ key: NSAttributedString.Key, _ at: Int) -> Any? { named.textStorage!.attribute(key, at: at, effectiveRange: nil) }
        // Dynamic colors are new objects each time, so compare what they resolve to.
        func rgb(_ value: Any?) -> String {
            var text = "none"
            NSAppearance(named: .darkAqua)!.performAsCurrentDrawingAppearance {
                if let color = (value as? NSColor)?.usingColorSpace(.sRGB) { text = String(format: "%.3f,%.3f,%.3f", color.redComponent, color.greenComponent, color.blueComponent) }
            }
            return text
        }
        precondition((rgb(attr(.foregroundColor, marrenAt)) == rgb(WritingTextView.nameColor(.character))), "A character's name takes the character color")
        precondition((rgb(attr(.foregroundColor, pierAt)) == rgb(WritingTextView.nameColor(.location))), "A place takes the location color")
        precondition(rgb(attr(.foregroundColor, walkedAt)) != rgb(WritingTextView.nameColor(.character)), "Ordinary words are untouched")
        precondition(rgb(attr(.foregroundColor, lowerAt)) != rgb(WritingTextView.nameColor(.character)), "A lowercase single word isn't a name")
        precondition(named.nameRanges.count == 3, "Marren Vale, the Pier, and Vale: \(named.nameRanges.count)")
        // Color only: the same colors; a kind can be switched off
        named.nameShimmer = false
        named.decorate()
        precondition(rgb(attr(.foregroundColor, marrenAt)) == rgb(WritingTextView.nameColor(.character)), "Color-only style keeps the colors")
        named.nameKinds = [.location]
        named.decorate()
        precondition(rgb(attr(.foregroundColor, marrenAt)) != rgb(WritingTextView.nameColor(.character)) && rgb(attr(.foregroundColor, pierAt)) == rgb(WritingTextView.nameColor(.location)), "Characters can be turned off while places stay")
        named.nameKinds = Set(CardKind.allCases)
        named.decorate()
        // A change of names restyles even though the text is the same
        named.nameHighlighter = NameHighlighter.build(from: [nameCard("Walked Far", .character)])
        named.decorate()
        precondition((rgb(attr(.foregroundColor, marrenAt)) != rgb(WritingTextView.nameColor(.character))), "Old names stop standing out when the cards change")
        // Off
        named.nameHighlighter = nil
        named.nameShimmer = true
        named.decorate()
        precondition(named.nameRanges.isEmpty, "Turned off, nothing is highlighted")
        // Scrolling past the end, and keeping the line you're writing centered
        let scrollHost = WritingScrollView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        scrollHost.hasVerticalScroller = true
        scrollHost.contentView = RoomClipView()
        let roomy = WritingTextView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        roomy.isRichText = false
        roomy.isVerticallyResizable = true
        roomy.isHorizontallyResizable = false
        roomy.autoresizingMask = [.width]
        roomy.textContainer?.widthTracksTextView = true
        roomy.textContainer?.containerSize = NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude)
        roomy.minSize = .zero
        roomy.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        scrollHost.documentView = roomy
        roomy.string = (0..<120).map { "Line \($0) of a long chapter that keeps going." }.joined(separator: "\n\n")
        roomy.layoutManager!.ensureLayout(for: roomy.textContainer!)
        roomy.sizeToFit()
        let roomClip = scrollHost.contentView as! RoomClipView
        func scrollTo(_ y: CGFloat) { roomClip.scroll(to: roomClip.constrainBoundsRect(NSRect(x: 0, y: y, width: 800, height: 600)).origin) }
        let plainHeight = roomClip.documentRect.height
        precondition(plainHeight > 1500, "The test document is longer than the window (\(plainHeight))")
        scrollTo(1_000_000)
        let plainBottom = roomClip.bounds.origin.y
        precondition(abs(plainBottom - (plainHeight - 600)) < 2, "Standard scrolling stops at the last line")
        roomy.typewriterMode = "room"
        roomy.updateScrollRoom()
        precondition(roomClip.bottomRoom == 276 && roomClip.documentRect.height == plainHeight + 276, "Half a window of room appears below the text")
        scrollTo(1_000_000)
        precondition(roomClip.bounds.origin.y > plainBottom + 250, "You can scroll well past the last line")
        roomy.typewriterMode = "off"
        roomy.updateScrollRoom()
        precondition(roomClip.bottomRoom == 0, "Turning it off takes the room away")
        // Centering brings the line you're writing to the middle from anywhere on the page, without jumping
        let centerWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600), styleMask: [.titled], backing: .buffered, defer: true)
        centerWindow.contentView = scrollHost
        precondition(centerWindow.makeFirstResponder(roomy), "The editor can take focus")
        func caretMid(at location: Int) -> CGFloat {
            let glyph = roomy.layoutManager!.glyphIndexForCharacter(at: min(location, roomy.layoutManager!.numberOfGlyphs - 1))
            return roomy.layoutManager!.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil).midY + roomy.textContainerOrigin.y
        }
        roomy.typewriterMode = "center"
        roomy.updateScrollRoom()
        precondition(roomClip.topRoom == 0 && roomClip.bottomRoom == 276, "Center mode makes room below only")
        // Near the top of the page nothing slides: typing on the first lines leaves the page where it is
        scrollTo(-1_000_000)
        precondition(roomClip.bounds.origin.y == 0, "The page can't be scrolled down past its first line")
        for line in [0, 3, 8] {
            let at = line == 0 ? 0 : (roomy.string as NSString).range(of: "Line \(line) ").location
            roomy.setSelectedRange(NSRange(location: at, length: 0))
            roomy.centerCaretIfNeeded(animated: false)
            precondition(roomClip.bounds.origin.y == 0, "A caret near the top doesn't move the page (line \(line): \(roomClip.bounds.origin.y))")
        }
        // From the middle of the document
        let midPoint = (roomy.string as NSString).range(of: "Line 60 ").location
        roomy.setSelectedRange(NSRange(location: midPoint, length: 0))
        roomy.centerCaretIfNeeded(animated: false)
        precondition(abs(roomClip.bounds.midY - caretMid(at: midPoint)) < 4, "Wherever you clicked, that's the line that centers")
        // Typing on the same line doesn't move the page at all
        let restingY = roomClip.bounds.origin.y
        roomy.setSelectedRange(NSRange(location: midPoint + 3, length: 0))
        roomy.centerCaretIfNeeded(animated: false)
        precondition(roomClip.bounds.origin.y == restingY, "No jitter while you stay on a line")
        // A page that has only been laid out near the top (as after an edit) still centers a line far below it
        let lazy = "Line 90 "
        roomy.string = (0..<120).map { "Line \($0) of a long chapter that keeps going." }.joined(separator: "\n\n")
        roomy.setSelectedRange(NSRange(location: (roomy.string as NSString).range(of: lazy).location, length: 0))
        roomy.centerCaretIfNeeded(animated: false)
        let lazyAt = (roomy.string as NSString).range(of: lazy).location
        precondition(abs(roomClip.bounds.midY - caretMid(at: lazyAt)) < 4, "Centering doesn't clamp to a half-laid-out page: \(roomClip.bounds.midY) vs \(caretMid(at: lazyAt))")
        // And to the very end
        roomy.setSelectedRange(NSRange(location: (roomy.string as NSString).length, length: 0))
        roomy.centerCaretIfNeeded(animated: false)
        precondition(abs(roomClip.bounds.midY - caretMid(at: (roomy.string as NSString).length)) < 4, "The last line sits in the middle too")
        // Room mode gives space but never moves the page by itself
        roomy.typewriterMode = "room"
        roomy.updateScrollRoom()
        precondition(roomClip.topRoom == 0 && roomClip.bottomRoom == 276, "Room mode is bottom only")
        scrollTo(0)
        roomy.setSelectedRange(NSRange(location: midPoint, length: 0))
        roomy.centerCaretIfNeeded(animated: false)
        precondition(roomClip.bounds.origin.y == 0, "Only \"center\" mode moves the page by itself")
        // Clicks and pointer scrolling never re-center; typing and keys do
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        let key = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)
        precondition(WritingTextView.isPointerDriven(click) && !WritingTextView.isPointerDriven(key) && !WritingTextView.isPointerDriven(nil))

        // Releasing the open document so its file can be trashed: the document becomes blank and untitled.
        let document = NSDocument()
        let releasedFile = FileManager.default.temporaryDirectory.appendingPathComponent("quill-release-\(UUID()).md")
        document.fileURL = releasedFile
        let releasing = EditorCommands()
        var loaded: [(String, URL?)] = []
        releasing.loadText = { loaded.append(($0, $1)) }
        SingleDocumentCoordinator.shared.detach(document, using: releasing)
        precondition(document.fileURL == nil, "The file is released before anything else happens")
        precondition(loaded.count == 1 && loaded[0].0 == "" && loaded[0].1 == nil, "The page is emptied and untitled")
        // Regression: the shared color panel must never mutate plain Markdown or
        // issue text-change notifications while SwiftUI lays out its color wells.
        let beforeColor = editor.attributedString()
        let selectionBeforeColor = editor.selectedRange()
        editor.changeColor(nil)
        precondition(editor.attributedString().isEqual(to: beforeColor))
        precondition(editor.selectedRange() == selectionBeforeColor)
        precondition(NSColor(white: 0.5, alpha: 1).quillHex == "#7F7F7F")
        precondition(NSColor(srgbRed: 1.2, green: -0.1, blue: 0.5, alpha: 1).quillHex == "#FF007F")
        let unchanged = editor.string
        editor.bodyFontFamily = "Helvetica"
        editor.lineSpacingRatio = 0.5
        editor.decorate()
        let chosenFont = editor.textStorage!.attribute(.font, at: 1, effectiveRange: nil) as! NSFont
        precondition(chosenFont.familyName == "Helvetica")
        precondition(editor.string == unchanged)
        editor.themeName = "parchment"
        editor.decorate()
        precondition((editor.textStorage!.attribute(.foregroundColor, at: 1, effectiveRange: nil) as? NSColor) == WritingTheme.named("parchment").foreground)
        precondition(editor.string == unchanged)
        editor.bodySize = 30
        editor.decorate()
        precondition(editor.string == unchanged, "Zoom must not change saved Markdown")
        precondition(FocusParagraph.range(in: "One\nsoft\n\nTwo", caret: 5) == NSRange(location: 0, length: 9))
        precondition(FocusParagraph.range(in: "One\n\n", caret: 5) == NSRange(location: 5, length: 0))
        precondition(FocusParagraph.range(in: "", caret: 0) == NSRange(location: 0, length: 0))
        print("Passed: focus tracking/clearing, font switching, soft-line paragraphs; native fonts, source preservation, centered margins, bold insertion/exit/toggle, italic newline exit, Unicode selections.")
    }
}

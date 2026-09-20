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
        let unchanged = editor.string
        editor.bodyFontFamily = "Helvetica"
        editor.lineSpacingRatio = 0.5
        editor.decorate()
        let chosenFont = editor.textStorage!.attribute(.font, at: 1, effectiveRange: nil) as! NSFont
        precondition(chosenFont.familyName == "Helvetica")
        precondition(editor.string == unchanged)
        precondition(FocusParagraph.range(in: "One\nsoft\n\nTwo", caret: 5) == NSRange(location: 0, length: 9))
        precondition(FocusParagraph.range(in: "One\n\n", caret: 5) == NSRange(location: 5, length: 0))
        precondition(FocusParagraph.range(in: "", caret: 0) == NSRange(location: 0, length: 0))
        print("Passed: focus tracking/clearing, font switching, soft-line paragraphs; native fonts, source preservation, centered margins, bold insertion/exit/toggle, italic newline exit, Unicode selections.")
    }
}

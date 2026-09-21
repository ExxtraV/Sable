import AppKit
import Foundation

@main enum ImportChecks {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quill-import-\(getpid())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // HTML: the way text arrives from a web page or Google Docs
        let html = """
        <html><body><h1>The Crossing</h1><p>She was <em>very</em> tired, and <strong>he</strong> was not. See <a href="https://example.com/a">the map</a>.</p>
        <h2>Arrival</h2><ul><li>rope</li><li>lantern</li></ul><ol><li>first</li><li>second</li></ol>
        <p>Stars * and under_scores.</p></body></html>
        """
        let htmlURL = dir.appendingPathComponent("sample.html")
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)
        let fromHTML = try RichTextMarkdown.importDocument(at: htmlURL)
        precondition(fromHTML.contains("# The Crossing"), "Heading 1: \(fromHTML)")
        precondition(fromHTML.contains("She was *very* tired, and **he** was not."), "Italic and bold: \(fromHTML)")
        precondition(fromHTML.contains("[the map](https://example.com/a)"), "Links: \(fromHTML)")
        precondition(fromHTML.contains("## Arrival") || fromHTML.contains("# Arrival"), "A smaller heading: \(fromHTML)")
        precondition(fromHTML.contains("- rope\n- lantern"), "Bullets stay together: \(fromHTML)")
        precondition(fromHTML.contains("1. first\n2. second"), "Numbers count: \(fromHTML)")
        precondition(fromHTML.contains("Stars \\* and under\\_scores."), "Markdown characters in the text are escaped: \(fromHTML)")

        // Word: build a real .docx, then read it back
        let big = NSFont(name: "Helvetica-Bold", size: 24)!, plain = NSFont(name: "Times-Roman", size: 12)!
        let italic = NSFontManager.shared.convert(plain, toHaveTrait: .italicFontMask)
        let boldFont = NSFontManager.shared.convert(plain, toHaveTrait: .boldFontMask)
        let document = NSMutableAttributedString()
        document.append(NSAttributedString(string: "Chapter One\n", attributes: [.font: big]))
        document.append(NSAttributedString(string: "It was ", attributes: [.font: plain]))
        document.append(NSAttributedString(string: "cold", attributes: [.font: italic]))
        document.append(NSAttributedString(string: " and ", attributes: [.font: plain]))
        document.append(NSAttributedString(string: "quiet", attributes: [.font: boldFont]))
        document.append(NSAttributedString(string: ".\n", attributes: [.font: plain]))
        document.append(NSAttributedString(string: "A second paragraph that is ordinary body text, long enough to dominate the document so twelve points is the body size.\n", attributes: [.font: plain]))
        let docx = try document.data(from: NSRange(location: 0, length: document.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.officeOpenXML])
        let docxURL = dir.appendingPathComponent("Draft.docx")
        try docx.write(to: docxURL)
        let fromWord = try RichTextMarkdown.importDocument(at: docxURL)
        precondition(fromWord.hasPrefix("# Chapter One\n\n"), "A big bold line is a heading: \(fromWord)")
        precondition(fromWord.contains("It was *cold* and **quiet**."), "Word italics and bold: \(fromWord)")
        precondition(fromWord.contains("\n\nA second paragraph"), "Paragraphs are separated by a blank line: \(fromWord)")

        // RTF
        let rtf = try document.data(from: NSRange(location: 0, length: document.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        let rtfURL = dir.appendingPathComponent("Draft.rtf")
        try rtf.write(to: rtfURL)
        let fromRTF = try RichTextMarkdown.importDocument(at: rtfURL)
        precondition(fromRTF.contains("It was *cold* and **quiet**."), "RTF: \(fromRTF)")

        // Markdown and text pass through untouched
        let mdURL = dir.appendingPathComponent("Note.md")
        try "# Kept\n\n*as is*\n".write(to: mdURL, atomically: true, encoding: .utf8)
        let passthrough = try RichTextMarkdown.importDocument(at: mdURL)
        precondition(passthrough == "# Kept\n\n*as is*\n")

        // Where imports land: named after the source, never over an existing file
        let first = try DocumentImport.write("one", named: docxURL, in: dir)
        let second = try DocumentImport.write("two", named: docxURL, in: dir)
        precondition(first.lastPathComponent == "Draft.md" && second.lastPathComponent == "Draft 2.md", "Imports don't overwrite: \(first.lastPathComponent), \(second.lastPathComponent)")
        let written = try String(contentsOf: first, encoding: .utf8)
        precondition(written == "one")
        print("Passed: HTML, Word, and RTF import to Markdown (headings, emphasis, links, lists, escapes), text passthrough, safe file naming.")
    }
}

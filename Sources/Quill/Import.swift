import AppKit
import Foundation

/// Turns formatted text (from a Word or Google Docs file, or pasted from a web page) into Markdown: italics, bold,
/// headings, lists, links, and strikethrough survive; fonts, colors, and spacing are left behind.
enum RichTextMarkdown {
    /// Reads a document Sable can import and returns Markdown. Plain text and Markdown files are returned as they are.
    static func importDocument(at url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ["md", "markdown", "txt", "text"].contains(ext) {
            return try String(contentsOf: url, encoding: .utf8)
        }
        let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
        return markdown(from: attributed)
    }

    static let importTypes = ["docx", "doc", "rtf", "rtfd", "odt", "html", "htm", "txt", "md", "markdown"]

    static func markdown(from attributed: NSAttributedString) -> String {
        let text = attributed.string as NSString
        guard text.length > 0 else { return "" }
        let body = bodySize(of: attributed)
        struct Paragraph { var attributed: NSAttributedString; var list: NSTextList?; var depth = 0; var size: CGFloat; var bold: Bool }
        var paragraphs: [Paragraph] = []
        var location = 0
        while location < text.length {
            var start = 0, end = 0, contentsEnd = 0
            text.getParagraphStart(&start, end: &end, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
            location = end
            let range = NSRange(location: start, length: contentsEnd - start)
            guard range.length > 0 else { continue }
            var paragraph = attributed.attributedSubstring(from: range)
            let style = attributed.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
            var list: NSTextList?, depth = 0
            if let lists = style?.textLists, let last = lists.last {
                list = last
                depth = lists.count - 1
                // The importer writes the bullet or number into the text ("\t•\t"); the list marker replaces it.
                if let tail = paragraph.string.range(of: "^[\\t ]*[^\\t]*\\t", options: .regularExpression) {
                    paragraph = paragraph.attributedSubstring(from: NSRange(tail.upperBound..., in: paragraph.string))
                }
            }
            guard !paragraph.string.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            paragraphs.append(Paragraph(attributed: paragraph, list: list, depth: depth, size: dominantSize(of: paragraph), bold: isAllBold(paragraph)))
        }
        // Headings are the short lines set larger than the body text; the biggest size is #, the next ##, then ###.
        func isHeading(_ p: Paragraph) -> Bool {
            p.list == nil && p.attributed.length < 140 && (p.size >= body * 1.15 || (p.size > body * 1.05 && p.bold))
        }
        let headingSizes = Array(Set(paragraphs.filter(isHeading).map(\.size))).sorted(by: >)

        var blocks: [(text: String, list: Bool)] = []
        var listNumbers: [Int: Int] = [:]
        for paragraph in paragraphs {
            if let list = paragraph.list {
                let inline = inlineMarkdown(paragraph.attributed, headingLike: false).trimmingCharacters(in: .whitespaces)
                let marker = list.marker(forItemNumber: 1)
                let ordered = !(marker.contains("{") || marker.first.map { "•◦▪▫●○■□-–—*".contains($0) } == true)
                let indent = String(repeating: "  ", count: paragraph.depth)
                if ordered {
                    listNumbers[paragraph.depth, default: 0] += 1
                    blocks.append(("\(indent)\(listNumbers[paragraph.depth]!). " + inline, true))
                } else {
                    listNumbers[paragraph.depth] = 0
                    blocks.append(("\(indent)- " + inline, true))
                }
                continue
            }
            listNumbers = [:]
            if isHeading(paragraph), let rank = headingSizes.firstIndex(of: paragraph.size) {
                let title = inlineMarkdown(paragraph.attributed, headingLike: true).trimmingCharacters(in: .whitespaces)
                blocks.append((String(repeating: "#", count: min(3, rank + 1)) + " " + title, false))
            } else {
                blocks.append((inlineMarkdown(paragraph.attributed, headingLike: false).trimmingCharacters(in: .whitespaces), false))
            }
        }
        var output = ""
        for (index, block) in blocks.enumerated() {
            if index > 0 { output += (block.list && blocks[index - 1].list) ? "\n" : "\n\n" }
            output += block.text
        }
        return output + "\n"
    }

    // MARK: Runs

    private static func inlineMarkdown(_ attributed: NSAttributedString, headingLike: Bool) -> String {
        var pieces: [(text: String, bold: Bool, italic: Bool, strike: Bool, code: Bool, link: URL?)] = []
        let manager = NSFontManager.shared
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            var text = attributed.attributedSubstring(from: range).string
                .replacingOccurrences(of: "\u{00A0}", with: " ")
                .replacingOccurrences(of: "\u{2028}", with: "  \n")
                .replacingOccurrences(of: "\u{000B}", with: "  \n")
                .replacingOccurrences(of: "\u{FFFC}", with: "")
            guard !text.isEmpty else { return }
            let font = attributes[.font] as? NSFont
            let traits = font.map { manager.traits(of: $0) } ?? []
            let bold = !headingLike && traits.contains(.boldFontMask)
            let italic = traits.contains(.italicFontMask)
            let code = font?.isFixedPitch == true
            let strike = (attributes[.strikethroughStyle] as? Int ?? 0) != 0
            var link: URL?
            if let value = attributes[.link] as? URL { link = value } else if let value = attributes[.link] as? String { link = URL(string: value) }
            text = escape(text, code: code)
            pieces.append((text, bold, italic, strike, code, link))
        }
        // Join neighbors that share a look, so **a** **b** becomes **a b**.
        var merged: [(text: String, bold: Bool, italic: Bool, strike: Bool, code: Bool, link: URL?)] = []
        for piece in pieces {
            if let last = merged.last, last.bold == piece.bold, last.italic == piece.italic, last.strike == piece.strike, last.code == piece.code, last.link == piece.link {
                merged[merged.count - 1].text += piece.text
            } else { merged.append(piece) }
        }
        var result = ""
        for piece in merged {
            // Markers hug the words: spaces at the edges stay outside them.
            let leading = String(piece.text.prefix { $0 == " " })
            let trailing = String(piece.text.reversed().prefix { $0 == " " })
            var core = piece.text.trimmingCharacters(in: .whitespaces)
            guard !core.isEmpty else { result += piece.text; continue }
            if piece.code { core = "`" + core + "`" }
            if piece.strike { core = "~~" + core + "~~" }
            if piece.bold && piece.italic { core = "***" + core + "***" }
            else if piece.bold { core = "**" + core + "**" }
            else if piece.italic { core = "*" + core + "*" }
            if let link = piece.link, ["http", "https", "mailto"].contains(link.scheme?.lowercased() ?? "") { core = "[" + core + "](" + link.absoluteString + ")" }
            result += leading + core + trailing
        }
        return result
    }

    /// Keeps characters that mean something in Markdown from doing so.
    private static func escape(_ text: String, code: Bool) -> String {
        guard !code else { return text }
        var result = ""
        for character in text {
            if character == "*" || character == "_" || character == "\\" || character == "`" || character == "~" { result.append("\\") }
            result.append(character)
        }
        return result
    }

    // MARK: Sizes

    private static func bodySize(of attributed: NSAttributedString) -> CGFloat {
        var weights: [CGFloat: Int] = [:]
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let font = value as? NSFont { weights[(font.pointSize * 2).rounded() / 2, default: 0] += range.length }
        }
        return weights.max { $0.value < $1.value }?.key ?? 12
    }

    private static func dominantSize(of attributed: NSAttributedString) -> CGFloat {
        var weights: [CGFloat: Int] = [:]
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, _ in
            if let font = value as? NSFont { weights[(font.pointSize * 2).rounded() / 2, default: 0] += range.length }
        }
        return weights.max { $0.value < $1.value }?.key ?? 12
    }

    private static func isAllBold(_ attributed: NSAttributedString) -> Bool {
        var bold = true
        attributed.enumerateAttribute(.font, in: NSRange(location: 0, length: attributed.length)) { value, range, stop in
            let text = attributed.attributedSubstring(from: range).string
            guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
            if let font = value as? NSFont, NSFontManager.shared.traits(of: font).contains(.boldFontMask) { return }
            bold = false
            stop.pointee = true
        }
        return bold
    }
}

/// Where an imported document lands, and what it is called.
enum DocumentImport {
    /// A new Markdown file named after `source`, in `folder`, without overwriting anything.
    static func write(_ markdown: String, named source: URL, in folder: URL) throws -> URL {
        let base = source.deletingPathExtension().lastPathComponent
        var url = folder.appendingPathComponent(base + ".md")
        var number = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) \(number).md")
            number += 1
        }
        // Never over a file that appeared with the same name in the meantime.
        try Data(markdown.utf8).write(to: url, options: .withoutOverwriting)
        return url
    }
}

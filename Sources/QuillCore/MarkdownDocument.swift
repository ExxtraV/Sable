import Foundation

/// The one description of what a Markdown line is. The editor's styling, Reading Mode, and every export ask these
/// same questions, so a scene break, a note, or a list item is the same thing everywhere.
public enum MarkdownLines {
    /// `---`, `***`, `___`, or `* * *` on a line of its own.
    public static func isSceneBreak(_ line: String) -> Bool {
        let compact = line.filter { !$0.isWhitespace }
        guard compact.count >= 3, let first = compact.first, "-*_".contains(first) else { return false }
        return compact.allSatisfy { $0 == first }
    }

    /// A bare "****" is what pressing ⌘B on nothing types, so it stays bold rather than becoming a scene break.
    public static func isRule(_ line: String) -> Bool {
        isSceneBreak(line) && line.trimmingCharacters(in: .whitespaces) != "****"
    }

    /// `<!-- … -->`, an author's note that never reaches Reading Mode or an export.
    public static let commentPattern = "<!--[\\s\\S]*?(?:-->|\\z)"

    public static func removingComments(_ text: String) -> String {
        text.replacingOccurrences(of: commentPattern, with: "", options: .regularExpression)
    }

    /// The `---` metadata block at the very top of a file, if there is one.
    public static func frontMatterRange(in text: String) -> NSRange {
        let ns = text as NSString
        guard ns.hasPrefix("---\n") else { return NSRange(location: 0, length: 0) }
        let close = ns.range(of: "\n---", options: [], range: NSRange(location: 3, length: ns.length - 3))
        guard close.location != NSNotFound else { return NSRange(location: 0, length: 0) }
        return NSRange(location: 0, length: NSMaxRange(close))
    }

    /// `| a | b |`
    public static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.count >= 2 && trimmed.hasPrefix("|") && trimmed.hasSuffix("|")
    }

    /// The `|---|:--:|` line under a table's header.
    public static func isTableDivider(_ line: String) -> Bool {
        isTableRow(line) && line.contains("-") && line.allSatisfy { "|-: \t".contains($0) }
    }

    public static func isFence(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("```") { return "```" }
        if trimmed.hasPrefix("~~~") { return "~~~" }
        return nil
    }
}

public struct MarkdownRun: Equatable, Sendable {
    public var text: String
    public var bold = false
    public var italic = false
    public var code = false
    public var strike = false
    public var link: String?
    public init(text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, strike: Bool = false, link: String? = nil) {
        self.text = text; self.bold = bold; self.italic = italic; self.code = code; self.strike = strike; self.link = link
    }
}

public enum MarkdownBlock: Equatable, Sendable {
    case heading(Int, [MarkdownRun])
    case paragraph([MarkdownRun])
    case quote([MarkdownRun])
    case bullet([MarkdownRun], depth: Int)
    case numbered(Int, [MarkdownRun], depth: Int)
    case task(done: Bool, [MarkdownRun], depth: Int)
    case sceneBreak
    case code(String)
    /// Rows of cells; `header` is true when the first row is followed by a divider line.
    case table([[String]], header: Bool)
    case image(alt: String, source: String)
}

public enum MarkdownBlocks {
    /// Turns Markdown into paragraphs, headings, quotes, lists, tasks, tables, scene breaks, and code, joining soft
    /// line breaks. Notes (`<!-- -->`) and a metadata block at the top are left out.
    public static func parse(_ markdown: String, skipFrontMatter: Bool = true) -> [MarkdownBlock] {
        var source = markdown
        if skipFrontMatter {
            let front = MarkdownLines.frontMatterRange(in: source)
            if front.length > 0 { source = (source as NSString).substring(from: front.length) }
        }
        let cleaned = MarkdownLines.removingComments(source)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var table: [String] = []
        var fence: String?
        var code: [String] = []
        func flushParagraph() {
            if !paragraph.isEmpty { blocks.append(.paragraph(runs(paragraph.joined(separator: " ")))); paragraph = [] }
        }
        func flushQuote() {
            if !quote.isEmpty { blocks.append(.quote(runs(quote.joined(separator: " ")))); quote = [] }
        }
        func flushTable() {
            guard !table.isEmpty else { return }
            let header = table.count > 1 && MarkdownLines.isTableDivider(table[1])
            let rows = table.filter { !MarkdownLines.isTableDivider($0) }.map { row -> [String] in
                var cells = row.trimmingCharacters(in: .whitespaces).components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                if cells.first == "" { cells.removeFirst() }
                if cells.last == "" { cells.removeLast() }
                return cells
            }
            blocks.append(.table(rows, header: header))
            table = []
        }
        func flushAll() { flushParagraph(); flushQuote(); flushTable() }
        for raw in cleaned.components(separatedBy: "\n") {
            let line = raw.replacingOccurrences(of: "\r", with: "")
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let marker = fence {
                if trimmed.hasPrefix(marker) { blocks.append(.code(code.joined(separator: "\n"))); code = []; fence = nil } else { code.append(line) }
                continue
            }
            if let opening = MarkdownLines.isFence(trimmed) { flushAll(); fence = opening; continue }
            if trimmed.isEmpty { flushAll(); continue }
            if MarkdownLines.isSceneBreak(trimmed) { flushAll(); blocks.append(.sceneBreak); continue }
            if MarkdownLines.isTableRow(trimmed) { flushParagraph(); flushQuote(); table.append(trimmed); continue }
            flushTable()
            if let match = trimmed.range(of: "^#{1,6}\\s+", options: .regularExpression) {
                flushParagraph(); flushQuote()
                let level = trimmed[match].filter { $0 == "#" }.count
                let title = String(trimmed[match.upperBound...]).replacingOccurrences(of: "\\s+#+\\s*$", with: "", options: .regularExpression)
                blocks.append(.heading(level, runs(title)))
                continue
            }
            if let image = imageLine(trimmed) { flushAll(); blocks.append(.image(alt: image.alt, source: image.source)); continue }
            if let prefix = MarkdownEditing.prefix(of: line) {
                let content = (line as NSString).substring(from: prefix.length)
                if case .quote = prefix.marker {
                    flushParagraph()
                    quote.append(content)
                    continue
                }
                flushParagraph(); flushQuote()
                let depth = min(4, prefix.indentWidth / 2)
                switch prefix.marker {
                case .quote: break
                case .bullet:
                    if let task = prefix.task { blocks.append(.task(done: task.lowercased() == "[x]", runs(content), depth: depth)) }
                    else { blocks.append(.bullet(runs(content), depth: depth)) }
                case let .number(number, _): blocks.append(.numbered(number, runs(content), depth: depth))
                }
                continue
            }
            flushQuote()
            paragraph.append(trimmed)
        }
        if fence != nil, !code.isEmpty { blocks.append(.code(code.joined(separator: "\n"))) }
        flushAll()
        return blocks
    }

    /// `![alt](source)` alone on a line.
    static func imageLine(_ line: String) -> (alt: String, source: String)? {
        guard line.hasPrefix("!["), line.hasSuffix(")"),
              let match = try? NSRegularExpression(pattern: "^!\\[([^\\]]*)\\]\\(([^)]*)\\)$").firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else { return nil }
        let ns = line as NSString
        return (ns.substring(with: match.range(at: 1)), ns.substring(with: match.range(at: 2)))
    }

    /// Bold, italic, code, strikethrough, and link runs. Images inside a paragraph are dropped, keeping the page to words.
    public static func runs(_ inline: String) -> [MarkdownRun] {
        let withoutImages = inline.replacingOccurrences(of: "!\\[[^\\]]*\\]\\([^)]*\\)", with: "", options: .regularExpression)
        guard let parsed = try? AttributedString(markdown: withoutImages, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) else {
            return [MarkdownRun(text: withoutImages)]
        }
        var result: [MarkdownRun] = []
        for run in parsed.runs {
            let intent = run.inlinePresentationIntent ?? []
            let piece = MarkdownRun(text: String(parsed[run.range].characters), bold: intent.contains(.stronglyEmphasized),
                                    italic: intent.contains(.emphasized), code: intent.contains(.code), strike: intent.contains(.strikethrough),
                                    link: run.link?.absoluteString)
            if let last = result.last, last.bold == piece.bold, last.italic == piece.italic, last.code == piece.code, last.strike == piece.strike, last.link == piece.link {
                result[result.count - 1].text += piece.text
            } else { result.append(piece) }
        }
        return result
    }

    public static func plain(_ runs: [MarkdownRun]) -> String { runs.map(\.text).joined() }
}

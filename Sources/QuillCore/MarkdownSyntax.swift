import Foundation

public struct MarkdownSpan {
    public enum Kind: Sendable { case bold, italic, boldItalic, code, link, heading(Int), quote, list, strike
        /// A scene break or horizontal rule on its own line.
        case rule
        /// `<!-- … -->`, an author's note that never reaches an export.
        case comment
        case image
        /// `- [ ]` or `- [x]`; `range` is the whole line and `content` is the checkbox.
        case task(done: Bool)
        case footnote
        case table }
    public let kind: Kind
    public let range: NSRange
    public let content: NSRange
    public let markers: [NSRange]
    public let closing: NSRange?
    public let destination: NSRange?
}

public struct ChapterHeading: Identifiable {
    public var id: Int { range.location }
    public let title: String
    public let level: Int
    public let range: NSRange
}

/// An intentionally small source-highlighting grammar, not a Markdown-to-HTML renderer.
///
/// Only two things reach across lines: fenced code and `<!-- -->` notes (the "blocks"). Every other pattern stops at a
/// `\n`, so the spans inside a run of whole lines depend only on those lines and on the blocks. That is what lets the
/// editor restyle just the paragraph being written: `spans(in:range:blocks:)` over whole lines gives exactly the spans a
/// whole-document pass would give there.
public enum MarkdownSyntax {
    private static func expression(_ pattern: String) -> NSRegularExpression { try! NSRegularExpression(pattern: pattern) }
    private static let fence = expression("(?ms)^ {0,3}(`{3,}|~{3,})[^\\n]*\\n.*?(?:^ {0,3}\\1[ \\t]*(?:$)|\\z)")
    private static let comment = expression(MarkdownLines.commentPattern)
    private static let inlineCode = expression("(?<![\\\\`])(`+)([^`\\n]+)\\1(?!`)")
    private static let image = expression("!\\[([^]\\n]*)\\]\\(([^)\\n]*)\\)")
    private static let link = expression("(?<![\\\\!])\\[([^]\\n]*)\\]\\(([^)\\n]*)\\)")
    // Longest delimiters first prevents triple emphasis being consumed as bold.
    private static let emphasis: [(NSRegularExpression, MarkdownSpan.Kind)] = [
        (expression("(?<![\\\\*])(\\*{3})([^*\\n]*?)\\1(?!\\*)"), .boldItalic),
        (expression("(?<![\\\\*])(\\*{2})((?:[^*\\n]|\\*(?!\\*))*?)\\1(?!\\*)"), .bold),
        (expression("(?<![\\\\_\\p{L}\\p{N}])(__)([^_\\n]*?)\\1(?![_\\p{L}\\p{N}])"), .bold),
        (expression("(?<![\\\\*])(\\*)([^*\\n]*?)\\1(?!\\*)"), .italic),
        (expression("(?<![\\\\_\\p{L}\\p{N}])(_)([^_\\n]*?)\\1(?![_\\p{L}\\p{N}])"), .italic),
        (expression("(?<![\\\\~])(~~)([^~\\n]*?)\\1(?!~)"), .strike)
    ]
    private static let heading = expression("(?m)^ {0,3}(#{1,6})[ \\t]+([^\\n]+)")
    private static let headingStart = expression("(?m)^ {0,3}#{1,6}[ \\t]+[^\\n]")
    private static let footnote = expression("\\[\\^[^\\]\\s]+\\]:?")
    /// Lookarounds and anchors see the text around a range, so a match inside it is the same as in a whole-text search.
    private static let bounds: NSRegularExpression.MatchingOptions = [.withTransparentBounds, .withoutAnchoringBounds]

    public static func spans(in text: String) -> [MarkdownSpan] {
        spans(in: text, range: NSRange(location: 0, length: (text as NSString).length), blocks: blocks(in: text))
    }

    /// Fenced code and notes, the only spans that can cross a line break, in the order a full pass applies them.
    public static func blocks(in text: String) -> [MarkdownSpan] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        var result: [MarkdownSpan] = []
        for match in fence.matches(in: text, range: whole) {
            result.append(MarkdownSpan(kind: .code, range: match.range, content: match.range, markers: [], closing: nil, destination: nil))
        }
        let fences = result.map(\.range)
        for match in comment.matches(in: text, range: whole) where !fences.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
            result.append(MarkdownSpan(kind: .comment, range: match.range, content: match.range, markers: [], closing: nil, destination: nil))
        }
        return result
    }

    /// The spans a whole-text pass finds inside `range`, which must start at the beginning of a line and end just after a
    /// `\n` (or at the end of the text). `blocks` are the text's `blocks(in:)`; the part of each that falls in `range` leads the list.
    public static func spans(in text: String, range: NSRange, blocks: [MarkdownSpan]) -> [MarkdownSpan] {
        let source = text as NSString
        func matches(_ regex: NSRegularExpression) -> [NSTextCheckingResult] { regex.matches(in: text, options: bounds, range: range) }
        var result: [MarkdownSpan] = []
        var protected: [NSRange] = []
        for block in blocks {
            let part = NSIntersectionRange(block.range, range)
            guard part.length > 0 else { continue }
            protected.append(block.range)
            result.append(part == block.range ? block : MarkdownSpan(kind: block.kind, range: part, content: part, markers: [], closing: nil, destination: nil))
        }
        func available(_ range: NSRange) -> Bool {
            !protected.contains { NSIntersectionRange($0, range).length > 0 }
        }
        for match in matches(inlineCode) where available(match.range) {
            protected.append(match.range)
            result.append(MarkdownSpan(kind: .code, range: match.range, content: match.range(at: 2), markers: [match.range(at: 1), NSRange(location: NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length)], closing: NSRange(location: NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length), destination: nil))
        }
        // A scene break is protected before emphasis is looked for, or "* * *" would read as italics. What counts as one
        // is decided in MarkdownLines, the same place Reading Mode and the exports ask.
        let frontMatter = MarkdownLines.frontMatterRange(in: text)
        var lines: [(line: String, range: NSRange)] = []
        source.enumerateSubstrings(in: range, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lines.append((source.substring(with: range), range))
        }
        for (line, range) in lines where MarkdownLines.isRule(line) && line.prefix(while: { $0 == " " }).count <= 3
            && available(range) && NSIntersectionRange(frontMatter, range).length == 0 {
            protected.append(range)
            result.append(MarkdownSpan(kind: .rule, range: range, content: range, markers: [], closing: nil, destination: nil))
        }
        for match in matches(image) where available(match.range) {
            let alt = match.range(at: 1)
            protected.append(match.range)
            result.append(MarkdownSpan(kind: .image, range: match.range, content: alt,
                markers: [NSRange(location: match.range.location, length: 2), NSRange(location: NSMaxRange(alt), length: NSMaxRange(match.range) - NSMaxRange(alt))],
                closing: nil, destination: match.range(at: 2)))
        }
        for match in matches(link) where available(match.range) {
            let label = match.range(at: 1), destination = match.range(at: 2)
            result.append(MarkdownSpan(kind: .link, range: match.range, content: label,
                markers: [NSRange(location: match.range.location, length: 1), NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label))],
                closing: NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)), destination: destination))
            protected.append(NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)))
        }
        for (regex, kind) in emphasis {
            for match in matches(regex) where available(match.range) {
                let opening = match.range(at: 1)
                let closing = NSRange(location: NSMaxRange(match.range) - opening.length, length: opening.length)
                result.append(MarkdownSpan(kind: kind, range: match.range, content: match.range(at: 2), markers: [opening, closing], closing: closing, destination: nil))
            }
        }
        for match in matches(heading) where available(match.range) {
            result.append(MarkdownSpan(kind: .heading(match.range(at: 1).length), range: match.range, content: match.range(at: 2), markers: [match.range(at: 1)], closing: nil, destination: nil))
        }
        // Quotes, lists, and tasks are read by the same line classifier the editor's Return key and the exports use.
        for (line, range) in lines where available(range) {
            if let prefix = MarkdownEditing.prefix(of: line) {
                if case .quote = prefix.marker {
                    let marker = NSRange(location: range.location + prefix.indent.utf16.count, length: prefix.length - prefix.indent.utf16.count)
                    result.append(MarkdownSpan(kind: .quote, range: range, content: NSRange(location: range.location + prefix.length, length: range.length - prefix.length), markers: [marker], closing: nil, destination: nil))
                } else {
                    let content = NSRange(location: range.location + prefix.markerLength, length: range.length - prefix.markerLength)
                    result.append(MarkdownSpan(kind: .list, range: range, content: content, markers: [NSRange(location: range.location, length: prefix.markerLength)], closing: nil, destination: nil))
                    if let box = prefix.task {
                        let done = box.lowercased() == "[x]"
                        result.append(MarkdownSpan(kind: .task(done: done), range: range, content: NSRange(location: range.location + prefix.markerLength, length: 3), markers: [], closing: nil, destination: nil))
                    }
                }
            } else if MarkdownLines.isTableRow(line) {
                result.append(MarkdownSpan(kind: .table, range: range, content: range, markers: [], closing: nil, destination: nil))
            }
        }
        for match in matches(footnote) where available(match.range) {
            result.append(MarkdownSpan(kind: .footnote, range: match.range, content: match.range, markers: [], closing: nil, destination: nil))
        }
        return result
    }

    /// Only the lines that start like a heading are parsed, so the outline stays cheap in a long manuscript.
    public static func headings(in text: String) -> [ChapterHeading] {
        let source = text as NSString
        let candidates = headingStart.matches(in: text, range: NSRange(location: 0, length: source.length))
        guard !candidates.isEmpty else { return [] }
        let blocks = blocks(in: text)
        var result: [ChapterHeading] = []
        var done = -1
        for candidate in candidates where candidate.range.location >= done {
            let line = TextLines.lines(in: source, around: NSRange(location: candidate.range.location, length: 0))
            done = NSMaxRange(line)
            for span in spans(in: text, range: line, blocks: blocks) {
                guard case let .heading(level) = span.kind else { continue }
                result.append(ChapterHeading(title: source.substring(with: span.content), level: level, range: span.range))
            }
        }
        return result
    }

    public static func exitOffset(in text: String, selection: NSRange) -> Int? {
        exitOffset(in: text, selection: selection, blocks: blocks(in: text))
    }

    /// Only the line holding the end of the selection can have a closing marker or link destination the caret is inside.
    public static func exitOffset(in text: String, selection: NSRange, blocks: [MarkdownSpan]) -> Int? {
        let end = NSMaxRange(selection)
        let source = text as NSString
        guard end <= source.length else { return nil }
        let line = TextLines.lines(in: source, around: NSRange(location: end, length: 0))
        return spans(in: text, range: line, blocks: blocks).compactMap { span -> Int? in
            guard let closing = span.closing else { return nil }
            if let destination = span.destination, selection.location >= destination.location, end <= NSMaxRange(destination) {
                return NSMaxRange(span.range)
            }
            if end >= closing.location && end < NSMaxRange(closing) { return NSMaxRange(closing) }
            return nil
        }.max()
    }
}

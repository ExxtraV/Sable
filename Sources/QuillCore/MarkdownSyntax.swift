import Foundation

public struct MarkdownSpan {
    public enum Kind { case bold, italic, boldItalic, code, link, heading(Int), quote, list, strike
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
public enum MarkdownSyntax {
    public static func spans(in text: String) -> [MarkdownSpan] {
        let source = text as NSString
        let whole = NSRange(location: 0, length: source.length)
        func matches(_ pattern: String) -> [NSTextCheckingResult] {
            (try? NSRegularExpression(pattern: pattern).matches(in: text, range: whole)) ?? []
        }
        var result: [MarkdownSpan] = []
        var protected: [NSRange] = []
        for match in matches("(?ms)^ {0,3}(`{3,}|~{3,})[^\\n]*\\n.*?(?:^ {0,3}\\1[ \\t]*(?:$)|\\z)") {
            protected.append(match.range)
            result.append(MarkdownSpan(kind: .code, range: match.range, content: match.range, markers: [], closing: nil, destination: nil))
        }
        func available(_ range: NSRange) -> Bool {
            !protected.contains { NSIntersectionRange($0, range).length > 0 }
        }
        for match in matches(MarkdownLines.commentPattern) where available(match.range) {
            protected.append(match.range)
            result.append(MarkdownSpan(kind: .comment, range: match.range, content: match.range, markers: [], closing: nil, destination: nil))
        }
        for match in matches("(?<![\\\\`])(`+)([^`\\n]+)\\1(?!`)") where available(match.range) {
            protected.append(match.range)
            result.append(MarkdownSpan(kind: .code, range: match.range, content: match.range(at: 2), markers: [match.range(at: 1), NSRange(location: NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length)], closing: NSRange(location: NSMaxRange(match.range) - match.range(at: 1).length, length: match.range(at: 1).length), destination: nil))
        }
        // A scene break is protected before emphasis is looked for, or "* * *" would read as italics. What counts as one
        // is decided in MarkdownLines, the same place Reading Mode and the exports ask.
        let frontMatter = MarkdownLines.frontMatterRange(in: text)
        var lines: [(line: String, range: NSRange)] = []
        source.enumerateSubstrings(in: whole, options: [.byLines, .substringNotRequired]) { _, range, _, _ in
            lines.append((source.substring(with: range), range))
        }
        for (line, range) in lines where MarkdownLines.isRule(line) && line.prefix(while: { $0 == " " }).count <= 3
            && available(range) && NSIntersectionRange(frontMatter, range).length == 0 {
            protected.append(range)
            result.append(MarkdownSpan(kind: .rule, range: range, content: range, markers: [], closing: nil, destination: nil))
        }
        for match in matches("!\\[([^]\\n]*)\\]\\(([^)\\n]*)\\)") where available(match.range) {
            let alt = match.range(at: 1)
            protected.append(match.range)
            result.append(MarkdownSpan(kind: .image, range: match.range, content: alt,
                markers: [NSRange(location: match.range.location, length: 2), NSRange(location: NSMaxRange(alt), length: NSMaxRange(match.range) - NSMaxRange(alt))],
                closing: nil, destination: match.range(at: 2)))
        }
        for match in matches("(?<![\\\\!])\\[([^]\\n]*)\\]\\(([^)\\n]*)\\)") where available(match.range) {
            let label = match.range(at: 1), destination = match.range(at: 2)
            result.append(MarkdownSpan(kind: .link, range: match.range, content: label,
                markers: [NSRange(location: match.range.location, length: 1), NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label))],
                closing: NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)), destination: destination))
            protected.append(NSRange(location: NSMaxRange(label), length: NSMaxRange(match.range) - NSMaxRange(label)))
        }
        // Longest delimiters first prevents triple emphasis being consumed as bold.
        let rules: [(String, MarkdownSpan.Kind)] = [
            ("(?<![\\\\*])(\\*{3})([^*\\n]*?)\\1(?!\\*)", .boldItalic),
            ("(?<![\\\\*])(\\*{2})((?:[^*\\n]|\\*(?!\\*))*?)\\1(?!\\*)", .bold),
            ("(?<![\\\\_\\p{L}\\p{N}])(__)([^_\\n]*?)\\1(?![_\\p{L}\\p{N}])", .bold),
            ("(?<![\\\\*])(\\*)([^*\\n]*?)\\1(?!\\*)", .italic),
            ("(?<![\\\\_\\p{L}\\p{N}])(_)([^_\\n]*?)\\1(?![_\\p{L}\\p{N}])", .italic),
            ("(?<![\\\\~])(~~)([^~\\n]*?)\\1(?!~)", .strike)
        ]
        for (pattern, kind) in rules {
            for match in matches(pattern) where available(match.range) {
                let opening = match.range(at: 1)
                let closing = NSRange(location: NSMaxRange(match.range) - opening.length, length: opening.length)
                result.append(MarkdownSpan(kind: kind, range: match.range, content: match.range(at: 2), markers: [opening, closing], closing: closing, destination: nil))
            }
        }
        for match in matches("(?m)^ {0,3}(#{1,6})[ \\t]+([^\\n]+)") where available(match.range) {
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
        for match in matches("\\[\\^[^\\]\\s]+\\]:?") where available(match.range) {
            result.append(MarkdownSpan(kind: .footnote, range: match.range, content: match.range, markers: [], closing: nil, destination: nil))
        }
        return result
    }

    public static func headings(in text: String) -> [ChapterHeading] {
        spans(in: text).compactMap { span in
            guard case let .heading(level) = span.kind else { return nil }
            return ChapterHeading(title: (text as NSString).substring(with: span.content), level: level, range: span.range)
        }
    }

    public static func exitOffset(in text: String, selection: NSRange) -> Int? {
        let end = NSMaxRange(selection)
        return spans(in: text).compactMap { span -> Int? in
            guard let closing = span.closing else { return nil }
            if let destination = span.destination, selection.location >= destination.location, end <= NSMaxRange(destination) {
                return NSMaxRange(span.range)
            }
            if end >= closing.location && end < NSMaxRange(closing) { return NSMaxRange(closing) }
            return nil
        }.max()
    }
}

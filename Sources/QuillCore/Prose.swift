import Foundation

public enum Prose {
    public static let defaultWords = "very, really, just, quite, actually, basically, literally, somewhat, rather"

    // Keep code, link destinations, and YAML metadata out of prose review. The first three can span lines.
    private static let blockPatterns = [#"(?ms)\A---\r?\n.*?^---[ \t]*$"#, "(?ms)^```[^\\n]*\\n.*?^```[^\\n]*$", "(?ms)^~~~[^\\n]*\\n.*?^~~~[^\\n]*$"]
        .map { try! NSRegularExpression(pattern: $0) }
    private static let linePatterns = ["`[^`\\n]*`", "\\]\\([^\\n)]*\\)", "https?://[^\\s>]+"].map { try! NSRegularExpression(pattern: $0) }
    private static let bounds: NSRegularExpression.MatchingOptions = [.withTransparentBounds, .withoutAnchoringBounds]

    // UTF-16 ranges match Apple's text system, including text containing emoji.
    public static func suggestions(in text: String, words: String) -> [NSRange] {
        suggestions(in: text, words: words, range: NSRange(location: 0, length: (text as NSString).length), blocks: protectedBlocks(in: text))
    }

    /// Front matter and fenced code, the protected parts of the text that can cross a line break.
    public static func protectedBlocks(in text: String) -> [NSRange] {
        let whole = NSRange(location: 0, length: (text as NSString).length)
        return blockPatterns.flatMap { $0.matches(in: text, range: whole).map(\.range) }
    }

    /// The end of the front matter as prose review sees it, or 0.
    public static func frontMatterEnd(in text: String) -> Int {
        guard text.hasPrefix("---") else { return 0 }
        return blockPatterns[0].firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)).map { NSMaxRange($0.range) } ?? 0
    }

    /// The suggestions a whole-text search finds inside `range`, which must be whole lines (see `TextLines`); `blocks`
    /// are the text's `protectedBlocks(in:)`.
    public static func suggestions(in text: String, words: String, range: NSRange, blocks: [NSRange]) -> [NSRange] {
        let candidates = words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return [] }
        let protected = blocks.filter { NSIntersectionRange($0, range).length > 0 }
            + linePatterns.flatMap { $0.matches(in: text, options: bounds, range: range).map(\.range) }
        let pattern = "(?i)(?<![\\p{L}\\p{N}_])(?:" + candidates.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, options: bounds, range: range).map(\.range).filter { range in
            !protected.contains { NSIntersectionRange($0, range).length > 0 }
        }
    }

    /// True when every suggestion stays on one line, which region-by-region review relies on.
    public static func wordsStayOnOneLine(_ words: String) -> Bool { !words.contains("\n") && !words.contains("\r") }

    public static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

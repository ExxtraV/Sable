import Foundation

public enum Prose {
    public static let defaultWords = "very, really, just, quite, actually, basically, literally, somewhat, rather"

    // UTF-16 ranges match Apple's text system, including text containing emoji.
    public static func suggestions(in text: String, words: String) -> [NSRange] {
        let candidates = words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return [] }
        let source = text as NSString
        let whole = NSRange(location: 0, length: source.length)
        // Keep code, link destinations, and YAML metadata out of prose review.
        let protectedPatterns = ["(?ms)\\A---\\r?\\n.*?^---[ \\t]*$", "(?ms)^```[^\\n]*\\n.*?^```[^\\n]*$", "(?ms)^~~~[^\\n]*\\n.*?^~~~[^\\n]*$", "`[^`\\n]*`", "\\]\\([^\\n)]*\\)", "https?://[^\\s>]+"]
        let protected = protectedPatterns.flatMap { pattern in
            (try? NSRegularExpression(pattern: pattern).matches(in: text, range: whole).map(\.range)) ?? []
        }
        let pattern = "(?i)(?<![\\p{L}\\p{N}_])(?:" + candidates.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|") + ")(?![\\p{L}\\p{N}_])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        return regex.matches(in: text, range: whole).map(\.range).filter { range in
            !protected.contains { NSIntersectionRange($0, range).length > 0 }
        }
    }

    public static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }
}

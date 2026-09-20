import Foundation

public enum FocusParagraph {
    /// Soft line breaks belong to one Markdown paragraph; blank lines separate paragraphs.
    public static func range(in text: String, caret: Int) -> NSRange {
        let source = text as NSString
        let position = min(max(0, caret), source.length)
        guard source.length > 0 else { return NSRange(location: 0, length: 0) }
        if position == source.length, text.hasSuffix("\n") { return NSRange(location: position, length: 0) }
        var lines: [(NSRange, Bool)] = []
        var index = 0
        while index < source.length {
            let line = source.lineRange(for: NSRange(location: index, length: 0))
            let blank = source.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            lines.append((line, blank))
            index = NSMaxRange(line)
        }
        guard let current = lines.firstIndex(where: { NSLocationInRange(position, $0.0) }) ?? (position == source.length ? lines.indices.last : nil) else {
            return NSRange(location: position, length: 0)
        }
        if lines[current].1 { return lines[current].0 }
        var first = current, last = current
        while first > 0 && !lines[first - 1].1 { first -= 1 }
        while last + 1 < lines.count && !lines[last + 1].1 { last += 1 }
        return NSRange(location: lines[first].0.location, length: NSMaxRange(lines[last].0) - lines[first].0.location)
    }
}

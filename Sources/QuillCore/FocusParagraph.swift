import Foundation

public enum FocusParagraph {
    /// Soft line breaks belong to one Markdown paragraph; blank lines separate paragraphs. Only the lines around the caret
    /// are read, so this costs the same in a short story and a whole novel.
    public static func range(in text: String, caret: Int) -> NSRange {
        let source = text as NSString
        let position = min(max(0, caret), source.length)
        guard source.length > 0 else { return NSRange(location: 0, length: 0) }
        if position == source.length, text.hasSuffix("\n") { return NSRange(location: position, length: 0) }
        func line(at index: Int) -> NSRange { source.lineRange(for: NSRange(location: index, length: 0)) }
        func blank(_ line: NSRange) -> Bool { source.substring(with: line).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        // At the very end, the caret belongs to the last line.
        let current = line(at: position == source.length ? position - 1 : position)
        if blank(current) { return current }
        var first = current, last = current
        while first.location > 0 {
            let previous = line(at: first.location - 1)
            if blank(previous) { break }
            first = previous
        }
        while NSMaxRange(last) < source.length {
            let next = line(at: NSMaxRange(last))
            if blank(next) { break }
            last = next
        }
        return NSRange(location: first.location, length: NSMaxRange(last) - first.location)
    }
}

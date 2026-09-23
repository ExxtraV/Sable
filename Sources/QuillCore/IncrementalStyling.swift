import Foundation

/// Lines as the styling grammar sees them: split at `\n` only. Every other line break (`\r`, U+2028) stays inside a
/// line, so a range made of these lines never cuts a match that a whole-text search would find.
public enum TextLines {
    /// From the start of the line holding `range.location` to just past the `\n` ending the line holding its end (or
    /// the end of the text).
    public static func lines(in text: NSString, around range: NSRange) -> NSRange {
        let start = lineStart(in: text, at: range.location)
        let end = lineEnd(in: text, at: NSMaxRange(range))
        return NSRange(location: start, length: end - start)
    }

    /// The index just after the last `\n` before `index`, or 0.
    public static func lineStart(in text: NSString, at index: Int) -> Int {
        guard index > 0 else { return 0 }
        let found = text.range(of: "\n", options: [.literal, .backwards], range: NSRange(location: 0, length: min(index, text.length)))
        return found.location == NSNotFound ? 0 : found.location + 1
    }

    /// The index just after the first `\n` at or after `index`, or the end of the text.
    public static func lineEnd(in text: NSString, at index: Int) -> Int {
        guard index < text.length else { return text.length }
        let found = text.range(of: "\n", options: .literal, range: NSRange(location: index, length: text.length - index))
        return found.location == NSNotFound ? text.length : found.location + 1
    }
}

/// Where the text changed since it was last styled, kept up to date from the text storage's edit notifications: the
/// characters before `prefix` and the last `suffix` characters are exactly as they were.
public struct EditTracker: Equatable {
    public private(set) var prefix = Int.max
    public private(set) var suffix = Int.max
    public init() {}
    public var isClean: Bool { prefix == Int.max }
    /// An edit reported by the text storage: `editedRange` holds the new characters, `length` is the text's new length.
    public mutating func record(editedRange: NSRange, length: Int) {
        prefix = min(prefix, editedRange.location)
        suffix = min(suffix, max(0, length - NSMaxRange(editedRange)))
    }
    public mutating func reset() { self = EditTracker() }
}

/// Decides how much of the text an edit forces the editor to restyle, and keeps the ranges it remembers between passes
/// in step with the text. Everything here is about matching a from-scratch restyle exactly; see `MarkdownSyntax` for
/// why a run of whole lines can be styled on its own.
public enum IncrementalStyling {
    public enum Plan: Equatable {
        /// Restyle everything, as for a new document or a setting change.
        case full
        /// Restyle `range` (in the new text); it was `old` in the previous text, and nothing outside it changed.
        case region(range: NSRange, old: NSRange)
    }

    /// What the plan needs to know about the text as it was last styled.
    public struct Previous {
        public var text: NSString
        /// The end of any front-matter block, by the most generous of the definitions the styling passes use (0 if none).
        public var frontMatterEnd: Int
        public init(text: NSString, frontMatterEnd: Int) {
            self.text = text
            self.frontMatterEnd = frontMatterEnd
        }
    }

    /// Only these character sequences begin or end something that spans lines: a code fence, a note, a front-matter block.
    static let fenceTokens = ["```", "~~~"]
    static let noteTokens = ["<!--", "-->"]

    public static func plan(previous: Previous, text: NSString, edit: EditTracker) -> Plan {
        let oldLength = previous.text.length, newLength = text.length
        guard !edit.isClean else { return .full }
        let start = edit.prefix
        let suffix = edit.suffix
        guard start <= oldLength, start <= newLength, suffix <= oldLength - start, suffix <= newLength - start else { return .full }
        let oldChanged = NSRange(location: start, length: oldLength - suffix - start)
        let newChanged = NSRange(location: start, length: newLength - suffix - start)

        // The lines the edit touched, before and after. Their start is the same in both texts.
        let oldLines = TextLines.lines(in: previous.text, around: oldChanged)
        let newLines = TextLines.lines(in: text, around: newChanged)
        func contains(_ source: NSString, _ range: NSRange, _ tokens: [String]) -> Bool {
            tokens.contains { source.range(of: $0, options: .literal, range: range).location != NSNotFound }
        }
        // A fence line's meaning depends on its indentation and what follows the backticks, so any edit on a line holding
        // backticks or tildes can open or close a fence.
        if contains(previous.text, oldLines, fenceTokens) || contains(text, newLines, fenceTokens) { return .full }
        // A note depends only on where its `<!--` and `-->` are, so only an edit that touches one of them matters.
        func near(_ source: NSString, _ changed: NSRange) -> NSRange {
            let from = max(0, changed.location - 3)
            return NSRange(location: from, length: min(source.length, NSMaxRange(changed) + 3) - from)
        }
        if contains(previous.text, near(previous.text, oldChanged), noteTokens) || contains(text, near(text, newChanged), noteTokens) { return .full }
        // Front matter is the first `---` block of the file: an edit inside it, or one that adds or removes a `---` line
        // while the file starts with `---`, can move where it ends.
        if previous.text.hasPrefix("---") || text.hasPrefix("---") {
            if start <= previous.frontMatterEnd || contains(previous.text, oldLines, ["---"]) || contains(text, newLines, ["---"]) { return .full }
        }

        // One more line on each side, so a line's neighbors are always seen together with it.
        let before = TextLines.lineStart(in: text, at: max(0, newLines.location - 1))
        let after = TextLines.lineEnd(in: text, at: NSMaxRange(newLines))
        let range = NSRange(location: before, length: after - before)
        if range.length == newLength { return .full }
        return .region(range: range, old: NSRange(location: range.location, length: range.length - (newLength - oldLength)))
    }

    /// Moves a range remembered from the previous text (a code fence, a note) to where it is now. A range holding the
    /// edit grows or shrinks with it, and one that ran to the end of the text still does. Only valid when `plan` chose a
    /// region, which means the edit didn't touch anything that starts or ends such a range.
    public static func shift(_ range: NSRange, editStart: Int, oldEditEnd: Int, delta: Int, oldLength: Int) -> NSRange {
        let end = NSMaxRange(range)
        if end < editStart || (end == editStart && end < oldLength) { return range }
        if range.location >= oldEditEnd { return NSRange(location: range.location + delta, length: range.length) }
        return NSRange(location: range.location, length: range.length + delta)
    }

    public static func shift(_ spans: [MarkdownSpan], editStart: Int, oldEditEnd: Int, delta: Int, oldLength: Int) -> [MarkdownSpan] {
        spans.map { span in
            let range = shift(span.range, editStart: editStart, oldEditEnd: oldEditEnd, delta: delta, oldLength: oldLength)
            return MarkdownSpan(kind: span.kind, range: range, content: range, markers: [], closing: nil, destination: nil)
        }
    }

    /// Replaces the items of a location-ordered list that fell inside `old` with `replacement` (found in the new text's
    /// region), and moves the items after it by `delta`. Items never cross a line break, so none straddles `old`.
    public static func splice<Item>(_ items: [Item], old: NSRange, delta: Int, replacement: [Item],
                                    range: (Item) -> NSRange, moved: (Item, Int) -> Item) -> [Item] {
        var result = items.filter { NSMaxRange(range($0)) <= old.location }
        result.append(contentsOf: replacement)
        for item in items where range(item).location >= NSMaxRange(old) && NSMaxRange(range(item)) > old.location {
            result.append(moved(item, delta))
        }
        return result
    }
}

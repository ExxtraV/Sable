import Foundation

/// A change to make to the text: replace `range` with `replacement`, then select `selection` (in the new text).
public struct TextEdit: Equatable {
    public var range: NSRange
    public var replacement: String
    public var selection: NSRange
    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }
}

/// The editing rules behind lists, quotes, headings, and links, kept free of any view so they can be tested on their own.
/// Every function looks at the text and the selection and answers with one `TextEdit`, or nil when the ordinary key
/// behavior should apply.
public enum MarkdownEditing {
    public enum LineKind { case bullet, numbered, quote, task }

    // MARK: Line prefixes

    struct Prefix {
        var indentWidth: Int { indent.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } }
        enum Marker { case bullet(String), number(Int, String), quote }
        var indent: String
        var marker: Marker
        var task: String?          // "[ ]" or "[x]"
        var length: Int            // UTF-16 length of everything up to the content
        var markerLength: Int      // …and up to the task box, if there is one
        var isList: Bool { if case .quote = marker { return false }; return true }
    }

    private static let prefixExpression = try! NSRegularExpression(pattern: "^([ \\t]*)(?:((?:>[ \\t]?)+)|([-+*]|[0-9]{1,3}[.)])[ \\t]+(\\[[ xX]\\][ \\t]+)?)")

    static func isRule(_ line: String) -> Bool { MarkdownLines.isSceneBreak(line) }

    static func prefix(of line: String) -> Prefix? {
        guard !isRule(line) else { return nil }
        let ns = line as NSString
        guard let match = prefixExpression.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else { return nil }
        let indent = ns.substring(with: match.range(at: 1))
        if match.range(at: 2).location != NSNotFound {
            return Prefix(indent: indent, marker: .quote, task: nil, length: match.range.length, markerLength: match.range.length)
        }
        let token = ns.substring(with: match.range(at: 3))
        var task: String?
        var markerLength = match.range.length
        if match.range(at: 4).location != NSNotFound {
            task = String(ns.substring(with: match.range(at: 4)).prefix(3))
            markerLength = match.range(at: 4).location - match.range.location
        }
        if let last = token.last, last == "." || last == ")", let number = Int(token.dropLast()) {
            return Prefix(indent: indent, marker: .number(number, String(last)), task: task, length: match.range.length, markerLength: markerLength)
        }
        return Prefix(indent: indent, marker: .bullet(token), task: task, length: match.range.length, markerLength: markerLength)
    }

    /// Start, end (without the line break), and full end of the line holding `location`.
    private static func lineBounds(_ ns: NSString, _ location: Int) -> (start: Int, contentEnd: Int, end: Int) {
        var start = 0, end = 0, contentEnd = 0
        ns.getLineStart(&start, end: &end, contentsEnd: &contentEnd, for: NSRange(location: min(location, ns.length), length: 0))
        return (start, contentEnd, end)
    }

    // MARK: Return

    /// Return inside a list or quote continues it; Return on an empty item ends it (or moves it out one level).
    public static func newline(in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        guard NSMaxRange(selection) <= ns.length else { return nil }
        let bounds = lineBounds(ns, selection.location)
        let line = ns.substring(with: NSRange(location: bounds.start, length: bounds.contentEnd - bounds.start))
        guard let prefix = prefix(of: line) else { return nil }
        let caretInLine = selection.location - bounds.start
        guard caretInLine >= prefix.length, NSMaxRange(selection) <= bounds.contentEnd else { return nil }
        let content = (line as NSString).substring(from: prefix.length)
        let lineRange = NSRange(location: bounds.start, length: bounds.contentEnd - bounds.start)
        let atEnd = selection.location == bounds.contentEnd && selection.length == 0

        if content.trimmingCharacters(in: .whitespaces).isEmpty && atEnd {
            // An empty item: step out of the list, one level at a time.
            if !prefix.indent.isEmpty, prefix.isList {
                let reduced = String(prefix.indent.dropFirst(min(prefix.indent.count, unit(for: prefix))))
                let rebuilt = reduced + String(line.dropFirst(prefix.indent.count).prefix(prefix.length - prefix.indent.count))
                return TextEdit(range: lineRange, replacement: rebuilt, selection: NSRange(location: bounds.start + (rebuilt as NSString).length, length: 0))
            }
            return TextEdit(range: lineRange, replacement: "", selection: NSRange(location: bounds.start, length: 0))
        }
        // Return at the very front of an item's words just pushes them down the way it always has.
        if caretInLine == prefix.length && !content.isEmpty { return nil }

        var next = prefix.indent
        switch prefix.marker {
        case .quote:
            let quoted = (line as NSString).substring(with: NSRange(location: prefix.indent.count, length: prefix.length - prefix.indent.count))
            next += quoted.hasSuffix(" ") || quoted.hasSuffix("\t") ? quoted : quoted + " "
        case let .bullet(token): next += token + " "
        case let .number(number, delimiter): next += "\(number + 1)\(delimiter) "
        }
        if prefix.task != nil { next += "[ ] " }
        let replacement = "\n" + next
        return TextEdit(range: selection, replacement: replacement,
                        selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0))
    }

    private static func unit(for prefix: Prefix) -> Int {
        if case .number = prefix.marker { return 3 }
        return 2
    }

    // MARK: Tab

    private static func coveredLines(_ ns: NSString, _ selection: NSRange) -> NSRange {
        let start = lineBounds(ns, selection.location).start
        var endLocation = NSMaxRange(selection)
        if selection.length > 0, endLocation > start, endLocation <= ns.length, ns.character(at: endLocation - 1) == 10 { endLocation -= 1 }
        let end = lineBounds(ns, endLocation).end
        return NSRange(location: start, length: end - start)
    }

    /// Tab and Shift-Tab move list items in and out. Anywhere else nil, so Tab keeps its usual job.
    public static func indent(in text: String, selection: NSRange, outdent: Bool) -> TextEdit? {
        let ns = text as NSString
        guard NSMaxRange(selection) <= ns.length else { return nil }
        let covered = coveredLines(ns, selection)
        var lines = ns.substring(with: covered).components(separatedBy: "\n")
        let trailingBreak = lines.last == ""
        if trailingBreak { lines.removeLast() }
        let items = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !items.isEmpty, items.allSatisfy({ prefix(of: $0)?.isList == true }) else { return nil }
        var changed = false
        var caretShift = 0
        let caretLine = ns.substring(with: NSRange(location: lineBounds(ns, selection.location).start, length: lineBounds(ns, selection.location).contentEnd - lineBounds(ns, selection.location).start))
        var rebuilt: [String] = []
        for line in lines {
            guard let p = prefix(of: line) else { rebuilt.append(line); continue }
            var updated = line
            if outdent {
                if line.hasPrefix("\t") { updated = String(line.dropFirst()) }
                else {
                    let spaces = line.prefix { $0 == " " }.count
                    updated = String(line.dropFirst(min(spaces, unit(for: p))))
                }
            } else {
                updated = String(repeating: " ", count: unit(for: p)) + line
            }
            let delta = (updated as NSString).length - (line as NSString).length
            if delta != 0 { changed = true }
            if line == caretLine && caretShift == 0 { caretShift = delta }
            rebuilt.append(updated)
        }
        guard changed else { return nil }
        let replacement = rebuilt.joined(separator: "\n") + (trailingBreak ? "\n" : "")
        let newSelection: NSRange
        if selection.length == 0 {
            newSelection = NSRange(location: max(covered.location, selection.location + caretShift), length: 0)
        } else {
            let length = (replacement as NSString).length - (trailingBreak ? 1 : 0)
            newSelection = NSRange(location: covered.location, length: length)
        }
        return TextEdit(range: covered, replacement: replacement, selection: newSelection)
    }

    // MARK: Line formats

    /// Turns every selected line into a bullet, number, quote, or task, or takes that format away when they all have it.
    public static func toggleLine(_ kind: LineKind, in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let covered = coveredLines(ns, NSRange(location: min(selection.location, ns.length), length: min(selection.length, ns.length - min(selection.location, ns.length))))
        var lines = ns.substring(with: covered).components(separatedBy: "\n")
        let trailingBreak = lines.count > 1 && lines.last == ""
        if trailingBreak { lines.removeLast() }
        let only = lines.count == 1
        func has(_ line: String) -> Bool {
            guard let p = prefix(of: line) else { return false }
            switch (kind, p.marker) {
            case (.bullet, .bullet): return p.task == nil
            case (.task, .bullet): return p.task != nil
            case (.numbered, .number): return true
            case (.quote, .quote): return true
            default: return false
            }
        }
        let targets = lines.indices.filter { only || !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty }
        let removing = !targets.isEmpty && targets.allSatisfy { has(lines[$0]) }
        var number = 1
        var rebuilt: [String] = []
        for (index, line) in lines.enumerated() {
            guard targets.contains(index) else { rebuilt.append(line); continue }
            var indent = "", body = line
            if let p = prefix(of: line) {
                indent = p.indent
                body = (line as NSString).substring(from: p.length)
            } else {
                indent = String(line.prefix { $0 == " " || $0 == "\t" })
                body = String(line.dropFirst(indent.count))
            }
            if removing { rebuilt.append(indent + body); continue }
            let marker: String
            switch kind {
            case .bullet: marker = "- "
            case .task: marker = "- [ ] "
            case .quote: marker = "> "
            case .numbered: marker = "\(number). "; number += 1
            }
            rebuilt.append(indent + marker + body)
        }
        let replacement = rebuilt.joined(separator: "\n") + (trailingBreak ? "\n" : "")
        let newSelection: NSRange
        if selection.length == 0 {
            // Keep the caret in the same place relative to its words: shift it by every change up to and including its line.
            var index = 0, offset = covered.location
            for (i, line) in lines.enumerated() {
                let length = (line as NSString).length
                if selection.location <= offset + length { index = i; break }
                offset += length + 1
                index = i
            }
            let shift = shiftBefore(lines: lines, rebuilt: rebuilt, upTo: index + 1)
            newSelection = NSRange(location: max(covered.location, selection.location + shift), length: 0)
        } else {
            newSelection = NSRange(location: covered.location, length: (replacement as NSString).length - (trailingBreak ? 1 : 0))
        }
        return TextEdit(range: covered, replacement: replacement, selection: newSelection)
    }

    private static func shiftBefore(lines: [String], rebuilt: [String], upTo index: Int) -> Int {
        var shift = 0
        for i in 0..<index { shift += (rebuilt[i] as NSString).length - (lines[i] as NSString).length }
        return shift
    }

    /// Cycles the line's heading: none, #, ##, ###, none.
    public static func cycleHeading(in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let bounds = lineBounds(ns, selection.location)
        let line = ns.substring(with: NSRange(location: bounds.start, length: bounds.contentEnd - bounds.start))
        var level = 0
        var rest = line
        if let match = line.range(of: "^#{1,6}[ \\t]+", options: .regularExpression) {
            level = line[match].prefix { $0 == "#" }.count
            rest = String(line[match.upperBound...])
        }
        let next = level >= 1 && level < 3 ? level + 1 : (level == 0 ? 1 : 0)
        let updated = (next == 0 ? "" : String(repeating: "#", count: next) + " ") + rest
        let delta = (updated as NSString).length - (line as NSString).length
        let caret = max(bounds.start, selection.location + delta)
        return TextEdit(range: NSRange(location: bounds.start, length: bounds.contentEnd - bounds.start), replacement: updated,
                        selection: NSRange(location: min(caret, bounds.start + (updated as NSString).length), length: 0))
    }

    /// A scene break on its own paragraph.
    public static func horizontalRule(in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let bounds = lineBounds(ns, selection.location)
        let beforeOnLine = ns.substring(with: NSRange(location: bounds.start, length: selection.location - bounds.start))
        var lead = ""
        if !beforeOnLine.trimmingCharacters(in: .whitespaces).isEmpty { lead = "\n\n" }
        else if bounds.start > 0 {
            // At the start of a line: one break is enough if the line above has words, none if it is already blank.
            let above = lineBounds(ns, bounds.start - 1)
            let aboveText = ns.substring(with: NSRange(location: above.start, length: above.contentEnd - above.start))
            if !aboveText.trimmingCharacters(in: .whitespaces).isEmpty { lead = "\n" }
        }
        let replacement = lead + "* * *\n\n"
        return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: selection.location + (replacement as NSString).length, length: 0))
    }

    /// A link around the selection. If a web address is on the clipboard it becomes the destination.
    public static func link(in text: String, selection: NSRange, clipboard: String?) -> TextEdit {
        let ns = text as NSString
        let selected = ns.substring(with: selection)
        if let address = clipboard?.trimmingCharacters(in: .whitespacesAndNewlines), isAddress(address) {
            let replacement = "[" + selected + "](" + address + ")"
            let caret = selected.isEmpty ? selection.location + 1 : selection.location + (replacement as NSString).length
            return TextEdit(range: selection, replacement: replacement, selection: NSRange(location: caret, length: 0))
        }
        return TextEdit(range: selection, replacement: "[" + selected + "](url)",
                        selection: NSRange(location: selection.location + selection.length + 3, length: 3))
    }

    public static func isAddress(_ value: String) -> Bool {
        guard !value.contains(where: { $0.isWhitespace }) else { return false }
        let lower = value.lowercased()
        return lower.hasPrefix("http://") || lower.hasPrefix("https://") || lower.hasPrefix("mailto:")
    }
}

/// Curly quotes, em dashes, and ellipses as you type, never inside code, links, or the metadata block at the top.
public enum SmartTypography {
    public struct Change: Equatable {
        public let deleteCount: Int
        public let insert: String
    }

    /// The change to make when `typed` is entered at `location`, or nil to type it as it is.
    public static func change(typing typed: String, in text: String, at location: Int) -> Change? {
        guard typed == "\"" || typed == "'" || typed == "-" || typed == "." else { return nil }
        let ns = text as NSString
        guard location <= ns.length, !isProtected(ns, location) else { return nil }
        func character(_ offset: Int) -> Character? {
            let index = location - offset
            guard index >= 0, index < ns.length else { return nil }
            return Character(ns.substring(with: NSRange(location: index, length: 1)))
        }
        let previous = character(1)
        switch typed {
        case "\"", "'":
            let opening: Bool
            if let previous { opening = previous.isWhitespace || "([{<—–-‘“/".contains(previous) } else { opening = true }
            if typed == "\"" { return Change(deleteCount: 0, insert: opening ? "“" : "”") }
            return Change(deleteCount: 0, insert: opening ? "‘" : "’")
        case "-":
            guard previous == "-", let before = character(2), before != "-", !before.isNewline else { return nil }
            return Change(deleteCount: 1, insert: "—")
        default:
            guard previous == ".", character(2) == ".", character(3) != "." else { return nil }
            return Change(deleteCount: 2, insert: "…")
        }
    }

    private static func isProtected(_ ns: NSString, _ location: Int) -> Bool {
        let head = ns.substring(to: location)
        // The front matter block.
        if head.hasPrefix("---\n") || head == "---" {
            let after = ns.substring(from: 0)
            let closing = (after as NSString).range(of: "\n---", options: [], range: NSRange(location: 3, length: max(0, ns.length - 3)))
            if closing.location == NSNotFound || location <= closing.location + 4 { return true }
        }
        // Inside a fenced block: an odd number of fence lines before here.
        let fences = (try? NSRegularExpression(pattern: "(?m)^ {0,3}(?:```|~~~)").numberOfMatches(in: head, range: NSRange(location: 0, length: (head as NSString).length))) ?? 0
        if fences % 2 == 1 { return true }
        // Inside inline code, or a link's address.
        let lineStart = (head as NSString).range(of: "\n", options: .backwards).location
        let line = lineStart == NSNotFound ? head : (head as NSString).substring(from: lineStart + 1)
        if line.filter({ $0 == "`" }).count % 2 == 1 { return true }
        if let open = line.range(of: "](", options: .backwards), !line[open.upperBound...].contains(")") { return true }
        return false
    }
}

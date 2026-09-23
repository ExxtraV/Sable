import Foundation
import NaturalLanguage

// The editor restyles only the lines around an edit. That is only right if every range-limited pass finds exactly what the
// whole-text pass finds there, and if nothing outside the region can change. This check compares the range-limited
// functions against verbatim copies of the whole-text code they replaced, on thousands of random Markdown documents and
// random edits built to hit every construct that crosses a line: fences, notes, front matter, `\r` and U+2028.
//
// QUILL_RANGE_SEED and QUILL_RANGE_DOCUMENTS override the seed and the number of documents.

@main enum StylingRangeChecks {
    static func main() {
        let environment = ProcessInfo.processInfo.environment
        let seed = environment["QUILL_RANGE_SEED"].flatMap { UInt64($0) } ?? 0x5EED
        let documents = environment["QUILL_RANGE_DOCUMENTS"].flatMap { Int($0) } ?? 400
        let started = Date()
        fixedCases()
        var rng = Random(seed: seed)
        var regions = 0, fulls = 0
        for index in 0..<documents {
            let text = Soup.document(&rng)
            wholeText(text, rng: &rng, tagging: index % 8 == 0)
            for _ in 0..<12 {
                let edited = Soup.edit(text, &rng)
                if edit(from: text, to: edited.text, change: edited.change, tagging: index % 8 == 0) { regions += 1 } else { fulls += 1 }
            }
        }
        print("Passed: range-limited spans, prose review, sentence colors, outline, formatting exit, focus paragraph, and region planning match whole-text passes (\(documents) documents from seed \(seed), \(regions) region and \(fulls) full plans) in \(String(format: "%.1f", Date().timeIntervalSince(started)))s.")
    }

    // MARK: Whole text, then any run of whole lines

    static func wholeText(_ text: String, rng: inout Random, tagging: Bool) {
        let source = text as NSString
        let full = Reference.spans(in: text)
        expect(describe(MarkdownSyntax.spans(in: text)) == describe(full), "spans(in:) is unchanged", text)
        expect(MarkdownSyntax.headings(in: text).map { "\($0.level) \($0.title) \($0.range)" } == Reference.headings(in: text).map { "\($0.level) \($0.title) \($0.range)" }, "the outline is unchanged", text)
        expect(Prose.suggestions(in: text, words: words) == Reference.suggestions(in: text, words: words), "prose review is unchanged", text)
        if tagging {
            let all = WordClass.allCases.reduce(0) { $0 | $1.rawValue }
            expect(describe(SentenceStructure.words(in: text, enabled: all)) == describe(Reference.words(in: text, enabled: all)), "sentence colors are unchanged", text)
        }
        for _ in 0..<8 {
            let caret = rng.int(0...source.length)
            expect(FocusParagraph.range(in: text, caret: caret) == Reference.focus(in: text, caret: caret), "focus paragraph at \(caret)", text)
            let length = rng.chance(0.5) ? 0 : rng.int(0...(source.length - caret))
            let selection = NSRange(location: caret, length: length)
            expect(MarkdownSyntax.exitOffset(in: text, selection: selection) == Reference.exitOffset(in: text, selection: selection), "formatting exit at \(selection)", text)
        }
        let blocks = MarkdownSyntax.blocks(in: text), proseBlocks = Prose.protectedBlocks(in: text)
        for _ in 0..<6 {
            let a = rng.int(0...source.length), b = rng.int(0...source.length)
            let range = TextLines.lines(in: source, around: NSRange(location: min(a, b), length: abs(a - b)))
            let expected = full.compactMap { span -> MarkdownSpan? in
                let part = NSIntersectionRange(span.range, range)
                guard part.length > 0 else { return nil }
                return blocks.contains { $0.range == span.range } ? MarkdownSpan(kind: span.kind, range: part, content: part, markers: [], closing: nil, destination: nil) : span
            }
            let local = MarkdownSyntax.spans(in: text, range: range, blocks: blocks)
            expect(describe(local) == describe(expected), "spans in \(range) match the whole-text spans there", text)
            expect(Prose.suggestions(in: text, words: words, range: range, blocks: proseBlocks) == Reference.suggestions(in: text, words: words).filter { NSIntersectionRange($0, range).length > 0 },
                   "prose review in \(range)", text)
            if tagging {
                let all = WordClass.allCases.reduce(0) { $0 | $1.rawValue }
                let whole = Reference.words(in: text, enabled: all).filter { NSIntersectionRange($0.range, range).length > 0 }
                expect(describe(SentenceStructure.words(in: text, enabled: all, range: range, spans: local)) == describe(whole), "sentence colors in \(range)", text)
            }
        }
    }

    // MARK: Edits

    /// Plans an edit the way the editor does and, when it picks a region, proves that everything outside the region is the
    /// same as before (moved by the edit) and that the remembered multi-line ranges moved correctly. Returns true for a region.
    static func edit(from old: String, to new: String, change: (location: Int, oldLength: Int, newLength: Int), tagging: Bool) -> Bool {
        let oldSource = old as NSString, newSource = new as NSString
        var tracker = EditTracker()
        tracker.record(editedRange: NSRange(location: change.location, length: change.newLength), length: newSource.length)
        precondition(tracker.prefix == change.location && tracker.suffix == oldSource.length - change.location - change.oldLength)
        let previous = IncrementalStyling.Previous(text: oldSource, frontMatterEnd: frontMatterEnd(old))
        guard case let .region(range, oldRange) = IncrementalStyling.plan(previous: previous, text: newSource, edit: tracker) else { return false }
        let context = "edit at \(change.location) replacing \(change.oldLength) with \(change.newLength), region \(range) (was \(oldRange))"
        let delta = newSource.length - oldSource.length
        expect(oldRange.location == range.location && NSMaxRange(oldRange) + delta == NSMaxRange(range), "the region lines up in both texts; \(context)", new)
        expect(range.location <= change.location && change.location + change.newLength <= NSMaxRange(range), "the region holds the edit; \(context)", new)
        expect(oldSource.substring(to: range.location) == newSource.substring(to: range.location)
               && oldSource.substring(from: NSMaxRange(oldRange)) == newSource.substring(from: NSMaxRange(range)), "nothing outside the region changed; \(context)", new)
        func shifted(_ ranges: [NSRange]) -> [NSRange] {
            ranges.map { IncrementalStyling.shift($0, editStart: change.location, oldEditEnd: change.location + change.oldLength, delta: delta, oldLength: oldSource.length) }
        }
        expect(shifted(MarkdownSyntax.blocks(in: old).map(\.range)) == MarkdownSyntax.blocks(in: new).map(\.range), "fences and notes moved with the edit; \(context)", new)
        expect(shifted(Prose.protectedBlocks(in: old)) == Prose.protectedBlocks(in: new), "prose review's protected blocks moved with the edit; \(context)", new)
        expect(frontMatterEnd(old) == frontMatterEnd(new) || frontMatterEnd(old) == 0 && frontMatterEnd(new) == 0, "front matter is unchanged; \(context)", new)
        // Outside the region, every span is the old one, moved.
        func outside(_ spans: [MarkdownSpan], _ region: NSRange, move: Int) -> [String] {
            spans.filter { NSIntersectionRange($0.range, region).length == 0 && !($0.range.length == 0 && NSLocationInRange($0.range.location, region)) }
                .map { span in
                    let by = span.range.location >= NSMaxRange(region) ? move : 0
                    return describe([span], offset: by).joined()
                }
        }
        let oldBlocks = Set(MarkdownSyntax.blocks(in: old).map(\.range)), newBlocks = Set(MarkdownSyntax.blocks(in: new).map(\.range))
        expect(outside(Reference.spans(in: old).filter { !oldBlocks.contains($0.range) }, oldRange, move: delta)
               == outside(Reference.spans(in: new).filter { !newBlocks.contains($0.range) }, range, move: 0), "spans outside the region are unchanged; \(context)", new)
        func outsideRanges(_ ranges: [NSRange], _ region: NSRange, move: Int) -> [NSRange] {
            ranges.filter { NSIntersectionRange($0, region).length == 0 }.map { $0.location >= NSMaxRange(region) ? NSRange(location: $0.location + move, length: $0.length) : $0 }
        }
        let oldSuggestions = Reference.suggestions(in: old, words: words), newSuggestions = Reference.suggestions(in: new, words: words)
        expect(outsideRanges(oldSuggestions, oldRange, move: delta) == outsideRanges(newSuggestions, range, move: 0), "suggestions outside the region are unchanged; \(context)", new)
        let spliced = IncrementalStyling.splice(oldSuggestions, old: oldRange, delta: delta,
                                                replacement: Prose.suggestions(in: new, words: words, range: range, blocks: Prose.protectedBlocks(in: new)),
                                                range: { $0 }, moved: { NSRange(location: $0.location + $1, length: $0.length) })
        expect(spliced == newSuggestions, "splicing the region's suggestions into the old list gives the new list; \(context)", new)
        expect(Prose.wordCount(old) - Prose.wordCount(oldSource.substring(with: oldRange)) + Prose.wordCount(newSource.substring(with: range)) == Prose.wordCount(new),
               "word counts add up across the region; \(context)", new)
        if tagging {
            let all = WordClass.allCases.reduce(0) { $0 | $1.rawValue }
            func outsideWords(_ words: [TaggedWord], _ region: NSRange, move: Int) -> [String] {
                describe(words.filter { NSIntersectionRange($0.range, region).length == 0 }
                    .map { TaggedWord(range: $0.range.location >= NSMaxRange(region) ? NSRange(location: $0.range.location + move, length: $0.range.length) : $0.range, kind: $0.kind) })
            }
            expect(outsideWords(Reference.words(in: old, enabled: all), oldRange, move: delta) == outsideWords(Reference.words(in: new, enabled: all), range, move: 0),
                   "sentence colors outside the region are unchanged; \(context)", new)
        }
        return true
    }

    static func frontMatterEnd(_ text: String) -> Int {
        let ns = text as NSString
        var nameEnd = 0
        if ns.hasPrefix("---\n") {
            let close = ns.range(of: "\n---", options: [], range: NSRange(location: 4, length: ns.length - 4))
            if close.location != NSNotFound { nameEnd = NSMaxRange(close) }
        }
        return max(NSMaxRange(MarkdownLines.frontMatterRange(in: text)), Prose.frontMatterEnd(in: text), nameEnd)
    }

    // MARK: Known cases

    static func fixedCases() {
        func plan(_ old: String, _ at: Int, delete: Int = 0, insert: String) -> IncrementalStyling.Plan {
            let new = (old as NSString).replacingCharacters(in: NSRange(location: at, length: delete), with: insert)
            var tracker = EditTracker()
            tracker.record(editedRange: NSRange(location: at, length: (insert as NSString).length), length: (new as NSString).length)
            return IncrementalStyling.plan(previous: .init(text: old as NSString, frontMatterEnd: frontMatterEnd(old)), text: new as NSString, edit: tracker)
        }
        func isRegion(_ plan: IncrementalStyling.Plan) -> Bool { if case .region = plan { return true }; return false }
        let story = "# One\n\nShe crossed the pier.\n\nThe bell rang twice.\n\nNobody answered.\n"
        guard case let .region(range, _) = plan(story, 30, insert: "x") else { preconditionFailure("Typing in prose restyles a region") }
        precondition((story as NSString).substring(with: range) == "\nThe bxell rang twice.\n\n" || range.length < (story as NSString).length, "The region is the paragraph and its neighbors")
        precondition(!isRegion(plan(story, 7, insert: "```\n")), "Opening a fence restyles everything")
        precondition(!isRegion(plan("Text\n``\nmore\n", 5, insert: "`")), "Completing a fence's backticks restyles everything")
        precondition(!isRegion(plan("A\n```\ncode\n```\nB\n", 2, delete: 4, insert: "")), "Removing a fence line restyles everything")
        precondition(!isRegion(plan("Note <!- here\n\nlater\n", 7, insert: "-")), "Completing <!-- restyles everything")
        precondition(isRegion(plan("Note <!-- a --> and then a long sentence of prose.\n\nlater\n", 40, insert: "x")), "Typing well away from a note on its line is local")
        precondition(isRegion(plan("<!-- a long note\nthat is still open\n\nmore\n\nand more\n", 38, insert: "x")), "Typing inside an unclosed note is local")
        let front = "---\ntitle: A\n---\n\nStory text here.\n\nMore.\n"
        precondition(!isRegion(plan(front, 6, insert: "x")), "Editing front matter restyles everything")
        precondition(isRegion(plan(front, 25, insert: "x")), "Typing after front matter is local")
        precondition(!isRegion(plan("---\ntitle: A\n\nStory\n\nMore\n", 20, insert: "---\n")), "A line that could close front matter restyles everything")
        precondition(!isRegion(plan("x", 1, insert: "y")), "A region as long as the text is a full pass")
        // Tracking several edits keeps only characters that no edit touched outside [prefix, length - suffix).
        var rng = Random(seed: 7)
        for _ in 0..<500 {
            let original = Soup.document(&rng) as NSString
            let text = NSMutableString(string: original)
            var tracker = EditTracker()
            for _ in 0..<rng.int(1...4) {
                let at = rng.int(0...text.length), length = rng.int(0...min(20, text.length - at))
                let insert = rng.chance(0.3) ? "" : Soup.piece(&rng)
                text.replaceCharacters(in: NSRange(location: at, length: length), with: insert)
                tracker.record(editedRange: NSRange(location: at, length: (insert as NSString).length), length: text.length)
            }
            let prefix = min(tracker.prefix, text.length), suffix = min(tracker.suffix, text.length - prefix)
            precondition(original.length >= prefix + suffix && original.substring(to: prefix) == text.substring(to: prefix)
                         && original.substring(from: original.length - suffix) == text.substring(from: text.length - suffix), "Edit tracking never claims a changed character is unchanged")
        }
    }

    // MARK: Helpers

    static let words = Prose.defaultWords + ", in order to"

    static func describe(_ spans: [MarkdownSpan], offset: Int = 0) -> [String] {
        func r(_ range: NSRange) -> String { "\(range.location + offset),\(range.length)" }
        return spans.map { "\($0.kind) \(r($0.range)) \(r($0.content)) \($0.markers.map(r)) \($0.closing.map(r) ?? "-") \($0.destination.map(r) ?? "-")" }
    }
    static func describe(_ words: [TaggedWord]) -> [String] { words.map { "\($0.range) \($0.kind)" } }

    static func expect(_ condition: Bool, _ message: String, _ text: String) {
        guard !condition else { return }
        let file = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("quill-range-failure.md")
        try? text.write(to: file, atomically: true, encoding: .utf8)
        print("FAILED: \(message)\nThe text is in \(file.path): \(text.debugDescription.prefix(400))")
        exit(1)
    }
}

// MARK: - Random Markdown

struct Random {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
    mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
    mutating func chance(_ p: Double) -> Bool { Double(next() >> 11) / Double(1 << 53) < p }
    mutating func pick<T>(_ items: [T]) -> T { items[int(0...(items.count - 1))] }
}

enum Soup {
    static let words = ["the", "tide", "very", "just", "Really", "lantern", "Marren", "walked", "quietly", "in", "order", "to", "bell", "🌙", "café", "e\u{301}"]
    static let marks = ["*", "**", "***", "_", "__", "~~", "`", "``", "```", "~~~", "<!--", "-->", "<!-- note -->", "[", "]", "(", ")",
                        "[link](https://example.com)", "![alt](a.png)", "[^1]", "[^1]:", "\\*", "https://x.io/a", "|", "#", "---", "\r", "\u{2028}", "  "]
    static let starts = ["", "", "", "", "# ", "## ", "> ", "- ", "* ", "1. ", "- [ ] ", "- [x] ", "   ", "    ", "```", "```md", "~~~", "---", "***",
                         "* * *", "| a | b |", "|---|---|", "<!--", "-->", "===", "\t"]

    static func piece(_ rng: inout Random) -> String {
        rng.chance(0.7) ? rng.pick(words) + (rng.chance(0.8) ? " " : "") : rng.pick(marks)
    }

    static func line(_ rng: inout Random) -> String {
        var line = rng.pick(starts)
        if line == "```" || line == "~~~" || line == "---" || line == "***" || line == "* * *" || line == "===" { return line }
        for _ in 0..<rng.int(0...12) { line += piece(&rng) }
        return line
    }

    static func document(_ rng: inout Random) -> String {
        var lines: [String] = []
        if rng.chance(0.2) { lines += ["---", "title: \(rng.pick(words))", rng.chance(0.8) ? "---" : "tags: x"] }
        for _ in 0..<rng.int(4...40) {
            lines.append(rng.chance(0.3) ? "" : line(&rng))
        }
        return lines.joined(separator: "\n") + (rng.chance(0.7) ? "\n" : "")
    }

    /// A random edit, mostly small and near where writing happens, sometimes structural.
    static func edit(_ text: String, _ rng: inout Random) -> (text: String, change: (location: Int, oldLength: Int, newLength: Int)) {
        let source = text as NSString
        let at = rng.int(0...source.length)
        let length = rng.chance(0.6) ? 0 : rng.int(0...min(rng.chance(0.8) ? 3 : 40, source.length - at))
        var insert = ""
        if rng.chance(0.85) {
            insert = rng.chance(0.5) ? String(rng.pick(Array("abcxyz *_`~-<>!#\n"))) : piece(&rng)
            if rng.chance(0.1) { insert += "\n" + line(&rng) }
        }
        // Don't split a surrogate pair or a CRLF: the text system never edits inside one.
        let range = source.rangeOfComposedCharacterSequences(for: NSRange(location: at, length: length))
        let new = source.replacingCharacters(in: range, with: insert)
        return (new, (range.location, range.length, (insert as NSString).length))
    }
}

// MARK: - The whole-text code this replaced, verbatim

enum Reference {
    static func spans(in text: String) -> [MarkdownSpan] {
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


    static func headings(in text: String) -> [ChapterHeading] {
        spans(in: text).compactMap { span in
            guard case let .heading(level) = span.kind else { return nil }
            return ChapterHeading(title: (text as NSString).substring(with: span.content), level: level, range: span.range)
        }
    }

    static func exitOffset(in text: String, selection: NSRange) -> Int? {
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

    static func suggestions(in text: String, words: String) -> [NSRange] {
        let candidates = words.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !candidates.isEmpty else { return [] }
        let source = text as NSString
        let whole = NSRange(location: 0, length: source.length)
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

    static func words(in text: String, enabled: Int) -> [TaggedWord] {
        guard enabled != 0 else { return [] }
        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        let spans = Reference.spans(in: text)
        let excluded = spans.flatMap { span -> [NSRange] in
            if case .code = span.kind { return [span.range] }
            return span.markers
        }
        var result: [TaggedWord] = []
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass, options: [.omitPunctuation, .omitWhitespace]) { tag, range in
            let kind: WordClass?
            switch tag { case .noun: kind = .noun; case .verb: kind = .verb; case .adjective: kind = .adjective; case .adverb: kind = .adverb; case .pronoun: kind = .pronoun; default: kind = nil }
            let nsRange = NSRange(range, in: text)
            if let kind, enabled & kind.rawValue != 0, !excluded.contains(where: { NSIntersectionRange($0, nsRange).length > 0 }) {
                result.append(TaggedWord(range: nsRange, kind: kind))
            }
            return true
        }
        return result
    }

    static func focus(in text: String, caret: Int) -> NSRange {
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

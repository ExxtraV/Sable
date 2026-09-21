import Foundation

@main enum MarkdownEditingChecks {
    static func apply(_ edit: TextEdit?, to text: String) -> (String, NSRange)? {
        guard let edit else { return nil }
        return ((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement), edit.selection)
    }
    /// `|` marks the caret in the input; the result shows it again.
    static func run(_ marked: String, _ operation: (String, NSRange) -> TextEdit?) -> String? {
        let ns = marked as NSString
        let caret = ns.range(of: "|")
        let text = ns.replacingCharacters(in: caret, with: "")
        guard let (result, selection) = apply(operation(text, NSRange(location: caret.location, length: 0)), to: text) else { return nil }
        return (result as NSString).replacingCharacters(in: NSRange(location: selection.location, length: 0), with: "|")
    }

    static func main() {
        // Return continues lists and quotes
        func enter(_ marked: String) -> String? { run(marked) { MarkdownEditing.newline(in: $0, selection: $1) } }
        precondition(enter("- one|") == "- one\n- |", "A bullet continues")
        precondition(enter("* one|") == "* one\n* |")
        precondition(enter("1. one|") == "1. one\n2. |", "A number counts up")
        precondition(enter("9) nine|") == "9) nine\n10) |")
        precondition(enter("  - nested|") == "  - nested\n  - |", "Indent is kept")
        precondition(enter("- [ ] task|") == "- [ ] task\n- [ ] |", "A task continues unchecked")
        precondition(enter("- [x] done|") == "- [x] done\n- [ ] |")
        precondition(enter("> said|") == "> said\n> |", "A quote continues")
        precondition(enter("- one|\n- two") == "- one\n- |\n- two", "Return at the end of the middle item")
        precondition(enter("- one| two") == "- one\n- | two", "Return in the middle splits the item")
        precondition(enter("- |") == "|", "Return on an empty item ends the list")
        precondition(enter("  - |") == "  - |" || enter("  - |") == "- |", "An empty nested item moves out: \(enter("  - |") ?? "nil")")
        precondition(enter("  - |") == "- |", "An empty nested bullet steps out one level: \(enter("  - |") ?? "nil")")
        precondition(enter("> |") == "|", "An empty quote line ends the quote")
        precondition(enter("plain text|") == nil, "Ordinary lines are left to the usual Return")
        precondition(enter("* * *|") == nil && enter("---|") == nil, "A scene break is not a list")
        precondition(enter("**bold** start|") == nil && enter("*italic* start|") == nil, "Emphasis at the start isn't a bullet")
        precondition(enter("1986 was a year|") == nil, "A year without a period isn't a list")
        precondition(enter("- |words") == nil, "Return before the words keeps its usual meaning")

        // Tab
        func tab(_ marked: String, out: Bool = false) -> String? { run(marked) { MarkdownEditing.indent(in: $0, selection: $1, outdent: out) } }
        precondition(tab("- item|") == "  - item|", "Tab indents a bullet")
        precondition(tab("1. item|") == "   1. item|", "Tab indents a number by its width")
        precondition(tab("  - item|", out: true) == "- item|", "Shift-Tab moves it back")
        precondition(tab("- item|", out: true) == nil, "Nothing to outdent")
        precondition(tab("plain|") == nil, "Tab in prose is an ordinary tab")
        precondition(tab("> quote|") == nil, "Tab in a quote is left alone")
        let block = "- a\n- b\n- c"
        let blockEdit = MarkdownEditing.indent(in: block, selection: NSRange(location: 0, length: block.count), outdent: false)
        precondition(blockEdit?.replacement == "  - a\n  - b\n  - c", "Every selected item moves: \(String(describing: blockEdit?.replacement))")

        // Line formats
        func toggle(_ kind: MarkdownEditing.LineKind, _ marked: String) -> String? { run(marked) { MarkdownEditing.toggleLine(kind, in: $0, selection: $1) } }
        precondition(toggle(.bullet, "word|") == "- word|", "Make a bullet: \(toggle(.bullet, "word|") ?? "nil")")
        precondition(toggle(.bullet, "- word|") == "word|", "Toggle it off")
        precondition(toggle(.numbered, "- word|") == "1. word|", "Bullet to number")
        precondition(toggle(.quote, "wo|rd") == "> wo|rd", "Caret keeps its place")
        precondition(toggle(.task, "- word|") == "- [ ] word|", "A bullet becomes a task")
        precondition(toggle(.bullet, "|") == "- |", "An empty line gets a bullet")
        let many = "one\ntwo\n\nthree"
        let numbered = MarkdownEditing.toggleLine(.numbered, in: many, selection: NSRange(location: 0, length: many.count))
        precondition(numbered.replacement == "1. one\n2. two\n\n3. three", "Numbering skips blank lines: \(numbered.replacement)")
        let quoted = MarkdownEditing.toggleLine(.quote, in: "> a\n> b", selection: NSRange(location: 0, length: 7))
        precondition(quoted.replacement == "a\nb", "All quoted lines unquote together")
        func heading(_ marked: String) -> String? { run(marked) { MarkdownEditing.cycleHeading(in: $0, selection: $1) } }
        precondition(heading("Title|") == "# Title|" && heading("# Title|") == "## Title|" && heading("## Title|") == "### Title|" && heading("### Title|") == "Title|", "Heading cycle")
        precondition(heading("#### Deep|") == "Deep|", "A deeper heading is cleared")
        func rule(_ marked: String) -> String? { run(marked) { MarkdownEditing.horizontalRule(in: $0, selection: $1) } }
        precondition(rule("|") == "* * *\n\n|", "A scene break on an empty page: \(rule("|") ?? "nil")")
        precondition(rule("End of scene.|") == "End of scene.\n\n* * *\n\n|", "After words it gets its own paragraph")
        precondition(rule("Text\n|") == "Text\n\n* * *\n\n|", "After a line of text, a blank line first: \(rule("Text\n|") ?? "nil")")
        let linked = MarkdownEditing.link(in: "see here", selection: NSRange(location: 4, length: 4), clipboard: " https://example.com/x ")
        precondition(linked.replacement == "[here](https://example.com/x)" && linked.selection == NSRange(location: 4 + 29, length: 0), "A copied address becomes the link")
        let plain = MarkdownEditing.link(in: "see here", selection: NSRange(location: 4, length: 4), clipboard: "not a link")
        precondition(plain.replacement == "[here](url)" && plain.selection == NSRange(location: 4 + 4 + 3, length: 3), "Otherwise the address is a placeholder")
        precondition(MarkdownEditing.link(in: "", selection: NSRange(location: 0, length: 0), clipboard: "mailto:a@b.co").selection == NSRange(location: 1, length: 0), "An empty label puts the caret inside")

        // Smart typography
        func typed(_ character: String, after text: String) -> String? {
            guard let change = SmartTypography.change(typing: character, in: text, at: (text as NSString).length) else { return nil }
            return (text as NSString).substring(to: (text as NSString).length - change.deleteCount) + change.insert
        }
        precondition(typed("\"", after: "") == "“" && typed("\"", after: "He said ") == "He said “", "An opening quote")
        precondition(typed("\"", after: "He said “Hi") == "He said “Hi”", "A closing quote")
        precondition(typed("\"", after: "(") == "(“" && typed("\"", after: "—") == "—“", "After punctuation that opens")
        precondition(typed("'", after: "don") == "don’" && typed("'", after: "She said ") == "She said ‘", "Apostrophes and single quotes")
        precondition(typed("-", after: "word-") == "word—", "Two hyphens make a dash")
        precondition(typed("-", after: "word") == nil && typed("-", after: "\n-") == nil && typed("-", after: "--") == nil, "A list marker or a rule is left alone")
        precondition(typed(".", after: "wait..") == "wait…" && typed(".", after: "wait.") == nil && typed(".", after: "wait...") == nil, "Ellipsis")
        precondition(typed("\"", after: "`code ") == nil, "Not inside inline code")
        precondition(typed("\"", after: "```\ncode ") == nil && typed("\"", after: "```\ncode\n```\nthen ") == "```\ncode\n```\nthen “", "Not inside a code block, but fine after it")
        precondition(typed("'", after: "---\ntitle: Don") == nil && typed("'", after: "---\ntitle: X\n---\nDon") == "---\ntitle: X\n---\nDon’", "Not in front matter")
        precondition(typed("\"", after: "[label](http://x.co/") == nil, "Not inside a link address")
        precondition(typed("a", after: "x") == nil, "Other characters are untouched")
        print("Passed: list continuation, indenting, line formats, headings, scene breaks, links, smart typography.")
    }
}

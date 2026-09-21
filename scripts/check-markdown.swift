import Foundation

@main enum MarkdownChecks {
    static func main() {
        let document = "# The crossing\n🌙 **bold** and *italic* and ***both***. [Map](https://example.com)\n`**not bold**`\n```md\n# Not a chapter\n```\n## Arrival"
        let spans = MarkdownSyntax.spans(in: document)
        precondition(spans.contains { if case .bold = $0.kind { return (document as NSString).substring(with: $0.content) == "bold" }; return false })
        precondition(spans.contains { if case .italic = $0.kind { return (document as NSString).substring(with: $0.content) == "italic" }; return false })
        precondition(spans.contains { if case .boldItalic = $0.kind { return (document as NSString).substring(with: $0.content) == "both" }; return false })
        precondition(!spans.contains { if case .bold = $0.kind { return (document as NSString).substring(with: $0.content) == "not bold" }; return false })
        precondition(MarkdownSyntax.headings(in: document).map(\.title) == ["The crossing", "Arrival"])
        precondition(MarkdownSyntax.exitOffset(in: "**story**", selection: NSRange(location: 7, length: 0)) == 9)
        precondition(MarkdownSyntax.exitOffset(in: "****", selection: NSRange(location: 2, length: 0)) == 4)
        precondition(MarkdownSyntax.exitOffset(in: "*story*", selection: NSRange(location: 6, length: 0)) == 7)
        precondition(MarkdownSyntax.exitOffset(in: "[Map](url)", selection: NSRange(location: 6, length: 3)) == 10)
        precondition(MarkdownSyntax.exitOffset(in: "plain", selection: NSRange(location: 5, length: 0)) == nil)
        precondition(MarkdownSyntax.exitOffset(in: "**story**", selection: NSRange(location: 4, length: 0)) == nil)
        precondition(MarkdownSyntax.headings(in: "```\n# unfinished code fence").isEmpty)
        // Scene breaks, notes, images, tasks, tables, footnotes, escapes
        let extras = "Text\n\n* * *\n\n---\n\n***\n\n<!-- a **note**\nspans lines -->\n\n![Map](maps/a.png)\n\n- [ ] open\n- [x] done\n\n| a | b |\n|---|---|\n| 1 | 2 |\n\nOne[^1] here.\n\n[^1]: The note.\n\n\\*not italic\\* and snake_case_name"
        let ex = MarkdownSyntax.spans(in: extras)
        func texts(_ test: (MarkdownSpan.Kind) -> Bool) -> [String] { ex.filter { test($0.kind) }.map { (extras as NSString).substring(with: $0.range) } }
        precondition(texts { if case .rule = $0 { return true }; return false } == ["* * *", "---", "***"], "Scene breaks: \(texts { if case .rule = $0 { return true }; return false })")
        precondition(!ex.contains { if case .italic = $0.kind { return (extras as NSString).substring(with: $0.range).contains("* *") }; return false }, "* * * is not italics")
        precondition(texts { if case .comment = $0 { return true }; return false }.first?.hasPrefix("<!-- a **note**") == true, "A comment spans lines")
        precondition(!ex.contains { if case .bold = $0.kind { return true }; return false }, "Nothing inside a comment is styled")
        precondition(texts { if case .image = $0 { return true }; return false } == ["![Map](maps/a.png)"], "Images")
        precondition(!ex.contains { if case .link = $0.kind { return (extras as NSString).substring(with: $0.range).hasPrefix("[Map") }; return false }, "An image isn't also a link")
        precondition(ex.compactMap { span -> Bool? in if case let .task(done) = span.kind { return done }; return nil } == [false, true], "Tasks")
        precondition(texts { if case .table = $0 { return true }; return false }.count == 3, "Table rows")
        precondition(texts { if case .footnote = $0 { return true }; return false } == ["[^1]", "[^1]:"], "Footnote reference and definition")
        precondition(!ex.contains { if case .italic = $0.kind { return true }; return false }, "Escaped stars and snake_case_name style nothing")
        let front = "---\ntitle: A\nlocation: The Pier\n---\n\n# One"
        precondition(!MarkdownSyntax.spans(in: front).contains { if case .rule = $0.kind { return true }; return false }, "The front matter fence is not a scene break")
        print("Passed: Markdown styles, code exclusions, chapter outline, Unicode offsets, empty pairs, formatting exit, link exit.")
    }
}

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
        print("Passed: Markdown styles, code exclusions, chapter outline, Unicode offsets, empty pairs, formatting exit, link exit.")
    }
}

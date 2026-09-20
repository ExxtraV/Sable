import Foundation

@main
enum ProseChecks {
    static func main() {
        func matches(_ text: String, _ words: String) -> [String] {
            Prose.suggestions(in: text, words: words).map { (text as NSString).substring(with: $0) }
        }
        precondition(matches("🌙 Really, a very justifiable choice.", "really, very, just") == ["Really", "very"])
        precondition(matches("---\njust: very\n---\nReally `just` [very](https://very.test)\n```swift\njust\n```\nactually", "just, very, really, actually") == ["Really", "very", "actually"])
        precondition(matches("in order to write a+b", "in order to, a+b") == ["in order to", "a+b"])
        precondition(matches("very", " , ").isEmpty)
        print("Passed: Unicode ranges, whole words, Markdown exclusions, custom phrases, literal escaping, empty rules.")
    }
}

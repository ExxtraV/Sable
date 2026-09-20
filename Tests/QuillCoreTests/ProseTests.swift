import XCTest
@testable import QuillCore

final class ProseTests: XCTestCase {
    func testWholeWordsAndUnicode() {
        let text = "🌙 Really, a very justifiable choice."
        let matches = Prose.suggestions(in: text, words: "really, very, just")
        XCTAssertEqual(matches.map { (text as NSString).substring(with: $0) }, ["Really", "very"])
    }
    func testMarkdownProtectedRegions() {
        let text = "---\njust: very\n---\nReally `just` [very](https://very.test)\n```swift\njust\n```\nactually"
        let matches = Prose.suggestions(in: text, words: "just, very, really, actually")
        XCTAssertEqual(matches.map { (text as NSString).substring(with: $0) }, ["Really", "very", "actually"])
    }
    func testCustomPhrasesAndLiteralPatterns() {
        let text = "in order to write a+b"
        XCTAssertEqual(Prose.suggestions(in: text, words: "in order to, a+b").count, 2)
        XCTAssertEqual(Prose.suggestions(in: text, words: " , ").count, 0)
    }
}

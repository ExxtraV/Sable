import AppKit
import SwiftUI
import QuillCore

@main enum ReadingReferenceChecks {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        let rendered = MarkdownReading.render("# Harbor\n\nA **bright** room with *quiet* doors. [Map](https://example.com)\n\n- A bell", family: "Charter", size: 19, spacing: 0.28)
        precondition(rendered.string.contains("Harbor\n"))
        precondition(!rendered.string.contains("**") && !rendered.string.contains("# "))
        precondition(!rendered.string.contains("https://example.com"))
        precondition(rendered.string.contains("•  A bell"))
        let bold = rendered.attribute(.font, at: (rendered.string as NSString).range(of: "bright").location, effectiveRange: nil) as! NSFont
        precondition(NSFontManager.shared.traits(of: bold).contains(.boldFontMask))
        precondition(NSImage(contentsOfFile: "Assets/Sable.icns") != nil)
        let sentence = "The clever fox runs quickly."
        let classes = SentenceStructure.words(in: sentence, enabled: 31)
        precondition(classes.contains { $0.kind == .noun })
        precondition(classes.contains { $0.kind == .verb })
        precondition(SentenceStructure.words(in: "`fox runs quickly`", enabled: 31).isEmpty)
        precondition(SentenceStructure.words(in: sentence, enabled: 0).isEmpty)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quill-reference-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Reference.md")
        try Data("# Original\n".utf8).write(to: url)
        let document = try ParallelDocument.open(url: url, host: nil)
        precondition(document.text == "# Original\n")
        document.edit("# Updated\n\n**Bold** is still Markdown.\n")
        precondition(document.isDocumentEdited)
        precondition(NSDocumentController.shared.document(for: url) === document)
        let reused = try ParallelDocument.open(url: url, host: nil)
        precondition(reused === document)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            document.save(to: url, ofType: "net.daringfireball.markdown", for: .saveOperation) { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        }
        let saved = try String(contentsOf: url, encoding: .utf8)
        precondition(saved == document.text)
        precondition(!document.isDocumentEdited)
        document.close()
        print("Passed: clean reading, bold rendering, safe links, list rendering, icon decoding, parts of speech, code exclusion, tracked parallel edits/reuse and exact native save.")
    }
}

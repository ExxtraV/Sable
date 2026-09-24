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
        let extras = MarkdownReading.render("One.\n\n* * *\n\n<!-- private\nnote -->\nTwo.\n\n- [ ] open\n- [x] done", family: "Charter", size: 19, spacing: 0.28)
        precondition(extras.string.contains("*  *  *") && !extras.string.contains("•  * *"), "A scene break is drawn as one: \(extras.string.debugDescription)")
        precondition(!extras.string.contains("private") && !extras.string.contains("<!--"), "Notes to yourself are hidden")
        precondition(extras.string.contains("☐  open") && extras.string.contains("☑  done"), "Tasks show their boxes")
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

        // Changed outside Sable while edited here: nothing is saved over it until the writer chooses
        func save() async -> Error? { await withCheckedContinuation { c in document.saveParallel { c.resume(returning: $0) } } }
        func disk() -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "<unreadable>" }
        document.edit("Mine: written in the pane.\n")
        try Data("Theirs: written on another Mac.\n".utf8).write(to: url, options: .atomic)
        let refused = await save()
        precondition(refused is ParallelConflictError && document.conflict, "The save stops: \(String(describing: refused))")
        precondition(disk() == "Theirs: written on another Mac.\n", "The other version is untouched")
        let autosaved: Error? = await withCheckedContinuation { c in document.autosave(withImplicitCancellability: false) { c.resume(returning: $0) } }
        precondition(autosaved != nil && disk() == "Theirs: written on another Mac.\n", "Autosave stops too")
        let kept: Error? = await withCheckedContinuation { c in document.keepMine { c.resume(returning: $0) } }
        precondition(kept == nil && !document.conflict && disk() == "Mine: written in the pane.\n", "Keep Mine saves the pane's text: \(String(describing: kept))")
        let theirsCopy = try String(contentsOf: document.lastKept!, encoding: .utf8)
        precondition(theirsCopy == "Theirs: written on another Mac.\n", "The other version is in the Trash")
        try FileManager.default.removeItem(at: document.lastKept!)

        document.edit("Mine again.\n")
        try Data("Theirs again.\n".utf8).write(to: url, options: .atomic)
        _ = await save()
        precondition(document.conflict, "A second conflict")
        document.useSavedFile()
        precondition(!document.conflict && document.text == "Theirs again.\n" && !document.isDocumentEdited, "Use Saved File loads it")
        let mineCopy = try String(contentsOf: document.lastKept!, encoding: .utf8)
        precondition(mineCopy == "Mine again.\n" && disk() == "Theirs again.\n", "The pane's text is in the Trash; the file is as it was")
        try FileManager.default.removeItem(at: document.lastKept!)
        document.edit("Saved normally.\n")
        let normal = await save()
        precondition(normal == nil && disk() == "Saved normally.\n", "An ordinary save still works")

        // Replace in Project and revision restores read and write coordinated: an open copy saves first, then reloads
        document.edit("Unsaved words in the pane.\n")
        let seen = try await Task.detached { try SafeFile.readText(url) }.value
        precondition(seen == "Unsaved words in the pane.\n" && !document.isDocumentEdited, "A coordinated read gets the pane's unsaved words")
        try await Task.detached { try SafeFile.writeText("Written by a replacement.\n", to: url) }.value
        for _ in 0..<50 where document.text != "Written by a replacement.\n" { try await Task.sleep(nanoseconds: 100_000_000) }
        precondition(document.text == "Written by a replacement.\n" && !document.conflict, "And a coordinated write reloads it")

        // Moved to the Trash outside Sable: the document follows, says so, and Put Back brings it home
        var trashed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashed)
        for _ in 0..<50 where document.fileURL?.standardizedFileURL == url.standardizedFileURL { try await Task.sleep(nanoseconds: 100_000_000) }
        document.checkWhereabouts()
        precondition(document.whereabouts == .inTrash && document.lastPlacedURL?.standardizedFileURL == url.standardizedFileURL, "In the Trash: \(String(describing: document.fileURL))")
        try document.putBack()
        for _ in 0..<50 where document.fileURL?.standardizedFileURL != url.standardizedFileURL { try await Task.sleep(nanoseconds: 100_000_000) }
        document.checkWhereabouts()
        precondition(document.whereabouts == .inPlace && disk() == "Written by a replacement.\n", "Put back where it was, words intact")
        precondition((trashed as URL?).map { !FileManager.default.fileExists(atPath: $0.path) } ?? true, "Nothing is left in the Trash")

        // Deleted outright: the words stay, and Save Again writes the file back
        try FileManager.default.removeItem(at: url)
        document.checkWhereabouts()
        precondition(document.whereabouts == .missing && document.text == "Written by a replacement.\n", "Missing, words kept")
        let resaved: Error? = await withCheckedContinuation { c in document.saveAgain { c.resume(returning: $0) } }
        precondition(resaved == nil && disk() == "Written by a replacement.\n" && document.whereabouts == .inPlace, "Saved again: \(String(describing: resaved))")
        document.close()
        print("Passed: clean reading, bold rendering, safe links, list rendering, icon decoding, parts of speech, code exclusion, tracked parallel edits/reuse, exact native save, coordinated reads/writes reaching the open copy, files trashed or deleted outside Sable (Put Back, Save Again), and outside changes never saved over (Keep Mine / Use Saved File keep the other version in the Trash).")
    }
}

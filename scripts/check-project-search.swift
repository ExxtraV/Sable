import Foundation

@main enum ProjectSearchChecks {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("quill-search-\(getpid())")
        try fm.createDirectory(at: root.appendingPathComponent("Manuscript"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("Characters"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let one = root.appendingPathComponent("Manuscript/Chapter 1.md"), two = root.appendingPathComponent("Manuscript/Chapter 2.md")
        let marren = root.appendingPathComponent("Characters/Marren.md"), hidden = root.appendingPathComponent(".hidden/Secret.md"), other = root.appendingPathComponent("Notes.txt")
        try "# One\n\nMarren walked. marren waited.\nAnd Marrens' boat sank; Marren swam.".write(to: one, atomically: true, encoding: .utf8)
        try "# Two\n\nNo names here.\n\nMarren again, with $1 & \\n in the text.".write(to: two, atomically: true, encoding: .utf8)
        try "---\ntype: character\n---\nMarren Vale".write(to: marren, atomically: true, encoding: .utf8)
        try "Marren".write(to: hidden, atomically: true, encoding: .utf8)
        try "Marren".write(to: other, atomically: true, encoding: .utf8)

        precondition(ProjectSearch.markdownFiles(in: root).map(\.lastPathComponent) == ["Marren.md", "Chapter 1.md", "Chapter 2.md"] || Set(ProjectSearch.markdownFiles(in: root).map(\.lastPathComponent)) == ["Marren.md", "Chapter 1.md", "Chapter 2.md"], "Only visible Markdown files")

        var options = SearchOptions(query: "marren")
        let all = ProjectSearch.find(in: root, options: options)
        precondition(all.map(\.path) == ["Characters/Marren.md", "Manuscript/Chapter 1.md", "Manuscript/Chapter 2.md"], "Paths are relative: \(all.map(\.path))")
        precondition(all.map { $0.hits.count } == [1, 4, 1], "Case-insensitive counts: \(all.map { $0.hits.count })")
        options.caseSensitive = true
        precondition(ProjectSearch.find(in: root, options: options).map { $0.hits.count } == [1], "Match case: 'marren' as typed appears only in Chapter 1")
        options.query = "Marren"
        precondition(ProjectSearch.find(in: root, options: options).flatMap { $0.hits }.count == 5, "Match case counts")
        options.wholeWord = true
        let whole = ProjectSearch.find(in: root, options: options)
        precondition(whole.flatMap { $0.hits }.count == 4, "Whole word skips Marrens': \(whole.flatMap { $0.hits }.count)")
        let first = whole.first { $0.path.hasSuffix("Chapter 1.md") }!.hits
        precondition(first.map(\.line) == [3, 4], "Line numbers: \(first.map(\.line))")
        precondition((first[0].snippet as NSString).substring(with: first[0].snippetRange) == "Marren", "The snippet knows where the match is")
        precondition(ProjectSearch.find(in: root, options: SearchOptions(query: "")).isEmpty, "An empty query finds nothing")

        // Unsaved edits in an open file count
        let live = [one.standardizedFileURL: "# One\n\nNothing here."]
        precondition(ProjectSearch.find(in: root, options: SearchOptions(query: "Marren"), liveText: live).map(\.path) == ["Characters/Marren.md", "Manuscript/Chapter 2.md"], "Live text replaces what is on disk")

        // Replace: literal, with special characters, counted, and reversible
        let replacement = "Mara $1 \\n"
        options = SearchOptions(query: "Marren", caseSensitive: true, wholeWord: true)
        let outcome = ProjectSearch.replaced("Marren and Marrens", options: options, with: replacement)
        precondition(outcome.text == "Mara $1 \\n and Marrens" && outcome.count == 1, "The replacement is literal: \(outcome.text)")
        let receipt = try ProjectSearch.replace(in: [one, two, marren], options: SearchOptions(query: "Marren"), with: "Mara")
        precondition(receipt.replacements == 6 && receipt.files == 3, "Replaced \(receipt.replacements) in \(receipt.files)")
        let afterOne = try String(contentsOf: one, encoding: .utf8)
        precondition(afterOne == "# One\n\nMara walked. Mara waited.\nAnd Maras' boat sank; Mara swam.", "Written: \(afterOne)")
        let hiddenText = try String(contentsOf: hidden, encoding: .utf8), otherText = try String(contentsOf: other, encoding: .utf8)
        precondition(hiddenText == "Marren" && otherText == "Marren", "Other files untouched")
        // Undo puts back only files nobody has touched since: newer words are never overwritten
        let twoAfterReplace = try String(contentsOf: two, encoding: .utf8)
        try (twoAfterReplace + "\nA paragraph written after the replacement.").write(to: two, atomically: true, encoding: .utf8)
        let undone = ProjectSearch.restore(receipt)
        let restored = try String(contentsOf: one, encoding: .utf8)
        precondition(restored.hasPrefix("# One\n\nMarren walked. marren waited."), "Undo puts it back")
        precondition(undone.restored.count == 2 && undone.skipped == [two] && undone.failed.isEmpty, "Restored \(undone.restored), skipped \(undone.skipped)")
        let twoNow = try String(contentsOf: two, encoding: .utf8)
        precondition(twoNow.hasSuffix("A paragraph written after the replacement."), "The file changed since keeps its new words")
        let again = ProjectSearch.restore(receipt)
        precondition(again.restored.isEmpty && again.skipped.count == 3, "A second undo changes nothing")

        // A replacement that stops partway puts back what it already changed
        let locked = root.appendingPathComponent("Locked", isDirectory: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let stuck = locked.appendingPathComponent("Stuck.md")
        try "Marren is here too.".write(to: stuck, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let beforeOne = try String(contentsOf: one, encoding: .utf8)
        var failure: ReplaceFailure?
        do { _ = try ProjectSearch.replace(in: [one, stuck], options: SearchOptions(query: "Marren"), with: "Mara") } catch { failure = error as? ReplaceFailure }
        precondition(failure != nil && failure!.notPutBack.isEmpty, "The failure is reported, with nothing left changed")
        precondition(failure!.localizedDescription.hasSuffix("Nothing was changed."), "And says so: \(failure!.localizedDescription)")
        let oneAfterFailure = try String(contentsOf: one, encoding: .utf8)
        precondition(oneAfterFailure == beforeOne, "The file changed before the failure is back as it was")
        let stuckText = try String(contentsOf: stuck, encoding: .utf8)
        precondition(stuckText == "Marren is here too.", "The file that couldn't be written is whole")
        let none = try ProjectSearch.replace(in: [one], options: SearchOptions(query: "zzz"), with: "x")
        precondition(none.replacements == 0 && none.files == 0, "Nothing to replace changes nothing")

        // Long lines get a short snippet
        let long = String(repeating: "word ", count: 200) + "needle" + String(repeating: " word", count: 200)
        let longHit = ProjectSearch.hits(in: long, options: SearchOptions(query: "needle")).first!
        precondition(longHit.snippet.count < 200 && longHit.snippet.hasPrefix("…") && longHit.snippet.hasSuffix("…") && (longHit.snippet as NSString).substring(with: longHit.snippetRange) == "needle", "Snippet window: \(longHit.snippet.count)")
        print("Passed: project search (case, whole word, paths, lines, unsaved text), literal replace, undo that keeps newer words, rollback after a failed write, hidden and non-Markdown files.")
    }
}

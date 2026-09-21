import Foundation

@main enum RevisionChecks {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("quill-revisions-\(getpid())")
        try fm.createDirectory(at: root.appendingPathComponent("Manuscript"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let one = root.appendingPathComponent("Manuscript/Chapter 1.md"), two = root.appendingPathComponent("Manuscript/Chapter 2.md")
        try "# One\n\nThe harbor bell rang twice.\n\nMarren woke.".write(to: one, atomically: true, encoding: .utf8)
        try "# Two\n\nShe walked to the pier.".write(to: two, atomically: true, encoding: .utf8)

        precondition(Revisions.list(in: root).isEmpty, "No snapshots at first")
        let first = try Revisions.create(name: "First draft", note: "Before the rewrite", root: root, files: [one, two], chapterOrder: ["Chapter 2.md", "Chapter 1.md"])
        precondition(first.files.map(\.path) == ["Manuscript/Chapter 1.md", "Manuscript/Chapter 2.md"] && first.words == 16, "Files and words: \(first.files) \(first.words)")
        precondition(Revisions.list(in: root) == [first], "It is listed, and read back the same")
        precondition(Revisions.list(in: root).first?.chapterOrder == ["Chapter 2.md", "Chapter 1.md"], "The chapter order comes back")
        precondition(fm.fileExists(atPath: root.appendingPathComponent(".sable-revisions/\(first.id)/Manuscript/Chapter 1.md").path), "A plain copy of the file")

        // Nothing changed yet
        var changes = try Revisions.changes(from: first, root: root, files: [one, two])
        precondition(changes.allSatisfy { $0.status == .unchanged }, "Unchanged: \(changes)")

        // Rewrite chapter 1, delete chapter 2, add chapter 3
        try "# One\n\nThe harbor bell rang three times, slowly.\n\nMarren woke early.\n\nA new scene begins.".write(to: one, atomically: true, encoding: .utf8)
        try fm.removeItem(at: two)
        let three = root.appendingPathComponent("Manuscript/Chapter 3.md")
        try "# Three\n\nNew.".write(to: three, atomically: true, encoding: .utf8)
        changes = try Revisions.changes(from: first, root: root, files: [one, three])
        precondition(changes.map(\.status) == [.changed, .removed, .added], "Statuses: \(changes.map(\.status))")
        precondition(changes[0].delta == 7 && changes[1].wordsNow == 0 && changes[2].wordsThen == 0, "Word deltas: \(changes)")
        precondition(changes[0].title == "Chapter 1", "Titles come from file names")

        // Unsaved text counts
        let live = try Revisions.changes(from: first, root: root, files: [one, three], liveText: [one.standardizedFileURL: "# One\n\nThe harbor bell rang twice.\n\nMarren woke."])
        precondition(live[0].status == .unchanged, "What is on the page is what is compared")

        // The comparison
        let oldText = try Revisions.text(of: "Manuscript/Chapter 1.md", in: first, root: root)
        let newText = try String(contentsOf: one, encoding: .utf8)
        let pieces = Revisions.diff(from: oldText, to: newText)
        let deleted = pieces.filter { $0.kind == .deleted }.map(\.text).joined(separator: "|")
        let inserted = pieces.filter { $0.kind == .inserted }.map(\.text).joined(separator: "|")
        precondition(deleted == "twice|woke." || deleted.contains("twice") && deleted.contains("woke"), "Deleted words: \(deleted)")
        precondition(inserted.contains("three times, slowly") && inserted.contains("early") && inserted.contains("A new scene begins."), "Inserted words: \(inserted)")
        precondition(pieces.filter { $0.kind == .same }.map(\.text).joined().contains("# One"), "Unchanged text stays")
        let rebuiltNew = pieces.filter { $0.kind != .deleted }.map(\.text).joined()
        let rebuiltOld = pieces.filter { $0.kind != .inserted }.map(\.text).joined()
        precondition(rebuiltNew == newText && rebuiltOld == oldText, "Reading the pieces gives back both texts:\n\(rebuiltNew.debugDescription)\n\(newText.debugDescription)")
        precondition(Revisions.diff(from: "same\n", to: "same\n") == [DiffPiece(kind: .same, text: "same\n")], "No change, no markup")
        precondition(Revisions.diff(from: "", to: "new").map(\.kind) == [.inserted] && Revisions.diff(from: "old", to: "").map(\.kind) == [.deleted], "From nothing and to nothing")
        let big = (0..<3000).map { "word\($0)" }.joined(separator: " ")
        let bigRewrite = (0..<3000).map { "other\($0)" }.joined(separator: " ")
        let started = Date()
        let bigPieces = Revisions.diff(from: big, to: bigRewrite)
        precondition(Date().timeIntervalSince(started) < 3 && bigPieces.contains { $0.kind == .deleted } && bigPieces.contains { $0.kind == .inserted }, "A full rewrite is quick: \(Date().timeIntervalSince(started))s")

        // Restoring
        try Revisions.restore("Manuscript/Chapter 1.md", from: first, root: root)
        let restored = try String(contentsOf: one, encoding: .utf8)
        precondition(restored == oldText, "Chapter restored")
        try Revisions.restore("Manuscript/Chapter 2.md", from: first, root: root)
        precondition(fm.fileExists(atPath: two.path), "A deleted chapter comes back")

        // Safety snapshots, naming, deleting
        let safety = try Revisions.create(name: "Before restoring", kind: .safety, root: root, files: [one], date: Date().addingTimeInterval(5))
        precondition(Revisions.list(in: root).map(\.id) == [safety.id, first.id], "Newest first")
        try Revisions.rename(first, name: "Draft 1", note: "Sent to Sam", in: root)
        precondition(Revisions.list(in: root).last?.name == "Draft 1" && Revisions.list(in: root).last?.note == "Sent to Sam", "Rename and note")
        Revisions.delete(safety, in: root)
        precondition(Revisions.list(in: root).map(\.id) == [first.id] && !fm.fileExists(atPath: root.appendingPathComponent(".sable-revisions/\(safety.id)").path), "Deleted for good")

        // Files outside the folder are ignored, and unsaved text is kept
        let stray = fm.temporaryDirectory.appendingPathComponent("stray-\(getpid()).md")
        try "x".write(to: stray, atomically: true, encoding: .utf8)
        defer { try? fm.removeItem(at: stray) }
        let scoped = try Revisions.create(name: "Scoped", root: root, files: [one, stray], liveText: [one.standardizedFileURL: "On the page, not saved."])
        precondition(scoped.files.map(\.path) == ["Manuscript/Chapter 1.md"], "Only files inside the folder")
        let keptText = try Revisions.text(of: "Manuscript/Chapter 1.md", in: scoped, root: root)
        precondition(keptText == "On the page, not saved.", "Unsaved text is what is kept")

        // Automatic snapshots: daily, and only when something changed
        let auto = fm.temporaryDirectory.appendingPathComponent("quill-auto-\(getpid())")
        try fm.createDirectory(at: auto, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: auto) }
        let note = auto.appendingPathComponent("A.md")
        try "one two three".write(to: note, atomically: true, encoding: .utf8)
        let day1 = Date()
        precondition(Revisions.automaticIfDue(root: auto, files: [note], chapterOrder: nil, now: day1) != nil, "The first one is taken")
        precondition(Revisions.automaticIfDue(root: auto, files: [note], chapterOrder: nil, now: day1.addingTimeInterval(3600)) == nil, "Not twice in a day")
        precondition(Revisions.automaticIfDue(root: auto, files: [note], chapterOrder: nil, now: day1.addingTimeInterval(90_000)) == nil, "A day later, but nothing has changed")
        try "one two three four".write(to: note, atomically: true, encoding: .utf8)
        precondition(Revisions.automaticIfDue(root: auto, files: [note], chapterOrder: nil, now: day1.addingTimeInterval(90_000)) != nil, "A day later, and it changed")
        precondition(Revisions.automaticIfDue(root: auto, files: [], chapterOrder: nil) == nil, "Nothing to snapshot")
        // Pruning keeps the newest automatic ones and every manual one
        for n in 0..<25 {
            try "text \(n)".write(to: note, atomically: true, encoding: .utf8)
            try Revisions.create(name: "Auto \(n)", kind: .automatic, root: auto, files: [note], date: day1.addingTimeInterval(Double(200_000 + n * 100_000)))
        }
        try Revisions.create(name: "Keep me", kind: .manual, root: auto, files: [note], date: day1.addingTimeInterval(100))
        Revisions.prune(in: auto)
        let remaining = Revisions.list(in: auto)
        precondition(remaining.filter { $0.kind == .automatic }.count == Revisions.automaticLimit && remaining.contains { $0.name == "Keep me" }, "Old automatic snapshots are pruned, manual ones never: \(remaining.count)")
        print("Passed: snapshots (files, words, order, unsaved text), comparison by file and by word, restore, safety and automatic snapshots, pruning.")
    }
}

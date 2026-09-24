import Foundation

@main enum FileSafetyChecks {
    static func text(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "<unreadable>" }

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("quill-file-safety-\(getpid())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: root.appendingPathComponent("Locked").path)
            try? fm.removeItem(at: root)
        }
        let chapter = root.appendingPathComponent("Chapter 1.md")
        try Data("The harbor bell rang twice.\n".utf8).write(to: chapter)

        // Reading and writing
        let read = try SafeFile.readText(chapter)
        precondition(read == "The harbor bell rang twice.\n", "Reads the file")
        try SafeFile.writeText("The harbor bell rang three times.\n", to: chapter)
        precondition(text(chapter) == "The harbor bell rang three times.\n", "Writes the file")
        let listing = try fm.contentsOfDirectory(atPath: root.path)
        precondition(listing == ["Chapter 1.md"], "No temporary files are left beside it")

        // A Finder tag and the creation date survive a rewrite
        let tags = try PropertyListSerialization.data(fromPropertyList: ["Draft\n1"], format: .binary, options: 0)
        let tagName = "com.apple.metadata:_kMDItemUserTags"
        precondition(tags.withUnsafeBytes { setxattr(chapter.path, tagName, $0.baseAddress, tags.count, 0, 0) } == 0, "Tag set")
        let created = try fm.attributesOfItem(atPath: chapter.path)[.creationDate] as? Date
        Thread.sleep(forTimeInterval: 1.1)
        try SafeFile.writeText("Marren woke.\n", to: chapter)
        precondition(getxattr(chapter.path, tagName, nil, 0, 0, 0) == tags.count, "The Finder tag is kept")
        let createdAfter = try fm.attributesOfItem(atPath: chapter.path)[.creationDate] as? Date
        precondition(createdAfter == created, "The creation date is kept")

        // Writing only if nothing changed since
        let wrote = try SafeFile.replaceText(at: chapter, ifStill: "Marren woke.\n", with: "Mara woke.\n")
        precondition(wrote, "Unchanged: written")
        precondition(text(chapter) == "Mara woke.\n", "The new text is there")
        let refused = try SafeFile.replaceText(at: chapter, ifStill: "Marren woke.\n", with: "Old text.\n")
        precondition(!refused, "Changed since: refused")
        precondition(text(chapter) == "Mara woke.\n", "A refused write leaves the file alone")
        let missing = root.appendingPathComponent("Gone.md")
        let recreated = try SafeFile.replaceText(at: missing, ifStill: "Anything", with: "New")
        precondition(!recreated, "A missing file is not recreated")
        precondition(!fm.fileExists(atPath: missing.path), "Still missing")

        // A deleted file can be written back, into a folder that no longer exists either
        let restored = root.appendingPathComponent("Manuscript/Chapter 9.md")
        try SafeFile.writeText("Back again.\n", to: restored)
        precondition(text(restored) == "Back again.\n", "A deleted file comes back")

        // A write that can't happen leaves the original whole
        let locked = root.appendingPathComponent("Locked", isDirectory: true)
        try fm.createDirectory(at: locked, withIntermediateDirectories: true)
        let guarded = locked.appendingPathComponent("Chapter 2.md")
        try Data("Every word of chapter two.\n".utf8).write(to: guarded)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        var failed = false
        do { try SafeFile.writeText("Nothing.\n", to: guarded) } catch { failed = true }
        precondition(failed, "Writing into a read-only folder fails")
        precondition(text(guarded) == "Every word of chapter two.\n", "The original is untouched")
        failed = false
        do { _ = try SafeFile.replaceText(at: guarded, ifStill: "Every word of chapter two.\n", with: "Nothing.\n") } catch { failed = true }
        precondition(failed && text(guarded) == "Every word of chapter two.\n", "Also when checking first")
        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)

        // Keeping a copy in the Trash (removed again here, since these are only test files)
        let name = SafeFile.keptName(for: chapter, date: Date(timeIntervalSince1970: 0))
        precondition(name.hasPrefix("Chapter 1 (kept ") && name.hasSuffix(").md"), "Kept name: \(name)")
        let kept = try SafeFile.keepInTrash("Words set aside.\n", named: "sable-check-\(getpid()).md")
        precondition(text(kept) == "Words set aside.\n", "The kept text is in the Trash")
        try fm.removeItem(at: kept)
        let copy = try SafeFile.keepCopyInTrash(of: chapter, named: "sable-check-copy-\(getpid()).md")
        precondition(text(copy) == "Mara woke.\n", "A copy of the file is in the Trash")
        precondition(text(chapter) == "Mara woke.\n", "The file itself stays")
        try fm.removeItem(at: copy)

        // Moving never replaces anything, and knows where a file has ended up
        let moved = root.appendingPathComponent("Moved.md")
        try SafeFile.move(from: chapter, to: moved)
        precondition(text(moved) == "Mara woke.\n" && !fm.fileExists(atPath: chapter.path), "Moved")
        try Data("Someone else's file.\n".utf8).write(to: chapter)
        failed = false
        do { try SafeFile.move(from: moved, to: chapter) } catch { failed = true }
        precondition(failed && text(chapter) == "Someone else's file.\n" && text(moved) == "Mara woke.\n", "A move never lands on another file")
        precondition(FileWhereabouts.of(moved) == .inPlace, "In place")
        precondition(FileWhereabouts.of(root.appendingPathComponent("Nowhere.md")) == .missing, "Missing")
        precondition(FileWhereabouts.of(URL(fileURLWithPath: NSHomeDirectory() + "/.Trash/Chapter.md")) == .inTrash, "In the Trash")
        precondition(FileWhereabouts.of(URL(fileURLWithPath: NSHomeDirectory() + "/Library/Mobile Documents/.Trash/Chapter.md")) == .inTrash, "In iCloud Drive's Trash")
        precondition(FileWhereabouts.of(URL(fileURLWithPath: "/Volumes/Backup/.Trashes/501/Chapter.md")) == .inTrash, "In another disk's Trash")
        var inTrash: NSURL?
        try fm.trashItem(at: moved, resultingItemURL: &inTrash)
        let trashedURL = (inTrash as URL?)!
        precondition(FileWhereabouts.of(trashedURL) == .inTrash, "A real trashed file: \(trashedURL.path)")
        try SafeFile.move(from: trashedURL, to: moved)
        precondition(text(moved) == "Mara woke.\n" && FileWhereabouts.of(moved) == .inPlace, "And put back")

        print("Passed: coordinated reads and writes, no leftovers, tags and dates kept, write-if-unchanged, deleted files restored, failed writes leave originals whole, copies kept in the Trash, moves that never replace, and where a file has ended up (in place, missing, in the Trash).")
    }
}

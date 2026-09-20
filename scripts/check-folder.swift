import Foundation

@main enum FolderChecks {
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("quill-folder-check-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Chapter 10.md", "Chapter 2.md", "World.MARKDOWN", "Notes.txt", "image.png", ".hidden.md"] {
            try Data("test".utf8).write(to: root.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Scenes"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Outside"), withDestinationURL: URL(fileURLWithPath: "/"))
        let entries = try FolderListing.entries(at: root)
        precondition(entries.map(\.name) == ["Scenes", "Chapter 2.md", "Chapter 10.md", "Notes.txt", "World.MARKDOWN"])
        precondition(entries.first?.isDirectory == true)
        let empty = try FolderListing.entries(at: root.appendingPathComponent("Scenes"))
        precondition(empty.isEmpty)
        precondition(FolderCreation.fileName(for: " Act 1 ", kind: .file) == "Act 1.md")
        precondition(FolderCreation.fileName(for: "Notes.TXT", kind: .file) == "Notes.TXT")
        precondition(FolderCreation.fileName(for: "v1.2 draft", kind: .file) == "v1.2 draft.md")
        precondition(FolderCreation.fileName(for: "Act.1", kind: .folder) == "Act.1")
        for bad in ["", "  ", ".hidden", "a/b", "a:b"] { precondition(FolderCreation.fileName(for: bad, kind: .file) == nil) }
        let made = try FolderCreation.create(.file, named: "Prologue", in: root)
        precondition(made.lastPathComponent == "Prologue.md" && FileManager.default.fileExists(atPath: made.path))
        let madeFolder = try FolderCreation.create(.folder, named: "Drafts", in: root)
        var isDir: ObjCBool = false
        precondition(FileManager.default.fileExists(atPath: madeFolder.path, isDirectory: &isDir) && isDir.boolValue)
        do { _ = try FolderCreation.create(.file, named: "prologue.md", in: root); precondition(FileManager.default.fileExists(atPath: made.path)) }
        catch { /* case-insensitive volumes report the duplicate; case-sensitive ones create a second file */ }
        do { _ = try FolderCreation.create(.file, named: "Prologue", in: root); preconditionFailure("must not overwrite") }
        catch FolderCreationError.exists {}
        // Moving
        let moveRoot = root.appendingPathComponent("MoveTest")
        let a = moveRoot.appendingPathComponent("A"), b = moveRoot.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: a.appendingPathComponent("Deep"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: moveRoot.appendingPathComponent("x.md"))
        try Data("y".utf8).write(to: a.appendingPathComponent("Deep/y.md"))
        let moved = try FolderMove.perform([moveRoot.appendingPathComponent("x.md")], into: a, root: moveRoot)
        precondition(moved.count == 1 && FileManager.default.fileExists(atPath: a.appendingPathComponent("x.md").path))
        precondition(!FileManager.default.fileExists(atPath: moveRoot.appendingPathComponent("x.md").path))
        let noOp = try FolderMove.perform([a.appendingPathComponent("x.md")], into: a, root: moveRoot)
        precondition(noOp.isEmpty, "Same-folder drop is a no-op")
        do { _ = try FolderMove.perform([a], into: a.appendingPathComponent("Deep"), root: moveRoot); preconditionFailure() } catch FolderMoveError.intoItself {}
        do { _ = try FolderMove.perform([a], into: a, root: moveRoot); preconditionFailure() } catch {}
        do { _ = try FolderMove.perform([moveRoot.appendingPathComponent("x.md")], into: FileManager.default.temporaryDirectory, root: moveRoot); preconditionFailure() } catch FolderMoveError.outsideRoot {}
        try Data("z".utf8).write(to: b.appendingPathComponent("x.md"))
        do { _ = try FolderMove.perform([a.appendingPathComponent("x.md")], into: b, root: moveRoot); preconditionFailure() } catch FolderMoveError.exists {}
        precondition(FileManager.default.fileExists(atPath: a.appendingPathComponent("x.md").path), "A refused move leaves the item where it was")
        var moveMarks = FolderMarks()
        moveMarks.colors["A"] = .green; moveMarks.colors["A/Deep"] = .blue; moveMarks.pinned = ["A/Deep/y.md", "B"]
        let folderMove = try FolderMove.perform([a], into: b, root: moveRoot)
        let carried = moveMarks.remapped(moves: folderMove, root: moveRoot)
        precondition(carried.colors == ["B/A": .green, "B/A/Deep": .blue] && carried.pinned == ["B/A/Deep/y.md", "B"])
        precondition(FileManager.default.fileExists(atPath: b.appendingPathComponent("A/Deep/y.md").path))
        // Search, sort, word count
        let lib = root.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: lib.appendingPathComponent("Novel/Act Two"), withIntermediateDirectories: true)
        try Data("a".utf8).write(to: lib.appendingPathComponent("Novel/Act Two/Storm chapter.md"))
        try Data("a".utf8).write(to: lib.appendingPathComponent("Novel/Chapter One.md"))
        try Data("a".utf8).write(to: lib.appendingPathComponent("Novel/image.png"))
        try Data("a".utf8).write(to: lib.appendingPathComponent("Chapters notes.txt"))
        let hits = FolderListing.search("chapter", in: lib).map(\.name)
        precondition(Set(hits) == ["Storm chapter.md", "Chapter One.md", "Chapters notes.txt"], "Search reaches nested folders and skips other file types: \(hits)")
        precondition(hits.prefix(2).allSatisfy { $0.hasPrefix("Chapter") }, "Prefix matches rank first")
        precondition(FolderListing.search("Act", in: lib).map(\.name) == ["Act Two"], "Folders match too, and extensions don't")
        precondition(FolderListing.search("md", in: lib).isEmpty, "Extensions aren't searched")
        precondition(FolderListing.search("  ", in: lib).isEmpty)
        let older = BrowserEntry(url: URL(fileURLWithPath: "/a/Older.md"), isDirectory: false, modified: Date(timeIntervalSince1970: 100))
        let newer = BrowserEntry(url: URL(fileURLWithPath: "/a/Newer.md"), isDirectory: false, modified: Date(timeIntervalSince1970: 900))
        let folder = BrowserEntry(url: URL(fileURLWithPath: "/a/Zed"), isDirectory: true, modified: nil)
        precondition(FolderListing.sorted([older, newer, folder], by: .modified, foldersFirst: true).map(\.name) == ["Zed", "Newer.md", "Older.md"])
        precondition(FolderListing.sorted([older, newer, folder], by: .name, foldersFirst: false).map(\.name) == ["Newer.md", "Older.md", "Zed"])
        precondition(older.displayName == "Older" && folder.displayName == "Zed")
        precondition(FolderListing.wordCount(in: "# Title\n\nOne two — three ---\n") == 4)
        // Rename
        let file = lib.appendingPathComponent("Chapters notes.txt")
        let d1 = try FolderRename.destination(for: file, isDirectory: false, name: "Ideas")
        precondition(d1.lastPathComponent == "Ideas.txt", "Keeps the original extension")
        let d2 = try FolderRename.destination(for: file, isDirectory: false, name: "Ideas.md")
        precondition(d2.lastPathComponent == "Ideas.md")
        let d3 = try FolderRename.destination(for: file, isDirectory: false, name: "chapters NOTES")
        precondition(d3.lastPathComponent == "chapters NOTES.txt", "Case-only changes are allowed")
        do { _ = try FolderRename.destination(for: file, isDirectory: false, name: "a/b"); preconditionFailure() } catch FolderCreationError.invalidName {}
        do { _ = try FolderRename.destination(for: lib.appendingPathComponent("Novel/Chapter One.md"), isDirectory: false, name: "image.png"); } catch { preconditionFailure("A .png typed name becomes .png.md, which is free") }
        let renamed = try FolderRename.perform(lib.appendingPathComponent("Novel/Chapter One.md"), isDirectory: false, name: "Opening")
        precondition(renamed.lastPathComponent == "Opening.md" && FileManager.default.fileExists(atPath: renamed.path))
        try Data("a".utf8).write(to: lib.appendingPathComponent("Novel/Taken.md"))
        do { _ = try FolderRename.perform(renamed, isDirectory: false, name: "Taken"); preconditionFailure() } catch FolderCreationError.exists {}
        let renamedFolder = try FolderRename.perform(lib.appendingPathComponent("Novel"), isDirectory: true, name: "Book")
        precondition(FileManager.default.fileExists(atPath: renamedFolder.appendingPathComponent("Act Two/Storm chapter.md").path))
        precondition(FolderMove.rewrite(lib.appendingPathComponent("Novel/Act Two/x.md"), moves: [(lib.appendingPathComponent("Novel"), renamedFolder)]) == renamedFolder.appendingPathComponent("Act Two/x.md"))
        // Color labels
        let labelDefaults = UserDefaults(suiteName: "quill-label-check-\(UUID())")!
        ColorLabels.save([.red: "Draft", .blue: "Final"], defaults: labelDefaults)
        precondition(ColorLabels.load(defaults: labelDefaults) == [.red: "Draft", .blue: "Final"])
        let marksRoot = URL(fileURLWithPath: "/tmp/Writing")
        precondition(FolderMarks.key(for: marksRoot.appendingPathComponent("Scenes/One.md"), in: marksRoot) == "Scenes/One.md")
        precondition(FolderMarks.key(for: marksRoot, in: marksRoot) == nil)
        precondition(FolderMarks.key(for: URL(fileURLWithPath: "/tmp/Writing-other/x.md"), in: marksRoot) == nil, "Sibling folders sharing a prefix are outside the root")
        var marks = FolderMarks()
        marks.colors["Scenes"] = .blue
        marks.colors["Notes.txt"] = .red
        marks.pinned.insert("Scenes")
        precondition(marks.usedColors == [.red, .blue])
        precondition(marks.keys(matching: .color(.blue)) == ["Scenes"] && marks.keys(matching: .pinned) == ["Scenes"])
        let defaults = UserDefaults(suiteName: "quill-folder-check-\(UUID())")!
        FolderMarksStore.save(marks, for: marksRoot, defaults: defaults)
        precondition(FolderMarksStore.load(for: marksRoot, defaults: defaults) == marks)
        precondition(FolderMarksStore.load(for: URL(fileURLWithPath: "/tmp/Elsewhere"), defaults: defaults).isEmpty)
        print("Passed: natural sorting, subfolders, Markdown extensions, hidden/unsupported-file and symlink exclusions, folder marks (keys, filters, persistence), new file/folder creation, moving (safety checks, marks follow moved items), search, sorting, rename, and color labels.")
    }
}

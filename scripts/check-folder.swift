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
        print("Passed: natural sorting, subfolders, Markdown extensions, hidden/unsupported-file and symlink exclusions.")
    }
}

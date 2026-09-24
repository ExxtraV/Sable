import Foundation

/// Reading and rewriting a writer's files so no words are lost on the way.
///
/// Every read and write goes through NSFileCoordinator. Before a read, anything that has the file open with unsaved
/// changes (another app, or a Sable document in another window or the reference pane) saves them first, so what is
/// read is what the writer sees. After a write, it is told the file changed so it can reload instead of saving an
/// older copy over it. A write goes to a temporary file first and then replaces the original in one step, so a full
/// disk or a crash halfway leaves the original whole, and the file keeps its Finder tags and creation date.
///
/// Coordination waits for whoever has the file open, which can need the main thread: call these off the main thread.
enum SafeFile {
    static func readText(_ url: URL) throws -> String {
        var coordinationError: NSError?
        var result: Result<String, Error> = .failure(CocoaError(.fileReadUnknown))
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { actual in
            result = Result { try String(contentsOf: actual, encoding: .utf8) }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    static func writeText(_ text: String, to url: URL) throws {
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { actual in
            do { try replace(actual, with: text) } catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
    }

    /// Writes `text` only if the file still says `expected`. Returns false, having written nothing, if it changed since.
    static func replaceText(at url: URL, ifStill expected: String, with text: String) throws -> Bool {
        var coordinationError: NSError?
        var result: Result<Bool, Error> = .success(false)
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], writingItemAt: url, options: .forMerging, error: &coordinationError) { reader, writer in
            result = Result {
                guard (try? String(contentsOf: reader, encoding: .utf8)) == expected else { return false }
                try replace(writer, with: text)
                return true
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }

    /// Moves a file, coordinated so a document that has it open follows it. Never replaces anything at `destination`.
    static func move(from source: URL, to destination: URL) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else { throw CocoaError(.fileWriteFileExists, userInfo: [NSURLErrorKey: destination]) }
        var coordinationError: NSError?
        var failure: Error?
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forMoving, writingItemAt: destination, options: .forReplacing, error: &coordinationError) { from, to in
            do { try fm.moveItem(at: from, to: to) } catch { failure = error }
        }
        if let error = coordinationError ?? failure { throw error }
    }

    /// Puts a copy of `text` in the Trash, so a version that is about to be replaced is never simply gone.
    @discardableResult
    static func keepInTrash(_ text: String, named name: String) throws -> URL {
        try keepInTrash(named: name) { try Data(text.utf8).write(to: $0) }
    }

    /// Puts a copy of the file at `url` in the Trash, leaving the file itself where it is.
    @discardableResult
    static func keepCopyInTrash(of url: URL, named name: String? = nil) throws -> URL {
        try keepInTrash(named: name ?? url.lastPathComponent) { try FileManager.default.copyItem(at: url, to: $0) }
    }

    /// "Chapter 1 (kept 2026-09-23 at 14.05).md": a name that says when a copy was set aside.
    static func keptName(for url: URL, date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        return "\(stem) (kept \(formatter.string(from: date)))" + (ext.isEmpty ? "" : "." + ext)
    }

    private static func keepInTrash(named name: String, make: (URL) throws -> Void) throws -> URL {
        let fm = FileManager.default
        let folder = fm.temporaryDirectory.appendingPathComponent("sable-kept-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: folder) }
        let copy = folder.appendingPathComponent(name)
        try make(copy)
        var trashed: NSURL?
        try fm.trashItem(at: copy, resultingItemURL: &trashed)
        return (trashed as URL?) ?? copy
    }

    /// Replaces the file in one step from a finished temporary copy, keeping the original's attributes.
    private static func replace(_ url: URL, with text: String) throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: url.path) {
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        let scratch = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: url, create: true)
        defer { try? fm.removeItem(at: scratch) }
        let temporary = scratch.appendingPathComponent(url.lastPathComponent)
        try Data(text.utf8).write(to: temporary)
        // A file that is gone (a deleted chapter being restored) appears whole or not at all, and never lands on one
        // that turned up in the meantime.
        if fm.fileExists(atPath: url.path) { _ = try fm.replaceItemAt(url, withItemAt: temporary) }
        else { try fm.moveItem(at: temporary, to: url) }
    }
}

/// Where an open file has ended up. An open document follows its file wherever it goes, into the Trash too, and
/// keeps saving there; a file deleted outright exists only in the open document until it is saved again.
enum FileWhereabouts: Equatable, Sendable {
    case inPlace
    /// In the Trash (put there by Finder, another app, or sync): emptying the Trash would delete it.
    case inTrash
    /// Gone from disk.
    case missing

    static func of(_ url: URL) -> FileWhereabouts {
        // ~/.Trash, iCloud Drive's Mobile Documents/.Trash, and .Trashes on other disks.
        if url.standardizedFileURL.pathComponents.contains(where: { $0 == ".Trash" || $0 == ".Trashes" }) { return .inTrash }
        return FileManager.default.fileExists(atPath: url.path) ? .inPlace : .missing
    }
}

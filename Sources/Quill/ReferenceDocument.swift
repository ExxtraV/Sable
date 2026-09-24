import AppKit
import SwiftUI

/// A second Markdown file lives beside the active draft, never in another tab.
@MainActor
final class ParallelDocument: NSDocument, ObservableObject {
    @Published var text = ""
    @Published var saveError: String?
    /// The file changed outside Sable while it had edits here. Nothing is saved until the writer picks a version.
    @Published private(set) var conflict = false
    /// Where the version that wasn't kept went when the last conflict was settled.
    @Published private(set) var lastKept: URL?
    weak var hostWindow: NSWindow?
    private var scopedURL: URL?
    /// The file's text when it was last read or saved here, to tell whether something else has changed it since.
    private var savedText: String?

    override nonisolated class var autosavesInPlace: Bool { true }
    override var windowForSheet: NSWindow? { hostWindow }

    static func open(url: URL, host: NSWindow?) throws -> ParallelDocument {
        if let existing = NSDocumentController.shared.document(for: url) {
            guard let parallel = existing as? ParallelDocument else {
                throw NSError(domain: "SableMarkdownWriter", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file is already the active document. Choose another file to open beside it."])
            }
            parallel.hostWindow = host
            return parallel
        }

        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let document = try ParallelDocument(contentsOf: url, ofType: "net.daringfireball.markdown")
            if scoped { document.scopedURL = url }
            document.hostWindow = host
            NSDocumentController.shared.addDocument(document)
            return document
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let content = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        if Thread.isMainThread { MainActor.assumeIsolated { loaded(content) } }
        else { DispatchQueue.main.sync { self.loaded(content) } }
    }

    private func loaded(_ content: String) {
        text = content
        savedText = content
        conflict = false
    }

    /// Every save and autosave comes through here. If the file on disk no longer says what was last read or saved,
    /// something else changed it, and saving would replace that version without a word: stop and let the writer choose.
    override func save(to url: URL, ofType typeName: String, for saveOperation: NSDocument.SaveOperationType, completionHandler: @escaping (Error?) -> Void) {
        if saveOperation == .saveOperation || saveOperation == .autosaveInPlaceOperation, url == fileURL, changedOutside(url) {
            conflict = true
            completionHandler(ParallelConflictError(name: url.lastPathComponent))
            return
        }
        let writing = text
        super.save(to: url, ofType: typeName, for: saveOperation) { [weak self] error in
            if error == nil {
                if Thread.isMainThread { MainActor.assumeIsolated { self?.savedText = writing } }
                else { DispatchQueue.main.sync { self?.savedText = writing } }
            }
            completionHandler(error)
        }
    }

    private func changedOutside(_ url: URL) -> Bool {
        guard let savedText, FileManager.default.fileExists(atPath: url.path) else { return false }
        return (try? String(contentsOf: url, encoding: .utf8)) != savedText
    }

    /// Settles a conflict by saving the text here. The version on disk goes to the Trash as a copy first.
    func keepMine(completion: @escaping (Error?) -> Void = { _ in }) {
        guard let url = fileURL else { return }
        do {
            if FileManager.default.fileExists(atPath: url.path) { lastKept = try SafeFile.keepCopyInTrash(of: url, named: SafeFile.keptName(for: url)) }
        } catch {
            saveError = "Could not keep a copy of the other version, so nothing was saved: \(error.localizedDescription)"
            completion(error)
            return
        }
        // What is on disk now is safely kept, so it is what this save may replace.
        savedText = try? String(contentsOf: url, encoding: .utf8)
        fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        conflict = false
        saveParallel(completion: completion)
    }

    /// Settles a conflict by loading the version on disk. The text here goes to the Trash as a copy first.
    func useSavedFile() {
        guard let url = fileURL else { return }
        do {
            lastKept = try SafeFile.keepInTrash(text, named: SafeFile.keptName(for: url))
            try revert(toContentsOf: url, ofType: fileType ?? "net.daringfireball.markdown")
            saveError = nil
        } catch {
            saveError = "Could not load the saved file: \(error.localizedDescription)"
        }
    }

    override func data(ofType typeName: String) throws -> Data { Data(text.utf8) }

    func edit(_ value: String) {
        guard value != text else { return }
        text = value
        if lastKept != nil { lastKept = nil }
        updateChangeCount(.changeDone)
    }

    func saveParallel(completion: @escaping (Error?) -> Void = { _ in }) {
        guard let url = fileURL else {
            let error = CocoaError(.fileNoSuchFile)
            saveError = error.localizedDescription
            completion(error)
            return
        }
        save(to: url, ofType: fileType ?? "net.daringfireball.markdown", for: .saveOperation) { [weak self] error in
            self?.saveError = error?.localizedDescription
            self?.objectWillChange.send()
            completion(error)
        }
    }

    override func close() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        super.close()
    }
}

struct ParallelConflictError: LocalizedError {
    let name: String
    var errorDescription: String? { "“\(name)” changed outside Sable while you were editing it here, so it wasn’t saved. Choose which version to keep." }
}

struct ParallelEditingSurface: View {
    @ObservedObject var document: ParallelDocument
    var active = true
    var zoom = 1.0
    @AppStorage("fontFamily") private var family = "Charter"
    @AppStorage("fontSize") private var size = 19.0
    @AppStorage("lineSpacing") private var spacing = 0.28
    @AppStorage("syntaxClasses") private var syntaxClasses = 0
    @StateObject private var commands = EditorCommands()

    var body: some View {
        NativeEditor(
            zoom: zoom,
            zoomKey: WritingZoom.parallelKey,
            text: Binding(get: { document.text }, set: { document.edit($0) }),
            review: false,
            words: "",
            fontSize: size,
            pageWidth: 540,
            commands: commands,
            fontFamily: family,
            lineSpacing: spacing,
            readOnly: !active,
            syntaxClasses: syntaxClasses,
            documentUndoManager: document.undoManager,
            editingDocument: document,
            saveAction: { document.saveParallel() }
        )
        .onChange(of: active) { _, value in
            if value { commands.editor?.window?.makeFirstResponder(commands.editor) }
        }
    }
}

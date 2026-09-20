import AppKit
import SwiftUI

/// A second Markdown file lives beside the active draft, never in another tab.
@MainActor
final class ParallelDocument: NSDocument, ObservableObject {
    @Published var text = ""
    @Published var saveError: String?
    weak var hostWindow: NSWindow?
    private var scopedURL: URL?

    override nonisolated class var autosavesInPlace: Bool { true }
    override var windowForSheet: NSWindow? { hostWindow }

    static func open(url: URL, host: NSWindow?) throws -> ParallelDocument {
        if let existing = NSDocumentController.shared.document(for: url) {
            guard let parallel = existing as? ParallelDocument else {
                throw NSError(domain: "NewQuill", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file is already the active document. Choose another file to open beside it."])
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
        if Thread.isMainThread { MainActor.assumeIsolated { text = content } }
        else { DispatchQueue.main.sync { self.text = content } }
    }

    override func data(ofType typeName: String) throws -> Data { Data(text.utf8) }

    func edit(_ value: String) {
        guard value != text else { return }
        text = value
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

struct ParallelEditingSurface: View {
    @ObservedObject var document: ParallelDocument
    var active = true
    @AppStorage("fontFamily") private var family = "Charter"
    @AppStorage("fontSize") private var size = 19.0
    @AppStorage("lineSpacing") private var spacing = 0.28
    @AppStorage("syntaxClasses") private var syntaxClasses = 0
    @StateObject private var commands = EditorCommands()

    var body: some View {
        NativeEditor(
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
            saveAction: { document.saveParallel() }
        )
        .onChange(of: active) { _, value in
            if value { commands.editor?.window?.makeFirstResponder(commands.editor) }
        }
    }
}

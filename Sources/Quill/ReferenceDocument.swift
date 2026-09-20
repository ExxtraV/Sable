import AppKit
import SwiftUI

@MainActor
final class ReferenceDocument: NSDocument, ObservableObject {
    @Published var text = ""
    @Published var saveError: String?
    weak var hostWindow: NSWindow?
    private var scopedURL: URL?
    override nonisolated class var autosavesInPlace: Bool { true }
    override var windowForSheet: NSWindow? { windowControllers.first?.window ?? hostWindow }

    static func open(_ item: WorldDocument, host: NSWindow?) throws -> ReferenceDocument {
        return try open(url: item.resolve(), host: host)
    }
    static func open(url: URL, host: NSWindow?) throws -> ReferenceDocument {
        if let existing = NSDocumentController.shared.document(for: url) {
            guard let reference = existing as? ReferenceDocument else {
                throw NSError(domain: "NewQuill", code: 1, userInfo: [NSLocalizedDescriptionKey: "This file is already open in a writing tab. Close that tab before editing it as a reference so there is only one editable version."])
            }
            reference.hostWindow = host
            return reference
        }
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let document = try ReferenceDocument(contentsOf: url, ofType: "net.daringfireball.markdown")
            if scoped { document.scopedURL = url }
            document.hostWindow = host
            NSDocumentController.shared.addDocument(document)
            return document
        } catch { if scoped { url.stopAccessingSecurityScopedResource() }; throw error }
    }
    override func read(from data: Data, ofType typeName: String) throws {
        guard let content = String(data: data, encoding: .utf8) else { throw CocoaError(.fileReadInapplicableStringEncoding) }
        if Thread.isMainThread { MainActor.assumeIsolated { text = content } }
        else { DispatchQueue.main.sync { self.text = content } }
    }
    override func data(ofType typeName: String) throws -> Data { Data(text.utf8) }
    func edit(_ value: String) {
        guard value != text else { return }
        text = value
        updateChangeCount(.changeDone)
    }
    func saveReference() {
        guard let url = fileURL else { return }
        save(to: url, ofType: fileType ?? "net.daringfireball.markdown", for: .saveOperation) { [weak self] error in
            self?.saveError = error?.localizedDescription
            self?.objectWillChange.send()
        }
    }
    override func close() {
        scopedURL?.stopAccessingSecurityScopedResource()
        scopedURL = nil
        super.close()
    }
    override func makeWindowControllers() {
        guard windowControllers.isEmpty else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 680), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: ReferenceStandalone(document: self))
        addWindowController(NSWindowController(window: window))
    }
}

struct ReferenceEditingSurface: View {
    @ObservedObject var document: ReferenceDocument
    var active = true
    @AppStorage("fontFamily") private var family = "Charter"
    @AppStorage("fontSize") private var size = 19.0
    @AppStorage("lineSpacing") private var spacing = 0.28
    @AppStorage("syntaxClasses") private var syntaxClasses = 0
    @StateObject private var commands = EditorCommands()
    var body: some View {
        NativeEditor(text: Binding(get: { document.text }, set: { document.edit($0) }), review: false, words: "", fontSize: size,
            pageWidth: 540, commands: commands, fontFamily: family, lineSpacing: spacing, readOnly: !active,
            darker: true, syntaxClasses: syntaxClasses, documentUndoManager: document.undoManager, saveAction: { document.saveReference() })
            .onChange(of: active) { _, value in
                if value { commands.editor?.window?.makeFirstResponder(commands.editor) }
            }
    }
}
private struct ReferenceStandalone: View {
    @ObservedObject var document: ReferenceDocument
    var body: some View {
        VStack(spacing: 0) {
            ReferenceEditingSurface(document: document)
            HStack {
                Text(document.isDocumentEdited ? "Edited" : "Saved").foregroundStyle(.secondary)
                Spacer()
                Button("Save") { document.saveReference() }
            }.padding(14)
            if let error = document.saveError { Text(error).foregroundStyle(.red).padding() }
        }.preferredColorScheme(.dark)
    }
}

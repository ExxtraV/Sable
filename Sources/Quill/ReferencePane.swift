import SwiftUI
import QuillCore

enum ReferenceReader {
    static func read(_ item: WorldDocument) throws -> String {
        let url = try item.resolve()
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var result: Result<String, Error> = .success("")
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinationError) { coordinatedURL in
            result = Result {
                let handle = try FileHandle(forReadingFrom: coordinatedURL)
                defer { try? handle.close() }
                let data = try handle.read(upToCount: 200_000) ?? Data()
                var text = String(decoding: data, as: UTF8.self)
                if data.count == 200_000 { text += "\n\n[Preview truncated — open to read the complete document.]" }
                return text
            }
        }
        if let coordinationError { throw coordinationError }
        return try result.get()
    }
}

struct ReferencePane: View {
    let item: WorldDocument
    let openToEdit: () -> Void
    let close: () -> Void
    var hostWindow: NSWindow? = nil
    @AppStorage("fontFamily") private var family = "Charter"
    @AppStorage("fontSize") private var size = 19.0
    @AppStorage("lineSpacing") private var spacing = 0.28
    @State private var text = ""
    @State private var error: String?
    @State private var loading = true
    @State private var reload = UUID()
    @State private var document: ReferenceDocument?
    @State private var editing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(editing ? "REFERENCE · EDITING" : "REFERENCE · READING").font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                }
                Spacer()
                Button(editing ? "Read" : "Edit") {
                    if editing { document?.saveReference(); editing = false }
                    else {
                        do { document = try ReferenceDocument.open(item, host: hostWindow); editing = true }
                        catch { self.error = error.localizedDescription }
                    }
                }.disabled(loading)
                Button { reload = UUID() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(document != nil).help("Reload saved reference").accessibilityLabel("Reload reference")
                Button { document?.saveReference(); close() } label: { Image(systemName: "xmark") }.accessibilityLabel("Close reference")
            }.buttonStyle(.plain).padding(16)
            Divider()
            if let document {
                ReferenceDocumentContent(document: document, editing: editing)
            } else if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else { ReadingView(text: text, family: family, size: size, spacing: spacing, width: 540, darker: true) }
            if let error {
                HStack { Text(error).font(.caption).foregroundStyle(.orange); Button("Dismiss") { self.error = nil } }.padding(12)
            }
            if document == nil {
                Divider()
                HStack {
                    Text("Saved version").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open in tab", action: openToEdit).font(.caption)
                }.padding(12)
            }
        }
        .background(Color(white: 0.075))
        .environment(\.colorScheme, .dark)
        .frame(minWidth: 360, idealWidth: 440, maxWidth: 640)
        .task(id: reload) {
            if let url = try? item.resolve(), let existing = NSDocumentController.shared.document(for: url) as? ReferenceDocument {
                document = existing; existing.hostWindow = hostWindow; loading = false; return
            }
            loading = true; error = nil
            let result = await Task.detached(priority: .userInitiated) { Result { try ReferenceReader.read(item) } }.value
            guard !Task.isCancelled else { return }
            loading = false
            switch result { case let .success(value): text = value; case let .failure(failure): error = failure.localizedDescription }
        }
        .onDisappear { if document?.isDocumentEdited == true { document?.saveReference() } }
    }
}

private struct ReferenceDocumentContent: View {
    @ObservedObject var document: ReferenceDocument
    let editing: Bool
    @AppStorage("fontFamily") private var family = "Charter"
    @AppStorage("fontSize") private var size = 19.0
    @AppStorage("lineSpacing") private var spacing = 0.28
    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ReferenceEditingSurface(document: document, active: editing).opacity(editing ? 1 : 0).allowsHitTesting(editing).accessibilityHidden(!editing)
                if !editing { ReadingView(text: document.text, family: family, size: size, spacing: spacing, width: 540, darker: true) }
            }
            Divider()
            HStack {
                Text(document.isDocumentEdited ? "Edited · autosave enabled" : "Saved").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Save") { document.saveReference() }.font(.caption)
            }.padding(12)
            if let error = document.saveError { Text(error).font(.caption).foregroundStyle(.orange).padding(12) }
        }
    }
}

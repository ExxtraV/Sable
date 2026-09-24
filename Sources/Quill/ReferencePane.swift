import SwiftUI

enum ParallelReader {
    static func read(_ url: URL) throws -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return try String(contentsOf: url, encoding: .utf8)
    }
}

struct ParallelMarkdownPane: View {
    let url: URL
    let closeRequest: UUID?
    let close: () -> Void
    let didClose: () -> Void
    var hostWindow: NSWindow? = nil
    @AppStorage("fontFamily") private var family = "Charter"
    @AppStorage("fontSize") private var size = 19.0
    @AppStorage("lineSpacing") private var spacing = 0.28
    @AppStorage("parallelZoom") private var zoom = 1.0
    @State private var text = ""
    @State private var error: String?
    @State private var loading = true
    @State private var reload = UUID()
    @State private var document: ParallelDocument?
    @State private var editing = false
    @State private var closing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.deletingPathExtension().lastPathComponent).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text(editing ? "PARALLEL · EDITING" : "PARALLEL · READING")
                        .font(.system(size: 9, weight: .medium)).tracking(1).foregroundStyle(.secondary)
                }
                Spacer()
                if abs(zoom - 1) > 0.01 {
                    Button("\(Int((zoom * 100).rounded()))%") { WritingZoom.set(1, for: WritingZoom.parallelKey) }
                        .font(.system(size: 11)).foregroundStyle(.secondary).help("This pane is zoomed on its own. Click to reset it to 100%.")
                }
                Button(editing ? "Read" : "Edit") {
                    if editing { document?.saveParallel(); editing = false }
                    else { openForEditing() }
                }
                .disabled(loading)
                Button { reload = UUID() } label: { Image(systemName: "arrow.clockwise") }
                    .disabled(document != nil).help("Reload saved file").accessibilityLabel("Reload parallel document")
                Button(action: requestClose) { Image(systemName: "xmark") }
                    .accessibilityLabel("Close parallel document")
            }
            .buttonStyle(.plain)
            .padding(16)
            Divider()

            if let document {
                ParallelDocumentContent(document: document, editing: editing, zoom: zoom)
            } else if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ReadingView(zoom: zoom, zoomKey: WritingZoom.parallelKey, text: text, family: family, size: size, spacing: spacing, width: 540)
            }

            if let error {
                HStack { Text(error).font(.caption).foregroundStyle(.orange); Button("Dismiss") { self.error = nil } }.padding(12)
            }
        }
        .frame(minWidth: 360, idealWidth: 440, maxWidth: 640)
        .task(id: reload) {
            loading = true
            error = nil
            let result = await Task.detached(priority: .userInitiated) { Result { try ParallelReader.read(url) } }.value
            guard !Task.isCancelled else { return }
            loading = false
            switch result {
            case let .success(value): text = value
            case let .failure(failure): error = failure.localizedDescription
            }
        }
        .onChange(of: closeRequest) { _, request in
            if request != nil { requestClose() }
        }
        .onDisappear {
            guard closing else { return }
            document?.close()
            didClose()
        }
    }

    private func openForEditing() {
        do {
            document = try ParallelDocument.open(url: url, host: hostWindow)
            editing = true
        } catch { self.error = error.localizedDescription }
    }

    private func requestClose() {
        guard !closing else { return }
        guard let document, document.isDocumentEdited else {
            closing = true
            close()
            return
        }
        closing = true
        document.saveParallel { saveError in
            guard saveError == nil else {
                closing = false
                error = saveError?.localizedDescription
                return
            }
            close()
        }
    }
}

private struct ParallelDocumentContent: View {
    @ObservedObject var document: ParallelDocument
    let editing: Bool
    var zoom = 1.0
    @AppStorage("fontFamily") private var family = "Charter"
    @AppStorage("fontSize") private var size = 19.0
    @AppStorage("lineSpacing") private var spacing = 0.28

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                ParallelEditingSurface(document: document, active: editing, zoom: zoom)
                    .opacity(editing ? 1 : 0)
                    .allowsHitTesting(editing)
                    .accessibilityHidden(!editing)
                if !editing { ReadingView(zoom: zoom, zoomKey: WritingZoom.parallelKey, text: document.text, family: family, size: size, spacing: spacing, width: 540) }
            }
            Divider()
            HStack {
                Text(document.isDocumentEdited ? "Edited" : "Saved").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("Save") { document.saveParallel() }.font(.caption)
            }.padding(12)
            if document.conflict {
                VStack(alignment: .leading, spacing: 8) {
                    Text("This file changed outside Sable while you were editing it here. Choose the version to keep; the other goes to the Trash as a copy.")
                        .font(.caption).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button("Keep Mine") { document.keepMine() }
                            .help("Save the text in this pane. The version on disk goes to the Trash as a copy.")
                        Button("Use Saved File") { document.useSavedFile() }
                            .help("Load the version on disk. The text in this pane goes to the Trash as a copy.")
                    }.font(.caption)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12))
                .accessibilityElement(children: .contain)
            } else if let error = document.saveError {
                Text(error).font(.caption).foregroundStyle(.orange).padding(12)
            } else if let kept = document.lastKept {
                Text("The other version is in the Trash as “\(kept.lastPathComponent)”.").font(.caption).foregroundStyle(.secondary).padding(12)
            }
        }
    }
}

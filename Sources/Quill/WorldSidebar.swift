import SwiftUI
import AppKit
import QuillCore

struct WorldDocument: Identifiable, Codable {
    var id = UUID()
    let name: String
    var bookmark: Data

    static func reference(to url: URL) throws -> WorldDocument {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        return WorldDocument(name: url.deletingPathExtension().lastPathComponent,
            bookmark: try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    func resolve() throws -> URL {
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}

@MainActor
final class WorldLibrary: ObservableObject {
    @Published private(set) var documents: [WorldDocument] = []
    init() {
        if let data = UserDefaults.standard.data(forKey: "worldDocuments"),
           let saved = try? JSONDecoder().decode([WorldDocument].self, from: data) { documents = saved }
    }
    func add(_ urls: [URL]) throws {
        var updated = documents
        for url in urls {
            if updated.contains(where: { (try? $0.resolve().standardizedFileURL) == url.standardizedFileURL }) { continue }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            updated.append(WorldDocument(name: url.deletingPathExtension().lastPathComponent, bookmark: bookmark))
        }
        documents = updated
        persist()
    }
    func remove(_ id: UUID) {
        documents.removeAll { $0.id == id }
        persist()
    }
    private func persist() {
        if let data = try? JSONEncoder().encode(documents) { UserDefaults.standard.set(data, forKey: "worldDocuments") }
    }
}

struct WorldSidebar: View {
    let text: String
    let commands: EditorCommands
    let addFiles: () -> Void
    let chooseFolder: () -> Void
    let currentURL: URL?
    let showBeside: (WorldDocument) -> Void
    @AppStorage("outlineTitle") private var outlineTitle = "Outline"
    @AppStorage("outlineLevel") private var outlineLevel = 0
    @State private var showOutlineOptions = false
    @EnvironmentObject private var library: WorldLibrary
    @State private var selected: UUID?
    @State private var search = ""
    @State private var preview = ""
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var refreshID = UUID()

    private var selectedDocument: WorldDocument? { library.documents.first { $0.id == selected } }
    private var chapters: [ChapterHeading] {
        MarkdownSyntax.headings(in: text).filter { outlineLevel == 0 || $0.level == outlineLevel }
    }
    private var title: String {
        outlineTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Outline" : outlineTitle
    }
    private func openBeside(_ item: WorldDocument) {
        selected = nil
        showBeside(item)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WRITING DESK").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2)
                Spacer()
                Button(action: addFiles) { Image(systemName: "plus") }.buttonStyle(.plain)
                    .help("Pin Markdown world documents").accessibilityLabel("Pin world documents")
            }.foregroundStyle(.secondary).padding(18)
            TextField("Find files, headings, or notes", text: $search)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 14).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    FolderBrowserSection(currentURL: currentURL, search: search, chooseFolder: chooseFolder,
                        openFile: { url in commands.openInTab(url) { errorMessage = $0?.localizedDescription } },
                        pinFile: { url in do { try library.add([url]) } catch { errorMessage = error.localizedDescription } },
                        showBeside: { url in do { openBeside(try WorldDocument.reference(to: url)) } catch { errorMessage = error.localizedDescription } })
                    Divider().padding(.vertical, 6)
                    HStack {
                        Text(title.uppercased()).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        Button { showOutlineOptions.toggle() } label: { Image(systemName: "slider.horizontal.3") }
                            .buttonStyle(.plain).help("Name and filter your outline").accessibilityLabel("Outline options")
                            .popover(isPresented: $showOutlineOptions) { OutlineControls() }
                    }
                    if chapters.isEmpty { Text(outlineLevel == 0 ? "Add # headings to build your outline." : "No level \(outlineLevel) headings yet.").font(.caption).foregroundStyle(.secondary) }
                    ForEach(chapters.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }) { heading in
                        Button { commands.jump(to: heading.range) } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Image(systemName: "text.alignleft").font(.caption).foregroundStyle(.tertiary)
                                Text(heading.title).font(.system(size: 12)).lineLimit(2)
                                Spacer(minLength: 0)
                            }.padding(.leading, CGFloat(min(heading.level - 1, 3)) * 8)
                        }.buttonStyle(.plain).padding(.vertical, 3)
                    }
                    Divider().padding(.vertical, 6)
                    Text("WORLD DOCUMENTS").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    if library.documents.isEmpty {
                        Text("Keep characters, places, and timelines nearby. Pin existing Markdown files with +.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(library.documents.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { item in
                        Button { selected = item.id; refreshID = UUID() } label: {
                            Label(item.name, systemImage: "doc.text").font(.system(size: 12))
                                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                                .background(selected == item.id ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        }.buttonStyle(.plain)
                        .contextMenu {
                            Button("Read beside manuscript") { openBeside(item) }
                            Button("Unpin from sidebar") { if selected == item.id { selected = nil }; library.remove(item.id) }
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
            if let item = selectedDocument {
                Divider()
                HStack {
                    Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Spacer()
                    Button { openBeside(item) } label: { Image(systemName: "rectangle.split.2x1") }
                        .help("Read beside manuscript").accessibilityLabel("Read beside manuscript")
                    Button { refreshID = UUID() } label: { Image(systemName: "arrow.clockwise") }
                        .help("Reload preview").accessibilityLabel("Reload preview")
                    Button { selected = nil } label: { Image(systemName: "xmark") }
                        .help("Close preview").accessibilityLabel("Close preview")
                }.buttonStyle(.plain).padding(14)
                if loading { ProgressView().frame(maxWidth: .infinity).padding() }
                ScrollView {
                    Text(preview).font(.system(size: 13, design: .serif)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 16).padding(.bottom, 12)
                }.frame(maxHeight: 250)
                HStack {
                    Text("Read-only preview").font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open to edit") {
                        do {
                            let url = try item.resolve()
                            commands.openInTab(url) { errorMessage = $0?.localizedDescription }
                        } catch { errorMessage = error.localizedDescription }
                    }.font(.caption)
                }.padding(14)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .dropDestination(for: URL.self) { urls, _ in
            let markdown = urls.filter { ["md", "markdown", "txt"].contains($0.pathExtension.lowercased()) }
            guard !markdown.isEmpty else { return false }
            do { try library.add(markdown); return true }
            catch { errorMessage = error.localizedDescription; return false }
        }
        .task(id: refreshID) {
            guard let item = selectedDocument else { return }
            loading = true
            preview = ""
            let result = await Task.detached(priority: .userInitiated) { () -> String in
                do { return try ReferenceReader.read(item) }
                catch { return "Could not read this note: \(error.localizedDescription)\nTry unpinning and adding it again." }
            }.value
            guard !Task.isCancelled else { return }
            preview = result
            loading = false
        }
        .alert("Could not open document", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }
}

import SwiftUI
import AppKit

struct BrowserEntry: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let isDirectory: Bool
    var name: String { url.lastPathComponent }
}

enum FolderListing {
    static func entries(at folder: URL) throws -> [BrowserEntry] {
        let urls = try FileManager.default.contentsOfDirectory(at: folder,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey], options: [.skipsHiddenFiles])
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .isPackageKey])
            guard values.isSymbolicLink != true, values.isPackage != true else { return nil }
            if values.isDirectory == true { return BrowserEntry(url: url, isDirectory: true) }
            guard values.isRegularFile == true, ["md", "markdown", "txt"].contains(url.pathExtension.lowercased()) else { return nil }
            return BrowserEntry(url: url, isDirectory: false)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
}

struct BrowserRow: Identifiable {
    let entry: BrowserEntry
    let depth: Int
    var id: URL { entry.url }
}

@MainActor
final class FolderBrowser: ObservableObject {
    @Published private(set) var root: URL?
    @Published private(set) var current: URL?
    @Published private(set) var entries: [BrowserEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var expanded: Set<URL> = []
    @Published private(set) var children: [URL: [BrowserEntry]] = [:]
    @Published private(set) var loadingFolders: Set<URL> = []
    @Published private(set) var folderErrors: [URL: String] = [:]
    var visibleEntries: [BrowserRow] {
        func flatten(_ entries: [BrowserEntry], depth: Int) -> [BrowserRow] {
            entries.flatMap { entry -> [BrowserRow] in
                let row = BrowserRow(entry: entry, depth: depth)
                guard entry.isDirectory, expanded.contains(entry.url) else { return [row] }
                return [row] + flatten(children[entry.url] ?? [], depth: depth + 1)
            }
        }
        return flatten(entries, depth: 0)
    }
    func toggle(_ url: URL) {
        if expanded.contains(url) { expanded.remove(url) }
        else { expanded.insert(url); loadChildren(url) }
    }
    private func loadChildren(_ url: URL) {
        let request = requestID
        loadingFolders.insert(url)
        folderErrors[url] = nil
        Task {
            let result = await Task.detached(priority: .userInitiated) { Result { try FolderListing.entries(at: url) } }.value
            guard request == requestID else { return }
            loadingFolders.remove(url)
            switch result { case let .success(items): children[url] = items; case let .failure(error): folderErrors[url] = error.localizedDescription }
        }
    }
    private var scoped = false
    private var requestID = UUID()

    init() {
        if let bookmark = UserDefaults.standard.data(forKey: "writingFolder") {
            var stale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
                scoped = url.startAccessingSecurityScopedResource()
                root = url
                current = url
                if stale, let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    UserDefaults.standard.set(fresh, forKey: "writingFolder")
                }
            } catch { self.error = "Choose the folder again: \(error.localizedDescription)" }
        }
    }
    func choose(_ url: URL) throws {
        let newScope = url.startAccessingSecurityScopedResource()
        do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            if scoped { root?.stopAccessingSecurityScopedResource() }
            scoped = newScope
            root = url
            current = url
            expanded = []; children = [:]
            UserDefaults.standard.set(bookmark, forKey: "writingFolder")
            refresh()
        } catch {
            if newScope { url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
    func navigate(_ url: URL) {
        guard let root else { return }
        let base = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path == base || path.hasPrefix(base + "/") else { return }
        current = url
        expanded = []; children = [:]
        refresh()
    }
    func up() {
        guard let current, current != root else { return }
        navigate(current.deletingLastPathComponent())
    }
    func refresh() {
        guard let current else { return }
        requestID = UUID()
        let request = requestID
        loading = true
        error = nil
        entries = []
        children = [:]; loadingFolders = []; folderErrors = [:]
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result { try FolderListing.entries(at: current) }
            }.value
            guard request == requestID else { return }
            loading = false
            switch result {
            case let .success(items):
                entries = items
                for folder in expanded { loadChildren(folder) }
            case let .failure(failure): error = failure.localizedDescription
            }
        }
    }
}

struct FolderBrowserSection: View {
    @EnvironmentObject private var browser: FolderBrowser
    let currentURL: URL?
    let search: String
    let chooseFolder: () -> Void
    let openFile: (URL) -> Void
    let pinFile: (URL) -> Void
    let showBeside: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("FILES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    Button("Choose Writing Folder…", action: chooseFolder)
                    Button("Refresh") { browser.refresh() }.disabled(browser.current == nil)
                    if let root = browser.root { Button("Back to \(root.lastPathComponent)") { browser.navigate(root) } }
                } label: { Image(systemName: "ellipsis.circle") }
                .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("File browser menu")
            }
            if let current = browser.current {
                HStack(spacing: 8) {
                    Button { browser.up() } label: { Image(systemName: "arrow.up") }
                        .disabled(current == browser.root).accessibilityLabel("Parent folder")
                    Text(current.lastPathComponent).lineLimit(1).font(.system(size: 12, weight: .medium)).help(current.path)
                    Spacer()
                    if browser.loading { ProgressView().controlSize(.small) }
                }.buttonStyle(.plain).padding(.vertical, 4)
                ForEach(browser.visibleEntries.filter { search.isEmpty || $0.entry.name.localizedCaseInsensitiveContains(search) }) { row in
                    let entry = row.entry
                    Button {
                        if entry.isDirectory { browser.toggle(entry.url) } else { openFile(entry.url) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: entry.isDirectory ? (browser.expanded.contains(entry.url) ? "chevron.down" : "chevron.right") : "doc.text").foregroundStyle(.secondary)
                            Text(entry.name).lineLimit(1)
                            Spacer(minLength: 0)
                            if browser.loadingFolders.contains(entry.url) { ProgressView().controlSize(.mini) }
                        }.font(.system(size: 12)).padding(7).padding(.leading, CGFloat(min(row.depth, 10)) * 12)
                            .background(currentURL?.standardizedFileURL == entry.url.standardizedFileURL ? Color.accentColor.opacity(0.14) : .clear, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                    .contextMenu {
                        if entry.isDirectory { Button("Open this folder") { browser.navigate(entry.url) } }
                        else {
                            Button("Open to write") { openFile(entry.url) }
                            Button("Read beside manuscript") { showBeside(entry.url) }
                            Button("Pin as world document") { pinFile(entry.url) }
                        }
                    }
                }
                if !browser.folderErrors.isEmpty { Text("A subfolder could not be read. Refresh or choose the folder again.").font(.caption).foregroundStyle(.secondary) }
                if !browser.loading && browser.entries.isEmpty && browser.error == nil {
                    Text("No Markdown files in this folder.").font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Button("Choose Writing Folder…", action: chooseFolder).font(.caption)
                Text("Browse Markdown files and subfolders. Open files stay available as tabs.").font(.caption).foregroundStyle(.secondary)
            }
            if let error = browser.error { Text(error).font(.caption).foregroundStyle(.secondary) }
        }
        .onAppear { if browser.entries.isEmpty { browser.refresh() } }
    }
}

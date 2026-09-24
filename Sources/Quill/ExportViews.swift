import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// What is being exported: a project's whole manuscript, or just the document in front of you.
enum ExportSource: Identifiable {
    /// `unsaved` swaps in the text of a chapter that's open with changes not yet saved, so the export is what's on screen.
    case manuscript(project: URL, title: String, unsaved: [String: String])
    /// `url` is the document's file, if it has one, so the export can't be saved over it.
    case document(title: String, markdown: String, url: URL?)
    var id: String {
        switch self { case .manuscript: return "manuscript"; case .document: return "document" }
    }
}

/// Choose a format, a look, and which chapters, then save one file.
struct ExportSheet: View {
    let source: ExportSource
    let close: () -> Void
    @AppStorage("exportAuthor") private var author = NSFullUserName()
    @AppStorage("exportFormat") private var formatName = ExportFormat.pdf.rawValue
    @AppStorage("exportStyle") private var styleName = ExportStyle.manuscript.rawValue
    @AppStorage("exportPageSize") private var pageName = PageSize.regional.rawValue
    @AppStorage("exportTitlePage") private var titlePage = true
    @AppStorage("exportPageBreaks") private var pageBreaks = true
    @State private var title = ""
    @State private var chapters: [ExportChapter] = []
    @State private var included: Set<String> = []
    @State private var loading = true
    @State private var working = false
    @State private var problem: String?

    private var format: ExportFormat { ExportFormat(rawValue: formatName) ?? .pdf }
    private var isManuscript: Bool { if case .manuscript = source { return true } else { return false } }
    private var chosen: [ExportChapter] { chapters.filter { included.contains($0.id) } }
    private var chosenWords: Int { chosen.reduce(0) { $0 + $1.words } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(isManuscript ? "Export Manuscript" : "Export Document").font(.title3.weight(.semibold))
            Form {
                TextField("Title", text: $title)
                TextField("Author", text: $author)
                Picker("Format", selection: $formatName) {
                    ForEach(ExportFormat.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                }.pickerStyle(.segmented)
                if format.isPaged {
                    Picker("Style", selection: $styleName) {
                        ForEach(ExportStyle.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented)
                    Text((ExportStyle(rawValue: styleName) ?? .manuscript).detail).font(.caption).foregroundStyle(.secondary)
                    Picker("Page size", selection: $pageName) {
                        ForEach(PageSize.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
                    }.pickerStyle(.segmented)
                }
                if isManuscript {
                    Toggle("Title page", isOn: $titlePage)
                    if format.isPaged { Toggle("Start each chapter on a new page", isOn: $pageBreaks) }
                }
            }.formStyle(.columns)

            if isManuscript { chapterList }

            if let problem { Text(problem).font(.caption).foregroundStyle(.orange) }
            HStack {
                Text(isManuscript ? summary : "").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if working { ProgressView().controlSize(.small) }
                Button("Cancel", role: .cancel, action: close).keyboardShortcut(.cancelAction)
                Button("Export…", action: save).keyboardShortcut(.defaultAction)
                    .disabled(working || loading || chosen.isEmpty || title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22).frame(width: 470)
        .task { await load() }
    }

    private var summary: String {
        loading ? "Reading chapters…" : "\(chosen.count) of \(chapters.count) chapters · \(chosenWords.formatted()) words"
    }

    private var chapterList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Chapters").font(.subheadline.weight(.medium))
                Spacer()
                Button("All") { included = Set(chapters.map(\.id)) }.buttonStyle(.link).font(.caption)
                Button("None") { included = [] }.buttonStyle(.link).font(.caption)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(chapters) { chapter in
                        Toggle(isOn: Binding(get: { included.contains(chapter.id) }, set: { on in
                            if on { included.insert(chapter.id) } else { included.remove(chapter.id) }
                        })) {
                            HStack {
                                Text(chapter.title).lineLimit(1)
                                Spacer(minLength: 8)
                                Text(chapter.words.formatted()).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                            }
                        }.toggleStyle(.checkbox)
                    }
                    if chapters.isEmpty && !loading { Text("This project has no chapters yet.").font(.caption).foregroundStyle(.secondary) }
                }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 150)
            .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            Text("In the order you arranged them in the Manuscript tab.").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func load() async {
        switch source {
        case let .manuscript(project, projectTitle, unsaved):
            title = projectTitle
            var loaded = await Task.detached { ManuscriptExport.chapters(project: project) }.value
            for (name, markdown) in unsaved {
                if let index = loaded.firstIndex(where: { $0.name == name }) { loaded[index] = ManuscriptExport.chapter(named: name, markdown: markdown) }
            }
            chapters = loaded
            included = Set(loaded.map(\.id))
        case let .document(documentTitle, markdown, _):
            title = documentTitle
            chapters = [ManuscriptExport.chapter(named: documentTitle + ".md", markdown: markdown)]
            included = Set(chapters.map(\.id))
        }
        loading = false
    }

    /// The files this export is made from.
    private var sourceFiles: [URL] {
        switch source {
        case let .manuscript(project, _, _):
            let folder = FictionProject.folder(for: .chapter, in: project)
            return (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        case let .document(_, _, url): return url.map { [$0] } ?? []
        }
    }

    private var protectedFolders: [URL] {
        if case let .manuscript(project, _, _) = source { return [FictionProject.folder(for: .chapter, in: project)] }
        return []
    }

    private func save() {
        var options = ExportOptions()
        options.title = title.trimmingCharacters(in: .whitespaces)
        options.author = author.trimmingCharacters(in: .whitespaces)
        options.format = format
        options.style = ExportStyle(rawValue: styleName) ?? .manuscript
        options.pageSize = PageSize(rawValue: pageName) ?? .regional
        options.titlePage = isManuscript && titlePage
        options.chapterPageBreaks = isManuscript ? pageBreaks : true
        let selected = chosen

        let panel = NSSavePanel()
        panel.title = "Export"
        panel.prompt = "Export"
        panel.nameFieldStringValue = ManuscriptExport.fileName(for: options.title, format: format)
        if let type = UTType(filenameExtension: format.fileExtension) { panel.allowedContentTypes = [type] }
        panel.canCreateDirectories = true
        // Capture a copy of `options`: a captured `var` is shared with this main-actor function, so it can't be sent to the detached export.
        panel.begin { [options] response in
            guard response == .OK, let url = panel.url else { return }
            if let refusal = ExportDestination.problem(for: url, sources: sourceFiles, open: NSDocumentController.shared.documents.compactMap(\.fileURL), protectedFolders: protectedFolders) {
                problem = refusal
                return
            }
            working = true
            problem = nil
            Task {
                let outcome = await Task.detached { () -> Result<Void, Error> in
                    Result {
                        let data = try ManuscriptExport.export(selected, options: options)
                        // A file this replaces goes to the Trash as a copy first, in case it wasn't meant to go.
                        if FileManager.default.fileExists(atPath: url.path) { try SafeFile.keepCopyInTrash(of: url, named: SafeFile.keptName(for: url)) }
                        try data.write(to: url, options: .atomic)
                    }
                }.value
                working = false
                switch outcome {
                case .success:
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                    close()
                case let .failure(error): problem = error.localizedDescription
                }
            }
        }
    }
}

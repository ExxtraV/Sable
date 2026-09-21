import SwiftUI
import UniformTypeIdentifiers
import QuillCore

extension UTType {
    static let markdownDocument = UTType(importedAs: "net.daringfireball.markdown", conformingTo: .plainText)
}

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.markdownDocument, .plainText] }
    static var writableContentTypes: [UTType] { [.markdownDocument] }
    var text = ""

    init() {}
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents,
              let value = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadInapplicableStringEncoding)
        }
        text = value
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}

@main
struct QuillApp: App {
    @NSApplicationDelegateAdaptor(QuillAppDelegate.self) private var appDelegate
    @StateObject private var updater = AppUpdater()
    @StateObject private var browser = FolderBrowser()
    init() {
        LaunchBehavior.register()
        #if QUILL_PREVIEW
        let previewBrowser = FolderBrowser()
        if let folder = Bundle.main.resourceURL?.appendingPathComponent("Examples") {
            try? previewBrowser.choose(folder)
        }
        _browser = StateObject(wrappedValue: previewBrowser)
        #endif
    }
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            WritingView(document: file.$document, fileURL: file.fileURL)
                .environmentObject(browser)
        }
        .commands {
            WritingCommands()
            CommandGroup(replacing: .newItem) {
                Button("New Markdown File") { SingleDocumentCoordinator.shared.newDocument() }
                    .keyboardShortcut("n")
                Button("Open Markdown File…") { SingleDocumentCoordinator.shared.chooseDocument() }
                    .keyboardShortcut("o")
            }
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…", action: updater.check).disabled(!updater.canCheck)
            }
            CommandGroup(after: .textEditing) {
                Button("Find in Manuscript…") {
                    let item = NSMenuItem()
                    item.tag = Int(NSFindPanelAction.showFindPanel.rawValue)
                    NSApp.sendAction(#selector(NSTextView.performFindPanelAction(_:)), to: nil, from: item)
                }.keyboardShortcut("f")
            }
            CommandMenu("Markdown") {
                Button("Bold") { send(#selector(WritingTextView.markBold(_:))) }.keyboardShortcut("b")
                Button("Italic") { send(#selector(WritingTextView.markItalic(_:))) }.keyboardShortcut("i")
                Button("Link") { send(#selector(WritingTextView.markLink(_:))) }.keyboardShortcut("k")
                Button("Strikethrough") { send(#selector(WritingTextView.markStrikethrough(_:))) }.keyboardShortcut("x", modifiers: [.command, .shift])
                Button("Inline Code") { send(#selector(WritingTextView.markCode(_:))) }.keyboardShortcut("k", modifiers: [.command, .shift])
                Button("Leave Formatting") { send(#selector(WritingTextView.exitFormatting(_:))) }.keyboardShortcut("\\", modifiers: [.command])
                Divider()
                Button("Heading (cycle # ## ###)") { send(#selector(WritingTextView.markHeading(_:))) }.keyboardShortcut("h", modifiers: [.command, .shift])
                Button("Quote") { send(#selector(WritingTextView.markQuote(_:))) }.keyboardShortcut("q", modifiers: [.command, .option])
                Button("Bulleted List") { send(#selector(WritingTextView.markBulletList(_:))) }.keyboardShortcut("8", modifiers: [.command, .shift])
                Button("Numbered List") { send(#selector(WritingTextView.markNumberedList(_:))) }.keyboardShortcut("7", modifiers: [.command, .shift])
                Button("Task List") { send(#selector(WritingTextView.markTaskList(_:))) }.keyboardShortcut("9", modifiers: [.command, .shift])
                Button("Scene Break") { send(#selector(WritingTextView.markSceneBreak(_:))) }.keyboardShortcut("l", modifiers: [.command, .shift])
                Divider()
                Button("Paste as Markdown") { send(#selector(WritingTextView.pasteAsMarkdown(_:))) }.keyboardShortcut("v", modifiers: [.command, .control])
            }
        }
        Window("Sentence Structure", id: "sentence-options") { SentenceOptions() }
            .windowResizability(.contentSize)
        Window("Markdown Cheat Sheet", id: "markdown-cheat-sheet") { MarkdownCheatSheet() }
            .windowResizability(.contentMinSize)
        Settings { PreferencesView(updater: updater).environmentObject(browser) }
    }
    private func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}

struct WritingView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @EnvironmentObject private var browser: FolderBrowser
    @AppStorage("reviewProse") private var review = true
    @AppStorage("reviewWords") private var words = Prose.defaultWords
    @AppStorage("fontSize") private var fontSize = 19.0
    @AppStorage("fontFamily") private var fontFamily = "Charter"
    @AppStorage("lineSpacing") private var lineSpacing = 0.28
    @AppStorage("pageWidth") private var pageWidth = 680.0
    @AppStorage("sessionGoal") private var sessionGoal = 500
    @AppStorage("showWritingDesk") private var sidebar = true
    @AppStorage("toolbarEdge") private var toolbarEdgeName = ToolbarEdge.top.rawValue
    @AppStorage("toolbarAutoHide") private var toolbarAutoHide = true
    @AppStorage("toolbarEnabled") private var toolbarEnabled = true
    @AppStorage("sidebarWidth") private var sidebarWidth = 270.0
    @State private var sidebarDragStart: Double?
    @State private var resizeCursorActive = false
    @State private var showToolbarOptions = false
    @StateObject private var commands = EditorCommands()
    @AppStorage("writingTheme") private var themeName = "graphite"
    @AppStorage("focusStyle") private var focusStyle = "gradient"
    @AppStorage("typewriterMode") private var typewriterMode = "room"
    @AppStorage("nameHighlights") private var nameHighlights = true
    @AppStorage("nameStyle") private var nameStyle = "shimmer"
    @AppStorage("nameCharacters") private var nameCharacters = true
    @AppStorage("nameLocations") private var nameLocations = true
    @AppStorage("nameLore") private var nameLore = true
    @StateObject private var cardIndex = SceneIndexModel()
    @AppStorage("editorZoom") private var zoom = 1.0
    @StateObject private var saveFeedback = SaveFeedback()
    @State private var needsSetup = false
    @State private var edited = false
    @State private var hasSavedFile = false
    private let savePoll = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()
    @State private var reading = false
    @Environment(\.openWindow) private var openWindow
    @AppStorage("syntaxClasses") private var syntaxClasses = 0
    @AppStorage("wordColorVersion") private var colorVersion = 0
    @AppStorage("spellCheckEnabled") private var spellCheckEnabled = true
    @State private var focus = false
    @State private var showStyle = false
    @State private var showHelp = false
    @State private var choosingFolder = false
    @State private var parallelURL: URL?
    @State private var pendingSwitchURL: URL?
    @State private var pendingParallelURL: URL?
    @State private var closeParallelRequest: UUID?
    @State private var startingWords: Int?
    @State private var bankedWords = 0
    @State private var activeURL: URL?
    @State private var openCards: [OpenCard] = []
    @State private var tagSceneSignal = 0
    @State private var exportSource: ExportSource?
    @State private var findRequest: FindRequest?
    @State private var revisionsRequest: RevisionsRequest?
    @AppStorage("autoSnapshots") private var autoSnapshots = true
    @State private var importMessage: String?
    @AppStorage("dimMarkers") private var dimMarkers = true
    @AppStorage("smartTypography") private var smartTypography = false
    @AppStorage("sceneTagsPlacement") private var sceneTagsPlacement = "bottom"
    @State private var errorMessage: String?

    private var count: Int { Prose.wordCount(document.text) }
    private var sessionWords: Int { bankedWords + max(0, count - (startingWords ?? count)) }
    private var colorScheme: ColorScheme? { WritingTheme.named(themeName).dark ? .dark : .light }

    var body: some View {
        workspace
            .frame(minWidth: (sidebar ? sidebarWidth + 440 : 560) + (parallelURL == nil ? 0 : 370), minHeight: 520)
            .preferredColorScheme(colorScheme)
            .tint(.gray)
            .onAppear(perform: prepareWorkspace)
            .sheet(isPresented: $needsSetup) { folderSetup }
            .sheet(isPresented: $showStyle) { writingStyleSheet }
            .focusedSceneValue(\.writingActions, writingActions)
            .background(WindowConfigurator())
            .onChange(of: document.text) { _, _ in saveFeedback.message = ""; edited = true }
            .onReceive(savePoll) { _ in updateSaveState() }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false, onCompletion: handleFolderImport)
            .alert("Could not open selection", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                writingDesk.frame(width: sidebarWidth).overlay(alignment: .trailing) { sidebarResizeHandle }
                Divider()
            }
            .offset(x: sidebar ? 0 : -(sidebarWidth + 1))
            .frame(width: sidebar ? sidebarWidth + 1 : 0, alignment: .leading)
            .clipped()
            .allowsHitTesting(sidebar)
            .accessibilityHidden(!sidebar)
            HSplitView {
                editorPanel.frame(minWidth: 420)
                parallelPane
            }
        }
        .animation(.smooth(duration: 0.3), value: sidebar)
    }

    /// A thin strip on the desk's edge; drag it to make the desk wider or narrower.
    private var sidebarResizeHandle: some View {
        Color.clear.frame(width: 8).contentShape(Rectangle())
            .onHover { inside in
                if inside && !resizeCursorActive { NSCursor.resizeLeftRight.push(); resizeCursorActive = true }
                else if !inside && resizeCursorActive { NSCursor.pop(); resizeCursorActive = false }
            }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global)
                .onChanged { drag in
                    let start = sidebarDragStart ?? sidebarWidth
                    sidebarDragStart = start
                    sidebarWidth = min(420, max(220, start + drag.translation.width))
                }
                .onEnded { _ in sidebarDragStart = nil })
    }

    private var writingDesk: some View {
        WritingSidebar(
            text: document.text,
            commands: commands,
            chooseFolder: { choosingFolder = true },
            currentURL: activeURL,
            switchFile: switchPrimaryDocument,
            showParallel: showParallelDocument,
            parallelURL: parallelURL,
            showCard: showCard,
            releaseCurrentDocument: releaseCurrentDocument,
            exportManuscript: startManuscriptExport,
            exportDocument: startDocumentExport,
            showRevisions: { startRevisions(saving: false) }
        )
    }

    @ViewBuilder
    private var parallelPane: some View {
        if let parallelURL {
            ParallelMarkdownPane(
                url: parallelURL,
                closeRequest: closeParallelRequest,
                close: closeParallelDocument,
                didClose: completeParallelClose,
                hostWindow: commands.editor?.window
            )
            .id(parallelURL)
        }
    }

    private var folderSetup: some View {
        WritingFolderSetup().environmentObject(browser)
    }

    private var writingStyleSheet: some View {
        VStack {
            Form { WritingStyleControls() }
            Button("Done") { showStyle = false }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var writingActions: WritingActions {
        WritingActions(
            reading: { reading.toggle() },
            focus: { focus.toggle() },
            style: { showStyle = true },
            sentences: { openWindow(id: "sentence-options") },
            tagScene: { tagSceneSignal += 1 },
            exportManuscript: startManuscriptExport,
            exportDocument: startDocumentExport,
            canExportManuscript: browser.projectURL != nil,
            findInProject: startFindInProject,
            importDocument: startImport,
            revisions: { startRevisions(saving: false) },
            saveSnapshot: { startRevisions(saving: true) }
        )
    }

    private var cardDock: some View {
        CardDock(cards: $openCards, reservedCorner: reservedSceneCorner, dimIdleCards: focus && !reading, writingRoot: browser.root, activeURL: activeURL, liveText: document.text,
                 onEditBeside: showParallelDocument,
                 onOpenInEditor: switchPrimaryDocument,
                 onSetField: setCardField,
                 onProblem: { errorMessage = $0 })
    }

    private var sceneLayer: some View {
        SceneTagsLayer(activeURL: activeURL, liveText: document.text, editSignal: tagSceneSignal, focusDim: focus && !reading,
                       openCard: showCard, setTags: setSceneTags, createCard: createSceneCard, index: cardIndex)
    }

    /// Cards stack clear of the scene strip when it sits in a corner.
    private var reservedSceneCorner: CardCorner? {
        guard browser.projectURL != nil else { return nil }
        switch sceneTagsPlacement {
        case "topLeading": return .topLeading
        case "topTrailing": return .topTrailing
        case "bottomLeading": return .bottomLeading
        case "bottomTrailing": return .bottomTrailing
        default: return nil
        }
    }

    /// Scene tags are edited in the open chapter itself, so they undo like any other change and never race the file on disk.
    private func setSceneTags(_ kind: CardKind, _ names: [String]) {
        document.text = SceneTags.setting(names, for: kind, in: document.text)
    }

    /// A tag with no card yet: create the card. Nothing opens, so you stay in the chapter; the chip simply becomes solid.
    private func createSceneCard(_ kind: CardKind, _ name: String) {
        let item: NewProjectItem
        switch kind { case .character: item = .character; case .location: item = .location; case .lore: item = .lore }
        do { try browser.createProjectItem(item, named: name) } catch { errorMessage = error.localizedDescription }
    }

    /// Opens the export sheet for the whole manuscript. A chapter that's open with unsaved changes is exported as it stands on screen.
    private func startManuscriptExport() {
        guard let projectURL = browser.projectURL else { return }
        var unsaved: [String: String] = [:]
        if let url = activeURL, browser.isChapter(url) { unsaved[url.lastPathComponent] = document.text }
        exportSource = .manuscript(project: projectURL, title: browser.project?.title ?? projectURL.lastPathComponent, unsaved: unsaved)
    }

    /// What revisions look at: every chapter of a Fiction Project, or the document that is open.
    private func revisionScope() -> RevisionScope? {
        if let project = browser.projectURL {
            let files = ProjectSearch.markdownFiles(in: FictionProject.folder(for: .chapter, in: project))
            return RevisionScope(root: project, files: files, chapterOrder: browser.project?.chapterOrder, isProject: true, openURL: activeURL, openText: document.text)
        }
        guard let url = activeURL else { return nil }
        let rootPath = browser.root?.standardizedFileURL.path
        let root = rootPath.flatMap { url.standardizedFileURL.path.hasPrefix($0 + "/") ? browser.root : nil } ?? url.deletingLastPathComponent()
        return RevisionScope(root: root, files: [url], chapterOrder: nil, isProject: false, openURL: url, openText: document.text)
    }

    private func startRevisions(saving: Bool) {
        guard let scope = revisionScope() else {
            importMessage = "Save this document first; revisions keep copies of files, and this one isn't a file yet."
            return
        }
        revisionsRequest = RevisionsRequest(scope: scope, saving: saving)
    }

    /// Once a day, when the manuscript has changed, keeps a snapshot without being asked.
    private func takeDailySnapshot() async {
        guard autoSnapshots, browser.projectURL != nil, let scope = revisionScope() else { return }
        let root = scope.root, files = scope.files, order = scope.chapterOrder
        _ = await Task.detached(priority: .utility) { Revisions.automaticIfDue(root: root, files: files, chapterOrder: order) }.value
    }

    /// Opens Find & Replace across the Fiction Project, or the writing folder outside one.
    private func startFindInProject() {
        guard let root = browser.projectURL ?? browser.root else {
            importMessage = "Choose a writing folder first; Find & Replace looks through every Markdown file in it."
            return
        }
        findRequest = FindRequest(root: root, openURL: activeURL, openText: document.text)
    }

    private func openSearchHit(_ url: URL, _ range: NSRange) {
        findRequest = nil
        if url.standardizedFileURL == activeURL?.standardizedFileURL {
            commands.jump(to: range)
        } else {
            commands.switchTo(url) { error in
                errorMessage = error?.localizedDescription
                if error == nil { DispatchQueue.main.async { commands.jump(to: range) } }
            }
        }
    }

    /// Turns a Word, Google Docs, RTF, OpenDocument, or web page file into a new Markdown file and opens it.
    private func startImport() {
        let panel = NSOpenPanel()
        panel.title = "Import a Document"
        panel.message = "Choose a Word, RTF, OpenDocument, HTML, or text file. A Markdown copy is added to your writing folder; the original isn't changed."
        panel.prompt = "Import"
        panel.allowedContentTypes = RichTextMarkdown.importTypes.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let source = panel.url else { return }
        do {
            let markdown = try RichTextMarkdown.importDocument(at: source)
            let folder = browser.projectURL.map { FictionProject.folder(for: .chapter, in: $0) } ?? browser.current ?? browser.root
                ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = try DocumentImport.write(markdown, named: source, in: folder)
            browser.reload()
            commands.switchTo(destination) { errorMessage = $0?.localizedDescription }
        } catch {
            importMessage = "Could not import “\(source.lastPathComponent)”: \(error.localizedDescription)"
        }
    }

    private func startDocumentExport() {
        let name = activeURL?.deletingPathExtension().lastPathComponent ?? "Untitled"
        exportSource = .document(title: name, markdown: document.text)
    }

    /// Empties the editor so the file it has open can be moved to the Trash.
    private func releaseCurrentDocument() {
        guard let source = commands.editor?.window?.windowController?.document as? NSDocument else { return }
        SingleDocumentCoordinator.shared.detach(source, using: commands)
    }

    /// Shows a file as a floating card, or brings its card forward if it's already open.
    private func showCard(_ url: URL) {
        if let index = openCards.firstIndex(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            openCards[index].pinned = true
            return
        }
        // Spread new cards across the top corners first so they don't pile up.
        let loads = Dictionary(grouping: openCards, by: \.corner).mapValues(\.count)
        let corner = [CardCorner.topTrailing, .topLeading, .bottomTrailing, .bottomLeading].min { (loads[$0] ?? 0) < (loads[$1] ?? 0) } ?? .topTrailing
        withAnimation(.smooth) { openCards.append(OpenCard(url: url, corner: corner)) }
    }

    /// Edits one front-matter field. When the card's file is the open document the change goes through the
    /// document itself, so it can be undone and never fights the editor over the file on disk.
    private func setCardField(_ key: String, _ value: String, _ url: URL) {
        if activeURL?.standardizedFileURL == url.standardizedFileURL {
            document.text = FrontMatter.setting(key, to: value, in: document.text)
        } else {
            do { try CardStore.setField(key, to: value, in: url) } catch { errorMessage = error.localizedDescription }
        }
    }

    private var toolbarEdge: ToolbarEdge { ToolbarEdge(rawValue: toolbarEdgeName) ?? .top }

    private var hoverToolbar: some View {
        let edge = toolbarEdge
        return HoverToolbar(edge: edge, enabled: toolbarEnabled, autoHide: toolbarAutoHide, keepOpen: showToolbarOptions) {
            AnyLayout(edge.vertical ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 2))) {
                BarButton(icon: "sidebar.left", label: "Writing desk", detail: "Show or hide your files and outline.", shortcut: "⌃⌘S", active: sidebar) { sidebar.toggle() }
                barDivider
                BarButton(icon: reading ? "pencil" : "play", label: reading ? "Edit" : "Reading mode",
                          detail: reading ? "Go back to writing." : "Read your work with the Markdown marks hidden.", shortcut: "⇧⌘R") { reading.toggle() }
                BarButton(icon: "bold", label: "Bold", detail: "Make the selected words bold.", shortcut: "⌘B") { commands.format(#selector(WritingTextView.markBold(_:))) }.disabled(reading)
                BarButton(icon: "italic", label: "Italic", detail: "Italicize the selected words.", shortcut: "⌘I") { commands.format(#selector(WritingTextView.markItalic(_:))) }.disabled(reading)
                BarButton(icon: "link", label: "Link", detail: "Turn the selection into a link.", shortcut: "⌘K") { commands.format(#selector(WritingTextView.markLink(_:))) }.disabled(reading)
                BarButton(icon: "textformat", label: "Writing style", detail: "Change the font, size, theme, and page width.", shortcut: "⌥⌘,") { showStyle.toggle() }
                barDivider
                BarButton(icon: "scope", label: "Paragraph focus", detail: "Fade everything except the paragraph you’re writing.", shortcut: "⇧⌘F", active: focus) { focus.toggle() }.disabled(reading)
                BarButton(icon: "text.magnifyingglass", label: "Sentence colors", detail: "Color nouns, verbs, and other parts of speech.", shortcut: "⌥⌘J") { openWindow(id: "sentence-options") }
                barDivider
                BarButton(icon: "text.badge.checkmark", label: "Prose suggestions", detail: "Strike through words you might cut. Your text never changes.", active: review) { review.toggle() }
                BarButton(icon: "textformat.abc", label: "Spelling & grammar", detail: "Check spelling and grammar as you type.", active: spellCheckEnabled) { spellCheckEnabled.toggle() }.disabled(reading)
                barDivider
                BarButton(icon: "ellipsis", label: "Toolbar options", detail: "Move, hide, or turn off this toolbar.", shortcut: "⌥⌘T", active: showToolbarOptions) { showToolbarOptions.toggle() }
                    .popover(isPresented: $showToolbarOptions) { toolbarOptions }
            }
        }
    }

    private var toolbarOptions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Toolbar").font(.headline)
            Toggle("Show toolbar", isOn: $toolbarEnabled)
            Picker("Position", selection: $toolbarEdgeName) {
                ForEach(ToolbarEdge.allCases, id: \.rawValue) { Text($0.title).tag($0.rawValue) }
            }.pickerStyle(.segmented).labelsHidden().disabled(!toolbarEnabled)
            Toggle("Hide when not in use", isOn: $toolbarAutoHide).disabled(!toolbarEnabled)
            Text(!toolbarEnabled ? "The toolbar is off. Every action is still in the menus. Bring it back with ⌥⌘T."
                 : toolbarAutoHide ? "Move the pointer near the \(toolbarEdge.rawValue) edge to bring it back."
                 : "The toolbar stays put and the page makes room for it.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 260)
    }

    /// A fixed-size rule. SwiftUI's Divider stretches across a horizontal custom layout, which made the top bar full width.
    private var barDivider: some View {
        Rectangle().fill(.separator)
            .frame(width: toolbarEdge.vertical ? 22 : 1, height: toolbarEdge.vertical ? 1 : 20)
            .padding(toolbarEdge.vertical ? .vertical : .horizontal, 5)
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func prepareWorkspace() {
        if startingWords == nil { startingWords = count }
        needsSetup = browser.root == nil
        activeURL = fileURL
        if let fileURL { browser.enterProject(containing: fileURL) }
        let binding = $document
        commands.loadText = { text, url in
            bankedWords = sessionWords
            binding.wrappedValue.text = text
            startingWords = Prose.wordCount(text)
            saveFeedback.message = ""
            activeURL = url
            if let url { browser.enterProject(containing: url) }
            edited = false
            hasSavedFile = url != nil
        }
    }

    private func updateSaveState() {
        guard let native = commands.editor?.window?.windowController?.document as? NSDocument else { return }
        edited = native.isDocumentEdited
        hasSavedFile = native.fileURL != nil
        if activeURL != native.fileURL {
            activeURL = native.fileURL
            if let url = native.fileURL { browser.enterProject(containing: url) }
        }
        LaunchBehavior.remember(native.fileURL)
    }

    private func handleFolderImport(_ result: Result<[URL], Error>) {
        do {
            if let url = try result.get().first { try browser.choose(url) }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func switchPrimaryDocument(to url: URL) {
        if parallelURL != nil {
            pendingSwitchURL = url
            pendingParallelURL = nil
            closeParallelRequest = UUID()
        } else {
            commands.switchTo(url) { errorMessage = $0?.localizedDescription }
        }
    }

    private func showParallelDocument(_ url: URL) {
        guard url.standardizedFileURL != fileURL?.standardizedFileURL else {
            errorMessage = "This file is already open for writing."
            return
        }
        guard parallelURL?.standardizedFileURL != url.standardizedFileURL else { return }
        if parallelURL == nil {
            parallelURL = url
        } else {
            pendingSwitchURL = nil
            pendingParallelURL = url
            closeParallelRequest = UUID()
        }
    }

    private func closeParallelDocument() {
        closeParallelRequest = nil
        parallelURL = nil
    }

    private func completeParallelClose() {
        closeParallelRequest = nil
        if let next = pendingParallelURL {
            pendingParallelURL = nil
            parallelURL = next
            return
        }
        guard let target = pendingSwitchURL else { return }
        pendingSwitchURL = nil
        commands.switchTo(target) { errorMessage = $0?.localizedDescription }
    }

    /// A pinned toolbar reserves its own strip so it never covers the page; an auto-hiding one floats above it.
    private var editorPanel: some View {
        let edge = toolbarEdge
        let reserve: CGFloat = (toolbarAutoHide || !toolbarEnabled) ? 0 : 68
        return editorColumn
            .padding(.top, edge == .top ? reserve : 0)
            .padding(.leading, edge == .left ? reserve : 0)
            .padding(.trailing, edge == .right ? reserve : 0)
            .overlay { cardDock }
            .overlay { hoverToolbar }
            .sheet(item: $exportSource) { source in ExportSheet(source: source, close: { exportSource = nil }) }
            .sheet(item: $findRequest) { request in
                FindReplaceSheet(request: request,
                                 replaceOpenText: { commands.editor?.replaceEntireText($0) },
                                 open: openSearchHit, filesChanged: { browser.reload() }, close: { findRequest = nil })
            }
            .sheet(item: $revisionsRequest) { request in
                RevisionsSheet(request: request,
                               replaceOpenText: { commands.editor?.replaceEntireText($0) },
                               filesChanged: { browser.reload() },
                               restoreOrder: { order in if let project = browser.projectURL { try? FictionProject.setChapterOrder(order, in: project); browser.reload() } },
                               close: { revisionsRequest = nil })
            }
            .task(id: browser.projectURL) { await takeDailySnapshot() }
            .alert("Import", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(importMessage ?? "") }
            .animation(.smooth(duration: 0.3), value: reserve)
            .animation(.smooth(duration: 0.3), value: edge)
    }

    private var editorColumn: some View {
        VStack(spacing: 0) {
            ZStack {
                NativeEditor(text: $document.text, review: review, words: words, fontSize: fontSize,
                             pageWidth: pageWidth, commands: commands, fontFamily: fontFamily,
                             lineSpacing: lineSpacing, focusParagraph: focus, focusGradient: focusStyle == "gradient", readOnly: reading, syntaxClasses: syntaxClasses,
                             colorVersion: colorVersion, spellCheckEnabled: spellCheckEnabled, typewriterMode: typewriterMode,
                             nameHighlighter: nameHighlights && browser.projectURL != nil ? cardIndex.highlighter : nil, nameShimmer: nameStyle == "shimmer",
                             nameKinds: Set(CardKind.allCases.filter { ($0 == .character && nameCharacters) || ($0 == .location && nameLocations) || ($0 == .lore && nameLore) }),
                             dimMarkers: dimMarkers, smartTypography: smartTypography,
                             saveAction: { saveFeedback.save(commands.editor?.window?.windowController?.document as? NSDocument) },
                             sidebarGesture: { sidebar.toggle() })
                    .opacity(reading ? 0 : 1).allowsHitTesting(!reading).accessibilityHidden(reading)
                if reading { ReadingView(text: document.text, family: fontFamily, size: fontSize, spacing: lineSpacing, width: pageWidth) }
                if let edge = WritingTheme.named(themeName).edgeColor { VignetteOverlay(color: edge) }
                sceneLayer
            }
            .onChange(of: reading) { _, value in
                if value { commands.editor?.window?.makeFirstResponder(nil) }
                else { commands.editor?.window?.makeFirstResponder(commands.editor) }
            }
            Divider().opacity(0.5)
            HStack(spacing: 12) {
                Text(commands.selectionWords > 0 ? "\(commands.selectionWords) of \(count) words selected" : "\(count) words")
                Text("\(Int(zoom * 100))%")
                Button { saveFeedback.save(commands.editor?.window?.windowController?.document as? NSDocument) } label: {
                    Text(saveFeedback.message.isEmpty ? (edited ? "Unsaved changes" : (hasSavedFile ? "Saved" : "Not saved yet")) : saveFeedback.message)
                }.buttonStyle(.plain).help("Save document (⌘S)")
                if sessionGoal > 0 { Text("\(sessionWords) / \(sessionGoal) this session").help("Net words added since this document window opened.") }
                Spacer(minLength: 0)
                if focus && !reading { Image(systemName: "scope").help("Paragraph focus is on") }
                if review && !reading { Text("\(Prose.suggestions(in: document.text, words: words).count) cuts") }
                Button { showHelp.toggle() } label: { Image(systemName: "questionmark.circle") }
                    .buttonStyle(.plain).accessibilityLabel("Writing shortcuts")
                    .popover(isPresented: $showHelp) {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Keep your hands on the story").font(.headline)
                            Text("⌘B bold · ⌘I italic · ⌘K link · ⇧⌘X strikethrough\n⇧⌘H heading · ⇧⌘8 bullets · ⇧⌘7 numbers · ⇧⌘L scene break · ⌘F find\nReturn continues a list; Tab indents it\nTab / Escape: move past closing markers\nReturn: leave formatting and start a new line\n⇧⌘F: paragraph focus · ⌃⌘S: writing desk")
                            Text("Click a file in the writing desk to switch to it; drag files and folders to rearrange them. Use the arrow keys to move through the list, Return to open, ⇧Return to rename, ⌘Delete to trash. Control-click for colors, pins, and more. A two-finger horizontal swipe shows or hides the desk.")
                            Text("Visual styles, focus dimming, and prose suggestions never change your saved Markdown.").foregroundStyle(.secondary)
                        }.padding(22).frame(width: 370)
                    }
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 12)
            .background(WritingTheme.named(themeName).chromeColor)
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var updater: AppUpdater
    @AppStorage("reviewWords") private var words = Prose.defaultWords
    @AppStorage("fontSize") private var fontSize = 19.0
    @AppStorage("pageWidth") private var pageWidth = 680.0
    @AppStorage("sessionGoal") private var sessionGoal = 500
    @AppStorage("autoSnapshots") private var autoSnapshots = true
    @EnvironmentObject private var browser: FolderBrowser
    @State private var confirmGuide = false
    @State private var guideMessage: String?
    var body: some View {
        TabView {
            Form {
                UpdateSettings(updater: updater)
                Section("Revisions") {
                    Toggle("Keep a daily snapshot of my manuscript", isOn: $autoSnapshots)
                    Text("In a Fiction Project, Sable saves a copy of your chapters once a day if anything changed, and keeps the newest 20. Snapshots you save yourself are never removed. Find them under File → Revision History.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("Writing goal") {
                    Stepper("Session goal: \(sessionGoal) words", value: $sessionGoal, in: 0...10000, step: 100)
                    Text("Set the goal to 0 to hide it.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Sable Guide") {
                    Button("Regenerate Guide…") { regenerateGuide() }
                    if let guideMessage { Text(guideMessage).font(.caption).foregroundStyle(.secondary) }
                    else { Text("Adds a fresh copy of the Markdown guide to your writing folder.").font(.caption).foregroundStyle(.secondary) }
                }
                .confirmationDialog("A guide is already in your writing folder.", isPresented: $confirmGuide) {
                    Button("Replace It", role: .destructive) { writeGuide(replacing: true) }
                    Button("Keep Both") { writeGuide(replacing: false) }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("Replacing it discards any changes you made to that file. Keep Both saves the new copy with a number.") }
            }
            .formStyle(.grouped)
            .tabItem { Label("General", systemImage: "gearshape") }

            Form { WritingStyleControls() }
                .formStyle(.grouped)
                .tabItem { Label("Writing", systemImage: "textformat") }

            ScrollView { SentenceOptions().frame(maxWidth: .infinity) }
                .tabItem { Label("Highlights", systemImage: "highlighter") }

            Form {
                Section("Words and phrases to consider cutting") {
                    TextEditor(text: $words).font(.body).frame(height: 160)
                    Text("Separate entries with commas. These are style suggestions; dialogue and narrative voice may need them.")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Restore default words") { words = Prose.defaultWords }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("Review", systemImage: "scissors") }
        }
        .frame(width: 560, height: 520)
    }

    private var guideFolder: URL {
        browser.root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sable Markdown Writer")
    }

    private func regenerateGuide() {
        if Tutorial.guideExists(in: guideFolder) { confirmGuide = true } else { writeGuide(replacing: false) }
    }

    private func writeGuide(replacing: Bool) {
        do {
            let url = try Tutorial.regenerate(in: guideFolder, replacing: replacing)
            guideMessage = "Saved “\(url.lastPathComponent)” in \(guideFolder.lastPathComponent)."
            browser.reload()
        } catch { guideMessage = "Could not write the guide: \(error.localizedDescription)" }
    }
}

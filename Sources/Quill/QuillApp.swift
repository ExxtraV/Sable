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
    #if QUILL_PREVIEW
    init() {
        let previewBrowser = FolderBrowser()
        if let folder = Bundle.main.resourceURL?.appendingPathComponent("Examples") {
            try? previewBrowser.choose(folder)
        }
        _browser = StateObject(wrappedValue: previewBrowser)
    }
    #endif
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
                Button("Leave Formatting") { send(#selector(WritingTextView.exitFormatting(_:))) }.keyboardShortcut("\\", modifiers: [.command])
                Divider()
                Button("Heading") { send(#selector(WritingTextView.markHeading(_:))) }.keyboardShortcut("h", modifiers: [.command, .shift])
            }
        }
        Window("Sentence Structure", id: "sentence-options") { SentenceOptions() }
            .windowResizability(.contentSize)
        Settings { PreferencesView(updater: updater) }
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
    @StateObject private var commands = EditorCommands()
    @AppStorage("writingTheme") private var themeName = "graphite"
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
    @State private var errorMessage: String?

    private var count: Int { Prose.wordCount(document.text) }
    private var sessionWords: Int { max(0, count - (startingWords ?? count)) }
    private var colorScheme: ColorScheme? { WritingTheme.named(themeName).dark ? .dark : .light }

    var body: some View {
        workspace
            .frame(minWidth: (sidebar ? 710 : 560) + (parallelURL == nil ? 0 : 370), minHeight: 520)
            .preferredColorScheme(colorScheme)
            .tint(.gray)
            .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
            .toolbarBackground(.visible, for: .windowToolbar)
            .onAppear(perform: prepareWorkspace)
            .sheet(isPresented: $needsSetup) { folderSetup }
            .sheet(isPresented: $showStyle) { writingStyleSheet }
            .focusedSceneValue(\.writingActions, writingActions)
            .background(ToolbarHoverTracker())
            .onChange(of: document.text) { _, _ in saveFeedback.message = ""; edited = true }
            .onReceive(savePoll) { _ in updateSaveState() }
            .toolbar { toolbarItems }
            .fileImporter(isPresented: $choosingFolder, allowedContentTypes: [.folder], allowsMultipleSelection: false, onCompletion: handleFolderImport)
            .alert("Could not open selection", isPresented: errorPresented) {
                Button("OK") { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
    }

    private var workspace: some View {
        HStack(spacing: 0) {
            if sidebar {
                writingDesk.frame(width: 270)
                Divider()
            }
            HSplitView {
                editorPanel.frame(minWidth: 420)
                parallelPane
            }
        }
    }

    private var writingDesk: some View {
        WritingSidebar(
            text: document.text,
            commands: commands,
            chooseFolder: { choosingFolder = true },
            currentURL: fileURL,
            switchFile: switchPrimaryDocument,
            showParallel: showParallelDocument
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
            sentences: { openWindow(id: "sentence-options") }
        )
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
            ToolbarItem(placement: .navigation) {
                Button { sidebar.toggle() } label: { Label("Writing desk", systemImage: "sidebar.left") }
                    .help("Show or hide the writing desk (⌃⌘S)")
            }
            ToolbarItemGroup {
                Button { reading.toggle() } label: { Image(systemName: reading ? "pencil" : "play") }
                    .help(reading ? "Return to editing" : "Reading mode — hide Markdown marks")
                    .accessibilityLabel(reading ? "Edit manuscript" : "Reading mode")
                Button { commands.format(#selector(WritingTextView.markBold(_:))) } label: { Image(systemName: "bold") }
                    .help("Bold (⌘B)").accessibilityLabel("Bold").disabled(reading)
                Button { commands.format(#selector(WritingTextView.markItalic(_:))) } label: { Image(systemName: "italic") }
                    .help("Italic (⌘I)").accessibilityLabel("Italic").disabled(reading)
                Button { commands.format(#selector(WritingTextView.markLink(_:))) } label: { Image(systemName: "link") }
                    .help("Link (⌘K)").accessibilityLabel("Link").disabled(reading)
                Button { showStyle.toggle() } label: { Image(systemName: "textformat") }
                    .help("Fonts and writing style").accessibilityLabel("Writing style")

                Toggle(isOn: $focus) { Label("Paragraph focus", systemImage: "scope") }
                    .help("Dim everything outside the current paragraph (⇧⌘F)").disabled(reading)
                Button { openWindow(id: "sentence-options") } label: { Image(systemName: "text.magnifyingglass") }
                    .help("Color parts of speech").accessibilityLabel("Sentence structure")

                Toggle(isOn: $review) { Label("Prose suggestions", systemImage: "text.badge.checkmark") }
                    .help("Show possible cuts without changing your manuscript")
                Toggle(isOn: $spellCheckEnabled) { Label("Spelling & grammar", systemImage: "textformat.abc") }
                    .help("Turn off spelling and grammar checking — handy for distraction-free first drafts").disabled(reading)
            }
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private func prepareWorkspace() {
        if startingWords == nil { startingWords = count }
        needsSetup = browser.root == nil
    }

    private func updateSaveState() {
        guard let native = commands.editor?.window?.windowController?.document as? NSDocument else { return }
        edited = native.isDocumentEdited
        hasSavedFile = native.fileURL != nil
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

    private var editorPanel: some View {
        VStack(spacing: 0) {
            ZStack {
                NativeEditor(text: $document.text, review: review, words: words, fontSize: fontSize,
                             pageWidth: pageWidth, commands: commands, fontFamily: fontFamily,
                             lineSpacing: lineSpacing, focusParagraph: focus, readOnly: reading, syntaxClasses: syntaxClasses,
                             colorVersion: colorVersion, spellCheckEnabled: spellCheckEnabled,
                             saveAction: { saveFeedback.save(commands.editor?.window?.windowController?.document as? NSDocument) },
                             sidebarGesture: { sidebar.toggle() })
                    .opacity(reading ? 0 : 1).allowsHitTesting(!reading).accessibilityHidden(reading)
                if reading { ReadingView(text: document.text, family: fontFamily, size: fontSize, spacing: lineSpacing, width: pageWidth) }
            }
            .onChange(of: reading) { _, value in
                if value { commands.editor?.window?.makeFirstResponder(nil) }
                else { commands.editor?.window?.makeFirstResponder(commands.editor) }
            }
            Divider()
            HStack(spacing: 12) {
                Text("\(count) words")
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
                            Text("⌘B bold · ⌘I italic · ⌘K link\n⇧⌘H heading · ⌘F find\nTab / Escape: move past closing markers\nReturn: leave formatting and start a new line\n⇧⌘F: paragraph focus · ⌃⌘S: writing desk")
                            Text("Click a file in the writing desk to switch to it. Control-click a file to open it beside your current document. A two-finger horizontal swipe also shows or hides the writing desk. Outline options let you name and filter your headings.")
                            Text("Visual styles, focus dimming, and prose suggestions never change your saved Markdown.").foregroundStyle(.secondary)
                        }.padding(22).frame(width: 370)
                    }
            }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 18).padding(.vertical, 12)
        }
    }
}

struct PreferencesView: View {
    @ObservedObject var updater: AppUpdater
    @AppStorage("reviewWords") private var words = Prose.defaultWords
    @AppStorage("fontSize") private var fontSize = 19.0
    @AppStorage("pageWidth") private var pageWidth = 680.0
    @AppStorage("sessionGoal") private var sessionGoal = 500
    var body: some View {
        Form {
            UpdateSettings(updater: updater)
            WritingStyleControls()
            Stepper("Session goal: \(sessionGoal) words", value: $sessionGoal, in: 0...10000, step: 100)
            Text("Set the goal to 0 to hide it.").font(.caption).foregroundStyle(.secondary)
            Text("Words and phrases to consider cutting").font(.headline)
            TextEditor(text: $words).font(.body).frame(height: 110)
            Text("Separate entries with commas. These are style suggestions; dialogue and narrative voice may need them.")
                .font(.caption).foregroundStyle(.secondary)
            Button("Restore default words") { words = Prose.defaultWords }
        }.padding(24).frame(width: 450)
    }
}

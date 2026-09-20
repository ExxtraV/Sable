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
    @StateObject private var updater = AppUpdater()
    @StateObject private var library = WorldLibrary()
    @StateObject private var browser = FolderBrowser()
    #if QUILL_PREVIEW
    init() {
        let previewLibrary = WorldLibrary()
        let previewBrowser = FolderBrowser()
        if let folder = Bundle.main.resourceURL?.appendingPathComponent("Examples") {
            try? previewBrowser.choose(folder)
            try? previewLibrary.add([folder.appendingPathComponent("Northwatch.md")])
        }
        _library = StateObject(wrappedValue: previewLibrary)
        _browser = StateObject(wrappedValue: previewBrowser)
    }
    #endif
    var body: some Scene {
        DocumentGroup(newDocument: MarkdownDocument()) { file in
            WritingView(document: file.$document, fileURL: file.fileURL)
                .environmentObject(library)
                .environmentObject(browser)
        }
        .commands {
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
        Settings { PreferencesView(updater: updater) }
    }
    private func send(_ selector: Selector) {
        NSApp.sendAction(selector, to: nil, from: nil)
    }
}

struct WritingView: View {
    @Binding var document: MarkdownDocument
    let fileURL: URL?
    @EnvironmentObject private var library: WorldLibrary
    @EnvironmentObject private var browser: FolderBrowser
    @AppStorage("reviewProse") private var review = true
    @AppStorage("reviewWords") private var words = Prose.defaultWords
    @AppStorage("fontSize") private var fontSize = 19.0
    @AppStorage("fontFamily") private var fontFamily = "Charter"
    @AppStorage("lineSpacing") private var lineSpacing = 0.28
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("pageWidth") private var pageWidth = 680.0
    @AppStorage("sessionGoal") private var sessionGoal = 500
    @AppStorage("showWritingDesk") private var sidebar = true
    @StateObject private var commands = EditorCommands()
    @State private var reading = false
    @State private var sentenceOptions = false
    @AppStorage("syntaxClasses") private var syntaxClasses = 0
    @AppStorage("wordColorVersion") private var colorVersion = 0
    @AppStorage("spellCheckEnabled") private var spellCheckEnabled = true
    @State private var focus = false
    @State private var showStyle = false
    @State private var showHelp = false
    @State private var importing = false
    @State private var choosingFolder = false
    @State private var reference: WorldDocument?
    @State private var startingWords: Int?
    @State private var errorMessage: String?

    private var count: Int { Prose.wordCount(document.text) }
    private var sessionWords: Int { max(0, count - (startingWords ?? count)) }
    private var colorScheme: ColorScheme? { appearance == "system" ? nil : (appearance == "light" ? .light : .dark) }

    var body: some View {
        HStack(spacing: 0) {
            if sidebar {
                WorldSidebar(text: document.text, commands: commands,
                    addFiles: { choosingFolder = false; importing = true },
                    chooseFolder: { choosingFolder = true; importing = true },
                    currentURL: fileURL, showBeside: { reference = $0 })
                    .frame(width: 270)
                Divider()
            }
            HSplitView {
                editorPanel.frame(minWidth: 420)
                if let item = reference {
                    ReferencePane(item: item, openToEdit: {
                        do { commands.openInTab(try item.resolve()) { errorMessage = $0?.localizedDescription } }
                        catch { errorMessage = error.localizedDescription }
                    }, close: { reference = nil }, hostWindow: commands.editor?.window)
                    .id(item.id)
                }
            }
        }
        .frame(minWidth: (sidebar ? 710 : 560) + (reference == nil ? 0 : 370), minHeight: 520)
        .preferredColorScheme(colorScheme)
        .tint(.gray)
        .toolbarBackground(Color(nsColor: .windowBackgroundColor), for: .windowToolbar)
        .toolbarBackground(.visible, for: .windowToolbar)
        .onAppear { if startingWords == nil { startingWords = count } }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button { sidebar.toggle() } label: { Label("Writing desk", systemImage: "sidebar.left") }
                    .keyboardShortcut("s", modifiers: [.command, .control])
                    .help("Show or hide the writing desk (⌃⌘S)")
            }
            ToolbarItemGroup {
                Button { reading.toggle() } label: { Image(systemName: reading ? "pencil" : "play") }
                    .help(reading ? "Return to editing" : "Reading mode — hide Markdown marks")
                    .accessibilityLabel(reading ? "Edit manuscript" : "Reading mode")
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                Button { commands.format(#selector(WritingTextView.markBold(_:))) } label: { Image(systemName: "bold") }
                    .help("Bold (⌘B)").accessibilityLabel("Bold").disabled(reading)
                Button { commands.format(#selector(WritingTextView.markItalic(_:))) } label: { Image(systemName: "italic") }
                    .help("Italic (⌘I)").accessibilityLabel("Italic").disabled(reading)
                Button { commands.format(#selector(WritingTextView.markLink(_:))) } label: { Image(systemName: "link") }
                    .help("Link (⌘K)").accessibilityLabel("Link").disabled(reading)
                Button { showStyle.toggle() } label: { Image(systemName: "textformat") }
                    .help("Fonts and writing style").accessibilityLabel("Writing style")
                    .popover(isPresented: $showStyle) {
                        Form { WritingStyleControls() }.padding(20).frame(width: 380)
                    }
                Toggle(isOn: $focus) { Label("Paragraph focus", systemImage: "scope") }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                    .help("Dim everything outside the current paragraph (⇧⌘F)").disabled(reading)
                Button { sentenceOptions.toggle() } label: { Image(systemName: "text.magnifyingglass") }
                    .help("Color parts of speech").accessibilityLabel("Sentence structure")
                    .popover(isPresented: $sentenceOptions) { SentenceOptions() }
                Toggle(isOn: $review) { Label("Prose suggestions", systemImage: "text.badge.checkmark") }
                    .help("Show possible cuts without changing your manuscript")
                Toggle(isOn: $spellCheckEnabled) { Label("Spelling & grammar", systemImage: "textformat.abc") }
                    .help("Turn off spelling and grammar checking — handy for distraction-free first drafts").disabled(reading)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: choosingFolder ? [.folder] : [.markdownDocument, .plainText], allowsMultipleSelection: !choosingFolder) { result in
            do {
                let urls = try result.get()
                if choosingFolder { if let url = urls.first { try browser.choose(url) } }
                else { try library.add(urls) }
            } catch { errorMessage = error.localizedDescription }
        }
        .alert("Could not open selection", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private var editorPanel: some View {
        VStack(spacing: 0) {
            ZStack {
                NativeEditor(text: $document.text, review: review, words: words, fontSize: fontSize,
                             pageWidth: pageWidth, commands: commands, fontFamily: fontFamily,
                             lineSpacing: lineSpacing, focusParagraph: focus, readOnly: reading, syntaxClasses: syntaxClasses,
                             colorVersion: colorVersion, spellCheckEnabled: spellCheckEnabled)
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
                            Text("Use the Files menu to choose a writing folder. Files open in tabs so each draft keeps its edits. World documents can be read beside the manuscript with the split-view button. Outline options let you name and filter your headings.")
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

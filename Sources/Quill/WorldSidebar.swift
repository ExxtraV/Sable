import SwiftUI
import QuillCore

/// The writing desk deliberately stays small: one thing at a time. Files and the outline
/// live on separate tabs, so a long file list never buries your headings.
struct WritingSidebar: View {
    let text: String
    let commands: EditorCommands
    let chooseFolder: () -> Void
    let currentURL: URL?
    let switchFile: (URL) -> Void
    let showParallel: (URL) -> Void
    var parallelURL: URL? = nil
    @EnvironmentObject private var browser: FolderBrowser
    @AppStorage("outlineTitle") private var outlineTitle = "Outline"
    @AppStorage("outlineLevel") private var outlineLevel = 0
    @AppStorage("sidebarTab") private var tab = "files"
    @State private var showOutlineOptions = false
    @State private var showViewOptions = false
    @State private var search = ""

    private var chapters: [ChapterHeading] {
        MarkdownSyntax.headings(in: text).filter { outlineLevel == 0 || $0.level == outlineLevel }
    }
    private var outlineName: String {
        let trimmed = outlineTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Outline" : trimmed
    }
    private var showingFiles: Bool { tab != "outline" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Picker("Writing desk section", selection: $tab) {
                    Text("Files").tag("files")
                    Text(outlineName).tag("outline")
                }.pickerStyle(.segmented).labelsHidden()
                Button {
                    if showingFiles { showViewOptions.toggle() } else { showOutlineOptions.toggle() }
                } label: { Image(systemName: "slider.horizontal.3").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).help(showingFiles ? "Sort, layout, and color labels" : "Name and filter your outline")
                    .accessibilityLabel(showingFiles ? "File list options" : "Outline options")
                    .popover(isPresented: $showViewOptions, arrowEdge: .bottom) { SidebarOptions().environmentObject(browser) }
                    .popover(isPresented: $showOutlineOptions, arrowEdge: .bottom) { OutlineControls() }
            }.padding(.horizontal, 14).padding(.top, 14).padding(.bottom, 10)

            TextField(showingFiles ? "Search “\(browser.current?.lastPathComponent ?? "files")”" : "Search headings", text: $search)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 14).padding(.bottom, 10)

            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if showingFiles {
                            FolderBrowserSection(currentURL: currentURL, search: search, chooseFolder: chooseFolder,
                                switchFile: switchFile, showParallel: showParallel, parallelURL: parallelURL)
                        } else {
                            outline
                        }
                    }.padding(.horizontal, 12).padding(.bottom, 16)
                }
                .onChange(of: browser.selection) { _, url in if let url { proxy.scrollTo(url) } }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: tab) { _, _ in search = "" }
    }

    private var outline: some View {
        VStack(alignment: .leading, spacing: 2) {
            let shown = chapters.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) }
            if chapters.isEmpty {
                Text(outlineLevel == 0 ? "Add # headings to build your outline." : "No level \(outlineLevel) headings yet.")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            } else if shown.isEmpty {
                Text("No headings match.").font(.caption).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
            ForEach(shown) { heading in
                Button { commands.jump(to: heading.range) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(heading.title).font(.system(size: heading.level == 1 ? 13 : 12, weight: heading.level == 1 ? .medium : .regular)).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(min(heading.level - 1, 3)) * 12)
                    .padding(.vertical, 5).padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
            }
        }
    }
}

/// How the file list looks and sorts, plus the words you give each color.
struct SidebarOptions: View {
    @EnvironmentObject private var browser: FolderBrowser
    @AppStorage("sidebarCompact") private var compact = false
    @AppStorage("sidebarShowIcons") private var showIcons = true
    @AppStorage("sidebarShowExtensions") private var showExtensions = false
    @AppStorage("sidebarShowModified") private var showModified = false
    @AppStorage("sidebarShowWords") private var showWords = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("File list").font(.headline)
            VStack(alignment: .leading, spacing: 8) {
                Text("Sort by").font(.caption).foregroundStyle(.secondary)
                Picker("Sort by", selection: $browser.sort) {
                    ForEach(FileSort.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented).labelsHidden()
                Toggle("Folders first", isOn: $browser.foldersFirst)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Show").font(.caption).foregroundStyle(.secondary)
                Toggle("Icons", isOn: $showIcons)
                Toggle("File extensions", isOn: $showExtensions)
                Toggle("Last modified", isOn: $showModified)
                Toggle("Word count", isOn: $showWords)
                Toggle("Compact rows", isOn: $compact)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Color labels").font(.caption).foregroundStyle(.secondary)
                ForEach(MarkColor.allCases, id: \.self) { color in
                    HStack(spacing: 8) {
                        Circle().fill(color.color).frame(width: 10, height: 10)
                        TextField(color.name, text: Binding(get: { browser.colorLabels[color] ?? "" }, set: { browser.setLabel($0, for: color) }))
                            .textFieldStyle(.roundedBorder)
                    }
                }
                Text("Name what each color means to you, like Draft or Revised.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Reset Layout") {
                compact = false; showIcons = true; showExtensions = false; showModified = false; showWords = false
                browser.sort = .name; browser.foldersFirst = true
            }.controlSize(.small)
        }
        .toggleStyle(.checkbox)
        .padding(18).frame(width: 270)
    }
}

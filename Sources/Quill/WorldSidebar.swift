import SwiftUI
import QuillCore

/// The writing desk deliberately stays small: browse files, switch drafts, and
/// jump through headings. A second document is opened only in the split pane.
struct WritingSidebar: View {
    let text: String
    let commands: EditorCommands
    let chooseFolder: () -> Void
    let currentURL: URL?
    let switchFile: (URL) -> Void
    let showParallel: (URL) -> Void
    @AppStorage("outlineTitle") private var outlineTitle = "Outline"
    @AppStorage("outlineLevel") private var outlineLevel = 0
    @State private var showOutlineOptions = false
    @State private var search = ""
    private var chapters: [ChapterHeading] {
        MarkdownSyntax.headings(in: text).filter { outlineLevel == 0 || $0.level == outlineLevel }
    }
    private var title: String {
        outlineTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Outline" : outlineTitle
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("WRITING DESK").font(.system(size: 10, weight: .semibold, design: .rounded)).tracking(2)
                Spacer()
            }.foregroundStyle(.secondary).padding(18)
            TextField("Find files, headings, or notes", text: $search)
                .textFieldStyle(.roundedBorder).padding(.horizontal, 14).padding(.bottom, 12)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    FolderBrowserSection(currentURL: currentURL, search: search, chooseFolder: chooseFolder,
                        switchFile: switchFile, showParallel: showParallel)
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
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

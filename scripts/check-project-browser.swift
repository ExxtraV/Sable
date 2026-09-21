import Foundation

@main enum ProjectBrowserChecks {
    @MainActor static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("quill-project-browser-\(UUID())").standardizedFileURL
        try fm.createDirectory(at: root.appendingPathComponent("Loose Notes"), withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        // Isolate the browser's stored preferences from the developer's real ones.
        func same(_ a: URL?, _ b: URL?) -> Bool { a?.standardizedFileURL.path == b?.standardizedFileURL.path }
        let browser = FolderBrowser()
        try browser.choose(root)
        precondition(browser.projectURL == nil && same(browser.viewRoot, root))

        // Create a project from the library: the desk moves inside it.
        let project = try browser.createProject(named: "Saltmarsh", starterFiles: true).standardizedFileURL
        precondition(same(browser.projectURL, project) && browser.project?.title == "Saltmarsh")
        precondition(same(browser.viewRoot, project) && same(browser.current, project))
        precondition(browser.breadcrumbs.map(\.lastPathComponent) == ["Saltmarsh"], "The trail starts at the project, not above it")
        precondition(browser.canLeaveProject)
        do { _ = try browser.createProject(named: "Nested", starterFiles: false); preconditionFailure() } catch FictionProjectError.alreadyProject {}

        // Manuscript is always pinned and red by default, and only inside its own project
        let manuscript = project.appendingPathComponent("Manuscript")
        let characters = project.appendingPathComponent("Characters")
        precondition(browser.isManuscript(manuscript) && browser.isPinned(manuscript) && browser.color(of: manuscript) == .red)
        precondition(!browser.isManuscript(characters) && !browser.isPinned(characters) && browser.color(of: characters) == nil)
        browser.setColor(.blue, for: manuscript)
        precondition(browser.color(of: manuscript) == .blue, "A color you choose wins over the default")
        browser.setColor(nil, for: manuscript)
        precondition(browser.color(of: manuscript) == .red && browser.isPinned(manuscript))

        // The "+" on project folders: what each one adds, including folders nested inside them
        precondition(browser.projectItem(forFolder: manuscript) == .chapter)
        precondition(browser.projectItem(forFolder: characters) == .character)
        precondition(browser.projectItem(forFolder: project.appendingPathComponent("Locations")) == .location)
        precondition(browser.projectItem(forFolder: project.appendingPathComponent("World")) == .lore)
        precondition(browser.projectItem(forFolder: project.appendingPathComponent("Notes")) == nil && browser.projectItem(forFolder: project.appendingPathComponent("Images")) == nil)
        precondition(browser.projectItem(forFolder: project) == nil, "The project itself has no +")
        precondition(browser.projectItem(forFolder: root.appendingPathComponent("Loose Notes")) == nil, "Nor do folders outside it")
        let villains = characters.appendingPathComponent("Villains")
        try fm.createDirectory(at: villains, withIntermediateDirectories: true)
        precondition(browser.projectItem(forFolder: villains) == .character, "A folder inside Characters adds characters")
        let baron = try browser.createProjectItem(.character, named: "Baron Ash", in: villains)
        precondition(baron.deletingLastPathComponent().lastPathComponent == "Villains" && baron.lastPathComponent == "Baron Ash.md")
        let ninth = try browser.createProjectItem(.chapter, named: "Chapter 9", in: manuscript)
        precondition(ninth.deletingLastPathComponent().lastPathComponent == "Manuscript", "Chapters go straight into Manuscript")
        try fm.removeItem(at: ninth)   // keep the later chapter-order checks tidy
        do { _ = try browser.createProjectItem(.character, named: "Escape", in: root); preconditionFailure() } catch FolderMoveError.outsideRoot {}

        // Chapter order and goal are saved in the project, and a renamed chapter keeps its place
        precondition(browser.project?.chapterOrder == nil && browser.project?.wordGoal == nil)
        let second = try browser.createProjectItem(.chapter, named: "Chapter 2")
        try browser.setChapterOrder(["Chapter 2.md", "Chapter 1.md"])
        precondition(browser.project?.chapterOrder == ["Chapter 2.md", "Chapter 1.md"])
        precondition(FictionProject.load(project)?.chapterOrder == ["Chapter 2.md", "Chapter 1.md"], "Saved to disk, not just remembered")
        let opening = try browser.rename(BrowserEntry(url: second, isDirectory: false), to: "Opening")
        precondition(opening.lastPathComponent == "Opening.md" && browser.project?.chapterOrder == ["Opening.md", "Chapter 1.md"], "A renamed chapter keeps its slot")
        // Reordering from the Files tab shares the Manuscript tab's saved order
        let chapterOne = project.appendingPathComponent("Manuscript/Chapter 1.md")
        precondition(browser.isChapter(chapterOne) && browser.isChapter(opening) && !browser.isChapter(project.appendingPathComponent("Characters/Example Character.md")))
        precondition(!browser.isChapter(project.appendingPathComponent("Manuscript")), "The folder itself isn't a chapter")
        try browser.reorderChapter(chapterOne, onto: opening)
        precondition(browser.project?.chapterOrder == ["Chapter 1.md", "Opening.md"] && browser.chapterNames() == ["Chapter 1.md", "Opening.md"])
        try browser.moveChapter(opening, to: 0)
        precondition(browser.chapterNames() == ["Opening.md", "Chapter 1.md"])
        try browser.moveChapter(opening, to: 99)
        precondition(browser.chapterNames() == ["Chapter 1.md", "Opening.md"], "Out-of-range moves land at the end")
        try browser.moveChapter(opening, to: -4)
        precondition(browser.chapterNames() == ["Opening.md", "Chapter 1.md"], "…or the start")
        try browser.setWordGoal(80_000)
        precondition(browser.project?.wordGoal == 80_000)
        try browser.setWordGoal(nil)
        precondition(browser.project?.wordGoal == nil && browser.project?.chapterOrder != nil)

        // Selecting several items: ⌘-click toggles, ⇧-click and ⇧-arrows extend, ⌘A selects all
        let shownEntries = ["a", "b", "c", "d", "e"].map { BrowserEntry(url: root.appendingPathComponent("\($0).md"), isDirectory: false) }
        browser.recordDisplayed(shownEntries)
        let u = shownEntries.map(\.url)
        browser.click(u[0], command: false, shift: false)
        precondition(browser.selectedURLs == [u[0]] && browser.selection == u[0])
        browser.click(u[2], command: false, shift: true)
        precondition(browser.selectedURLs == Set(u[0...2]) && browser.selection == u[0], "Shift-click selects the range")
        browser.click(u[1], command: true, shift: false)
        precondition(browser.selectedURLs == [u[0], u[2]] && browser.selection == u[0], "Command-click removes one from the selection")
        browser.click(u[4], command: true, shift: false)
        precondition(browser.selectedURLs == [u[0], u[2], u[4]] && browser.selection == u[4], "…and adds one")
        browser.click(u[3], command: false, shift: false)
        precondition(browser.selectedURLs == [u[3]], "A plain click starts over")
        browser.extendSelection(by: 1)
        precondition(browser.selectedURLs == [u[3], u[4]], "Shift-down extends")
        browser.extendSelection(by: -1)
        precondition(browser.selectedURLs == [u[3]], "…and shift-up shrinks it back")
        browser.extendSelection(by: -1); browser.extendSelection(by: -1)
        precondition(browser.selectedURLs == Set(u[1...3]), "Extends upward from the anchor")
        precondition(browser.trashTargets(for: shownEntries[2]).map(\.url) == Array(u[1...3]), "Trashing an item in the selection trashes them all")
        precondition(browser.trashTargets(for: shownEntries[0]).map(\.url) == [u[0]], "Trashing an item outside it trashes just that item")
        precondition(browser.dragSet(for: [u[2]]) == Array(u[1...3]), "Dragging one of several selected items moves them all")
        precondition(browser.dragSet(for: [u[0]]) == [u[0]], "Dragging an unselected item moves just it")
        browser.selectAllDisplayed()
        precondition(browser.selectedURLs == Set(u))
        browser.selection = nil
        precondition(browser.selectedURLs.isEmpty)

        // Trashing several items at once, then Undo brings every one back
        let bulk = root.appendingPathComponent("Bulk \(UUID().uuidString.prefix(6))")
        try fm.createDirectory(at: bulk.appendingPathComponent("Folder"), withIntermediateDirectories: true)
        for name in ["One.md", "Two.md", "Three.md", "Folder/Inside.md"] { try Data(name.utf8).write(to: bulk.appendingPathComponent(name)) }
        let victims = ["One.md", "Two.md", "Three.md", "Folder", "Folder/Inside.md"].map { BrowserEntry(url: bulk.appendingPathComponent($0), isDirectory: $0 == "Folder") }
        do { try browser.trash(victims, protecting: [bulk.appendingPathComponent("Two.md")]); preconditionFailure() } catch FolderTrashError.inUse {}
        precondition(fm.fileExists(atPath: bulk.appendingPathComponent("One.md").path), "A blocked batch trashes nothing")
        try browser.trash(victims, protecting: [])
        for name in ["One.md", "Two.md", "Three.md", "Folder"] { precondition(!fm.fileExists(atPath: bulk.appendingPathComponent(name).path), name) }
        precondition(browser.lastTrashed?.items.count == 4 && browser.lastTrashed?.summary == "4 items", "A folder and the file inside it count once")
        try browser.undoTrash()
        for name in ["One.md", "Two.md", "Three.md", "Folder/Inside.md"] { precondition(fm.fileExists(atPath: bulk.appendingPathComponent(name).path), "\(name) is restored") }
        precondition(browser.lastTrashed == nil)
        // A place taken in the meantime keeps that item in the Trash and says so
        try browser.trash([victims[0]], protecting: [])
        precondition(browser.lastTrashed?.summary == "“One”")
        try Data("new".utf8).write(to: bulk.appendingPathComponent("One.md"))
        do { try browser.undoTrash(); preconditionFailure() } catch FolderTrashError.occupied {}
        if let stuck = browser.lastTrashed?.items.first { try? fm.removeItem(at: stuck.trashed) }   // tidy the test's own leftover

        // Inside a project the desk shows only that project.
        browser.navigate(root.appendingPathComponent("Loose Notes"))
        precondition(same(browser.current, project), "Can't wander out of a project by navigating")
        browser.up()
        precondition(same(browser.current, project), "Up stops at the project")
        browser.navigate(project.appendingPathComponent("Characters"))
        precondition(browser.breadcrumbs.map(\.lastPathComponent) == ["Saltmarsh", "Characters"])
        browser.up()
        precondition(same(browser.current, project))

        // Cards: kinds come from the folder, and only inside a project
        let example = BrowserEntry(url: project.appendingPathComponent("Characters/Example Character.md"), isDirectory: false)
        let chapter = BrowserEntry(url: project.appendingPathComponent("Manuscript/Chapter 1.md"), isDirectory: false)
        precondition(browser.cardKind(of: example) == .character && browser.cardKind(of: chapter) == nil)

        // New items land in the right folders
        let mara = try browser.createProjectItem(.character, named: "Mara")
        precondition(mara.deletingLastPathComponent().lastPathComponent == "Characters")

        precondition(!browser.canManageCategories, "Categories belong to the writing folder, not to a project")

        // Leaving is an explicit choice
        browser.leaveProject()
        precondition(browser.projectURL == nil && same(browser.current, root))
        precondition(browser.cardKind(of: example) == nil, "Outside a project nothing is a card")
        precondition(!browser.isManuscript(manuscript) && browser.color(of: manuscript) == nil && !browser.isPinned(manuscript), "Manuscript defaults apply only inside its project")

        // Categories: you make them in the writing folder, file folders under them, and they persist
        precondition(browser.canManageCategories)
        precondition(browser.addCategory(named: "School") && !browser.addCategory(named: "school") && !browser.addCategory(named: "  "))
        let categoryID = browser.categories.list[0].id
        let notes = root.appendingPathComponent("Loose Notes")
        browser.assign(notes, to: categoryID)
        precondition(browser.categoryID(of: BrowserEntry(url: notes, isDirectory: true)) == categoryID)
        precondition(browser.categoryID(of: BrowserEntry(url: project, isDirectory: true, isProject: true)) == nil, "Projects aren't filed under categories")
        precondition(browser.categoryID(of: BrowserEntry(url: notes, isDirectory: false)) == nil, "Only folders are")
        let relaunched = FolderBrowser()
        precondition(relaunched.categories == browser.categories, "Categories survive a relaunch")
        let archive = root.appendingPathComponent("Archive")
        try fm.createDirectory(at: archive, withIntermediateDirectories: true)
        try browser.move([notes], into: archive)
        let movedNotes = archive.appendingPathComponent("Loose Notes")
        precondition(browser.categoryID(of: BrowserEntry(url: movedNotes, isDirectory: true)) == categoryID, "A moved folder keeps its category")
        let renamedNotes = try browser.rename(BrowserEntry(url: movedNotes, isDirectory: true), to: "Term Papers")
        precondition(browser.categoryID(of: BrowserEntry(url: renamedNotes, isDirectory: true)) == categoryID, "…and a renamed one")
        browser.deleteCategory(categoryID)
        precondition(browser.categoryID(of: BrowserEntry(url: renamedNotes, isDirectory: true)) == nil && fm.fileExists(atPath: renamedNotes.path), "Deleting a category leaves the folders alone")

        // Opening a file in a project brings the desk into it, and only once
        browser.enterProject(containing: mara)
        precondition(same(browser.projectURL, project))
        browser.navigate(project.appendingPathComponent("World"))
        browser.enterProject(containing: mara)
        precondition(same(browser.projectURL, project))

        // Convert back: same files, plain folder
        let before = try fm.contentsOfDirectory(atPath: project.path).filter { $0 != FictionProject.markerName }.sorted()
        try browser.convertToRegularFolder(project)
        precondition(browser.projectURL == nil && !FictionProject.isProject(project))
        let after = try fm.contentsOfDirectory(atPath: project.path).sorted()
        precondition(after == before)
        browser.navigate(root)
        precondition(same(browser.viewRoot, root) && browser.breadcrumbs.map(\.lastPathComponent) == [root.lastPathComponent])

        // Adopt a plain folder in place
        try browser.adoptAsProject(project, addStandardFolders: false)
        precondition(FictionProject.isProject(project))
        print("Passed: desk project mode (scoping, entering, leaving, follow-the-file, converting, adopting).")
    }
}

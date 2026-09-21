import Foundation

@main enum FictionChecks {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("quill-fiction-check-\(UUID())")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }

        // Creation
        let project = try FictionProject.create(named: "The Crossing", in: root, starterFiles: true)
        precondition(FictionProject.isProject(project))
        precondition(FictionProject.load(project)?.title == "The Crossing")
        for name in FictionProject.standardFolders { precondition(fm.fileExists(atPath: project.appendingPathComponent(name).path), name) }
        for path in ["Manuscript/Chapter 1.md", "Characters/Example Character.md", "Locations/Example Location.md"] {
            precondition(fm.fileExists(atPath: project.appendingPathComponent(path).path), path)
        }
        let bare = try FictionProject.create(named: "Bare", in: root, starterFiles: false)
        let bareCharacters = try fm.contentsOfDirectory(atPath: bare.appendingPathComponent("Characters").path)
        precondition(bareCharacters.isEmpty)
        do { _ = try FictionProject.create(named: "The Crossing", in: root, starterFiles: false); preconditionFailure() } catch FolderCreationError.exists {}
        do { _ = try FictionProject.create(named: "a/b", in: root, starterFiles: false); preconditionFailure() } catch FolderCreationError.invalidName {}
        precondition(!fm.fileExists(atPath: root.appendingPathComponent("a").path))

        // Everything in a project is plain files a normal editor can use
        let chapter = try String(contentsOf: project.appendingPathComponent("Manuscript/Chapter 1.md"), encoding: .utf8)
        precondition(chapter == "# Chapter 1\n\n")

        // The Start Here guide
        let guide = FictionProject.guideURL(in: project)
        let guideText = try String(contentsOf: guide, encoding: .utf8)
        precondition(guideText.hasPrefix("# Start here: The Crossing") && guideText.contains(".sable-project.json") && guideText.contains("image-crop"))
        precondition(guideText.contains("Convert to Regular Folder") && guideText.contains("type: character"))
        try "my own notes".write(to: guide, atomically: true, encoding: .utf8)
        let ensured = try FictionProject.ensureGuide(in: project)
        precondition(ensured == guide)
        let keptGuide = try String(contentsOf: guide, encoding: .utf8)
        precondition(keptGuide == "my own notes", "The guide never overwrites your edits")
        try fm.removeItem(at: guide)
        try FictionProject.ensureGuide(in: project)
        precondition(fm.fileExists(atPath: guide.path), "It can be brought back after deleting")
        precondition(fm.fileExists(atPath: FictionProject.guideURL(in: bare).path), "Every new project starts with it, sample files or not")
        precondition(CardParsing.info(for: guide, text: guideText, projectRoot: project) == nil, "The guide itself isn't a card")

        // Detecting a project from inside it
        let deepFile = project.appendingPathComponent("Characters/Example Character.md")
        precondition(FictionProject.projectRoot(containing: deepFile, within: root) == project.standardizedFileURL)
        precondition(FictionProject.projectRoot(containing: project, within: root) == project.standardizedFileURL)
        precondition(FictionProject.projectRoot(containing: root, within: root) == nil)
        try fm.createDirectory(at: root.appendingPathComponent("Plain/Sub"), withIntermediateDirectories: true)
        precondition(FictionProject.projectRoot(containing: root.appendingPathComponent("Plain/Sub"), within: root) == nil)
        precondition(FictionProject.projectRoot(containing: deepFile, within: root.appendingPathComponent("Plain")) == nil, "Never searches above the writing folder")

        // Items
        let marren = try FictionProject.createItem(.character, named: "Marren Vale", in: project)
        precondition(marren.lastPathComponent == "Marren Vale.md" && marren.deletingLastPathComponent().lastPathComponent == "Characters")
        do { _ = try FictionProject.createItem(.character, named: "Marren Vale", in: project); preconditionFailure() } catch FolderCreationError.exists {}
        precondition(FictionProject.nextChapterName(in: project) == "Chapter 2")
        _ = try FictionProject.createItem(.chapter, named: "Chapter 7", in: project)
        precondition(FictionProject.nextChapterName(in: project) == "Chapter 8")
        // A folder the writer renamed by case is still found
        try fm.moveItem(at: project.appendingPathComponent("Locations"), to: project.appendingPathComponent("locations"))
        let harbor = try FictionProject.createItem(.location, named: "Harbor", in: project)
        precondition(harbor.deletingLastPathComponent().lastPathComponent == "locations")

        // Front matter
        let text = try String(contentsOf: marren, encoding: .utf8)
        let front = FrontMatter.parse(text)
        precondition(front.hasBlock && front.value(for: "type") == "character" && front.value(for: "role") == nil)
        precondition(front.body.hasPrefix("# Marren Vale"))
        let edited = FrontMatter.setting("role", to: "Harbor pilot", in: text)
        precondition(FrontMatter.parse(edited).value(for: "role") == "Harbor pilot")
        precondition(FrontMatter.parse(edited).body == front.body, "Editing a field never touches the body")
        precondition(edited.components(separatedBy: "\n").filter { $0.hasPrefix("role:") }.count == 1)
        let added = FrontMatter.setting("image", to: "Images/Marren: the pilot.png", in: edited)
        precondition(FrontMatter.parse(added).value(for: "image") == "Images/Marren: the pilot.png", "Quoting round-trips")
        precondition(added.contains("image: \"Images/Marren: the pilot.png\""))
        let fresh = FrontMatter.setting("type", to: "character", in: "# Just a note\n\nBody")
        precondition(fresh.hasPrefix("---\ntype: character\n---\n\n# Just a note") && FrontMatter.parse(fresh).body == "# Just a note\n\nBody")
        let foreign = "---\ntitle: X\ntags:\n  - a\n  - b\n# comment\nrole: Spy\n---\nText"
        precondition(FrontMatter.parse(foreign).value(for: "role") == "Spy" && FrontMatter.parse(foreign).value(for: "title") == "X")
        let kept = FrontMatter.setting("role", to: "Pilot", in: foreign)
        precondition(kept.contains("tags:\n  - a\n  - b\n# comment") && kept.hasSuffix("---\nText"), "Unknown YAML is preserved")
        precondition(!FrontMatter.parse("Not front matter\n---\nx: y\n---").hasBlock)
        precondition(FrontMatter.parse("---\nunclosed: yes\nText").hasBlock == false)
        precondition(FrontMatter.tags(from: "[hero, \"the pilot\"]") == ["hero", "the pilot"] && FrontMatter.tags(from: "a, b") == ["a", "b"] && FrontMatter.tags(from: nil).isEmpty)

        // Card parsing
        let card = CardParsing.info(for: marren, text: added, projectRoot: project)!
        precondition(card.kind == .character && card.title == "Marren Vale" && card.subtitle == "Harbor pilot")
        precondition(card.imageRef == "Images/Marren: the pilot.png" && !card.body.hasPrefix("# "))
        let plain = project.appendingPathComponent("Notes/Ideas.md")
        precondition(CardParsing.info(for: plain, text: "# Ideas\n", projectRoot: project) == nil, "Ordinary notes aren't cards")
        let typed = CardParsing.info(for: plain, text: "---\ntype: place\nregion: North\n---\n# Cold Keep\nStone.", projectRoot: project)!
        precondition(typed.kind == .location && typed.title == "Cold Keep" && typed.subtitle == "North", "Front matter type overrides the folder")
        precondition(CardParsing.info(for: project.appendingPathComponent("Manuscript/Chapter 1.md"), text: chapter, projectRoot: project) == nil)
        precondition(CardParsing.isCandidate(marren, projectRoot: project) && !CardParsing.isCandidate(plain, projectRoot: project))
        let untitled = CardParsing.info(for: project.appendingPathComponent("Characters/Nameless.md"), text: "just words", projectRoot: project)!
        precondition(untitled.title == "Nameless" && untitled.body == "just words")

        let forced = CardParsing.info(for: plain, text: "# Ideas\nBody", projectRoot: project, fallback: .lore)
        precondition(forced?.kind == .lore && forced?.title == "Ideas", "Any file can be shown as a card")

        // Images
        let outside = root.appendingPathComponent("portrait.png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: outside)
        let ref = try CardParsing.importImage(outside, into: project)
        precondition(ref == "Images/portrait.png" && fm.fileExists(atPath: project.appendingPathComponent(ref).path))
        let v1 = try CardParsing.importImage(outside, into: project)
        precondition(v1 == "Images/portrait-2.png", "Never overwrites a picture")
        let v2 = try CardParsing.importImage(project.appendingPathComponent(ref), into: project)
        precondition(v2 == ref, "A picture already in the project isn't copied")
        precondition(CardParsing.resolveImage(ref, card: marren, projectRoot: project) == project.appendingPathComponent(ref))
        precondition(CardParsing.resolveImage("portrait.png", card: marren, projectRoot: project) != nil, "Bare names look in Images")
        precondition(CardParsing.resolveImage("../Nope.png", card: marren, projectRoot: project) == nil)
        do { _ = try CardParsing.importImage(root.appendingPathComponent("notes.txt"), into: project); preconditionFailure() } catch FictionProjectError.badImage {}

        // Cropping
        let wide = CGSize(width: 2000, height: 1000), tall = CGSize(width: 1000, height: 2000)
        let full = CropRect.make(imageSize: wide, zoom: 1, centerX: 0.5, centerY: 0.5)
        precondition(abs(full.height - 1) < 1e-9 && abs(full.width * 2000 / (full.height * 1000) - 0.8) < 1e-9, "Crop keeps the card's 4:5 shape on a wide picture")
        let fullTall = CropRect.make(imageSize: tall, zoom: 1, centerX: 0.5, centerY: 0.5)
        precondition(abs(fullTall.width - 1) < 1e-9 && abs(fullTall.width * 1000 / (fullTall.height * 2000) - 0.8) < 1e-9, "…and on a tall one")
        let zoomed = CropRect.make(imageSize: wide, zoom: 2, centerX: 0.5, centerY: 0.5)
        precondition(abs(zoomed.width - full.width / 2) < 1e-9 && abs(zoomed.height - 0.5) < 1e-9)
        let pushed = CropRect.make(imageSize: wide, zoom: 2, centerX: 5, centerY: -3)
        precondition(pushed.x + pushed.width <= 1.000001 && pushed.y >= 0 && pushed.x >= 0 && pushed.y + pushed.height <= 1.000001, "Never leaves the picture")
        precondition(CropRect.make(imageSize: wide, zoom: 99, centerX: 0.5, centerY: 0.5).height == 0.25, "Zoom is capped")
        precondition(abs(zoomed.zoom(imageSize: wide) - 2) < 1e-9, "Reopening a crop recovers its zoom")
        let round = CropRect(parsing: zoomed.formatted)!
        precondition(abs(round.x - zoomed.x) < 1e-4 && abs(round.width - zoomed.width) < 1e-4, "Crop survives a trip through the file")
        precondition(CropRect(parsing: "0.1, 0.2, 0.5, 0.5") == CropRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5))
        for bad in ["", "1,2,3", "0.5,0.5,0.9,0.9", "a,b,c,d", "0,0,0,0.5", "-0.4,0,0.5,0.5"] { precondition(CropRect(parsing: bad) == nil, bad) }
        precondition(CropRect(parsing: nil) == nil)
        let cropped = FrontMatter.setting("image-crop", to: zoomed.formatted, in: added)
        precondition(CardParsing.info(for: marren, text: cropped, projectRoot: project)?.imageCrop != nil, "Cards read their crop")
        precondition(CardParsing.info(for: marren, text: added, projectRoot: project)?.imageCrop == nil)
        precondition(CardParsing.info(for: marren, text: FrontMatter.setting("image-crop", to: "nonsense", in: added), projectRoot: project)?.imageCrop == nil, "A bad crop is ignored, not fatal")

        // Front matter lists written by other editors
        let yamlList = "---\ntitle: X\ncharacters:\n  - Marren Vale\n  - \"Old Tam\"\nrole: Pilot\n---\nBody"
        precondition(FrontMatter.tags(from: FrontMatter.parse(yamlList).value(for: "characters")) == ["Marren Vale", "Old Tam"], "A YAML list is read as a list")
        precondition(FrontMatter.parse(yamlList).value(for: "role") == "Pilot")
        let replacedList = FrontMatter.setting("characters", to: "Mara", in: yamlList)
        precondition(replacedList == "---\ntitle: X\ncharacters: Mara\nrole: Pilot\n---\nBody", "Replacing a list leaves no orphaned items: \(replacedList)")
        precondition(FrontMatter.removing("characters", in: yamlList) == "---\ntitle: X\nrole: Pilot\n---\nBody")
        precondition(FrontMatter.removing("nothing", in: yamlList) == yamlList && FrontMatter.removing("x", in: "no block") == "no block")
        precondition(FrontMatter.removing("only", in: "---\nonly: 1\n---\n\n# Title\n") == "# Title\n", "An emptied block goes away")

        // Scene tags
        let chapterText = "---\nlocation: The Pier\ncharacters: Marren Vale, mara, Old Tam\nworld: [Bell Law, \"Tide Rules\"]\n---\n# Chapter 2\n\nBody"
        let scene = SceneTags.parse(chapterText)
        precondition(scene.locations == ["The Pier"] && scene.characters == ["Marren Vale", "mara", "Old Tam"], "\(scene)")
        precondition(scene.world == ["Bell Law", "Tide Rules"] && !scene.isEmpty)
        precondition(SceneTags.parse("# Just a chapter").isEmpty && SceneTags.parse("---\nx: 1\n---\nText").isEmpty)
        precondition(SceneTags.parse("---\ncharacter: A\ncast: a, B\n---\n").characters == ["A", "B"], "Other spellings are read, duplicates dropped")
        let withPlaces = SceneTags.setting(["The Pier", "Cold Keep"], for: .location, in: chapterText)
        precondition(SceneTags.parse(withPlaces).locations == ["The Pier", "Cold Keep"] && !withPlaces.contains("\nlocation:"), "The singular key is replaced by the plural")
        precondition(SceneTags.parse(withPlaces).characters == scene.characters && withPlaces.hasSuffix("# Chapter 2\n\nBody"), "Other tags and the chapter text are untouched")
        let untouched = SceneTags.setting(["Marren Vale"], for: .character, in: "# Chapter 3\n\nText")
        precondition(untouched.hasPrefix("---\ncharacters: Marren Vale\n---\n\n# Chapter 3") && SceneTags.parse(untouched).characters == ["Marren Vale"], "A chapter with no front matter gets a block")
        precondition(SceneTags.setting([], for: .character, in: untouched) == "# Chapter 3\n\nText", "Clearing the last tag removes the block again")
        precondition(SceneTags.setting(["A, B"], for: .character, in: "x").contains("characters: A  B"), "Commas can't live inside a name")

        // Card index and matching
        let indexRoot = try FictionProject.create(named: "Indexed", in: root, starterFiles: false)
        let mara = try FictionProject.createItem(.character, named: "Marren Vale", in: indexRoot)
        try FrontMatter.setting("aliases", to: "Mara, The Pilot", in: String(contentsOf: mara, encoding: .utf8)).write(to: mara, atomically: true, encoding: .utf8)
        _ = try FictionProject.createItem(.character, named: "Old Tam", in: indexRoot)
        _ = try FictionProject.createItem(.location, named: "The Pier", in: indexRoot)
        _ = try FictionProject.createItem(.lore, named: "Bell Law", in: indexRoot)
        _ = try FictionProject.createItem(.chapter, named: "Chapter 1", in: indexRoot)
        try "# Lantern Rules\n".write(to: indexRoot.appendingPathComponent("Notes/Lantern Rules.md"), atomically: true, encoding: .utf8)
        try "---\ntype: location\n---\n# Cold Keep\n".write(to: indexRoot.appendingPathComponent("Notes/Cold Keep.md"), atomically: true, encoding: .utf8)
        let cards = CardIndex.load(project: indexRoot)
        precondition(cards.map(\.title) == ["Bell Law", "Cold Keep", "Marren Vale", "Old Tam", "The Pier"], "Cards only; chapters, guide, and plain notes are left out: \(cards.map(\.title))")
        precondition(CardIndex.match("marren vale", kind: .character, in: cards)?.title == "Marren Vale")
        precondition(CardIndex.match("MARA", kind: .character, in: cards)?.title == "Marren Vale", "Aliases match, ignoring case")
        precondition(CardIndex.match("the pilot", kind: .character, in: cards)?.title == "Marren Vale")
        precondition(CardIndex.match("Cold Keep", kind: .location, in: cards)?.kind == .location, "A type: line puts a card anywhere")
        precondition(CardIndex.match("Nobody", kind: .character, in: cards) == nil)
        precondition(CardIndex.match("the pier", kind: .character, in: cards)?.title == "The Pier", "Falls back to another kind when it's the only match")
        let marenCard = cards.first { $0.title == "Marren Vale" }!
        let picked = SceneTags(characters: ["Old Tam"]).toggling(marenCard, kind: .character)
        precondition(picked == ["Old Tam", "Marren Vale"], "Picking a card adds its file name")
        precondition(SceneTags(characters: ["Old Tam", "mara"]).toggling(marenCard, kind: .character) == ["Old Tam"], "Picking it again (even by alias) removes it")
        precondition(SceneTags(characters: ["A", "B"]).removing("a", kind: .character) == ["B"])
        // Unchanged cards are reused without reading
        let cachedCards = cards.map { IndexedCard(url: $0.url, kind: $0.kind, stem: $0.stem, title: "CACHED", subtitle: "", aliases: [], modified: $0.modified) }
        precondition(CardIndex.load(project: indexRoot, reusing: cachedCards).allSatisfy { $0.title == "CACHED" })

        // Card colors
        for good in ["Blue", " red ", "#8A6A34", "8a6a34", "GRAY"] { precondition(CardColor.normalized(good) != nil, good) }
        precondition(CardColor.normalized("Blue") == "blue" && CardColor.normalized("8A6A34") == "#8a6a34" && CardColor.normalized("#8A6A34") == "#8a6a34")
        for bad in ["", "  ", "chartreuse", "#12", "#GGGGGG", "12345678"] { precondition(CardColor.normalized(bad) == nil, bad) }
        precondition(CardColor.normalized(nil) == nil)
        let tinted = FrontMatter.setting("color", to: "Purple", in: try String(contentsOf: mara, encoding: .utf8))
        try tinted.write(to: mara, atomically: true, encoding: .utf8)
        precondition(CardParsing.info(for: mara, text: tinted, projectRoot: indexRoot)?.color == "purple", "Cards read their color")
        precondition(CardIndex.load(project: indexRoot).first { $0.title == "Marren Vale" }?.color == "purple", "…and so does the index the scene strip uses")
        precondition(CardParsing.info(for: mara, text: FrontMatter.setting("color", to: "chartreuse", in: tinted), projectRoot: indexRoot)?.color == nil, "An unknown color is ignored")
        precondition(CardIndex.load(project: indexRoot).first { $0.title == "Old Tam" }?.color == nil)

        // Name highlighting
        func makeCard(_ title: String, _ kind: CardKind, stem: String? = nil, aliases: [String] = []) -> IndexedCard {
            IndexedCard(url: URL(fileURLWithPath: "/p/\(title).md"), kind: kind, stem: stem ?? title, title: title, subtitle: "", aliases: aliases, modified: nil)
        }
        let namer = NameHighlighter.build(from: [
            makeCard("Marren Vale", .character, aliases: ["Mara", "The Pilot"]), makeCard("Old Tam", .character), makeCard("Rose", .character),
            makeCard("Captain Voss", .character), makeCard("The Pier", .location), makeCard("Cold Keep", .location), makeCard("Bell Law", .lore),
        ])
        func found(_ text: String) -> [String] {
            let ns = text as NSString
            return namer.matches(in: text).map { ns.substring(with: $0.range) }
        }
        precondition(found("Marren Vale stood up. Marren looked at Vale, and Vale looked back.") == ["Marren Vale", "Marren", "Vale", "Vale"], "Full name, first name, and last name all match")
        precondition(found("Mara said nothing. The Pilot said less.") == ["Mara", "The Pilot"], "Aliases match")
        precondition(found("Marren's coat and Vale’s boots") == ["Marren", "Vale"], "Possessives still match")
        precondition(found("the pier was cold; the Pier was colder; Pier Road") == ["the pier", "the Pier"], "A place matches as a whole phrase in any capitalization, never by one of its words")
        precondition(found("A rose is a rose, but Rose was late.") == ["Rose"], "A one-word name only matches when capitalized")
        precondition(found("Old men and a captain, then Captain Voss and Voss") == ["Captain Voss", "Voss"], "Titles and small words are never names on their own")
        precondition(found("the keep stood at Cold Keep, near the Keep") == ["Cold Keep"], "A place's single words are never matched on their own")
        precondition(found("Marrenton and Tamper and Valentine") == [], "Never part of a longer word")
        precondition(found("Bell rang. Law and order. The bell law.") == ["bell law"], "World notes match the whole phrase only")
        precondition(found("---\ncharacters: Marren Vale\n---\nMarren") == ["Marren"], "The front matter block is left alone")
        precondition(found("") == [] && NameHighlighter.empty.matches(in: "Marren Vale").isEmpty && NameHighlighter.empty.isEmpty)
        let academy = NameHighlighter.build(from: [makeCard("Highlandsburg Academy", .location), makeCard("Ada Highlandsburg Reyes", .character)])
        let academyText = "The academy was old. Highlandsburg Academy rose over Highlandsburg. Ada and Reyes."
        precondition(academy.matches(in: academyText).map { (academyText as NSString).substring(with: $0.range) } == ["Highlandsburg Academy", "Ada", "Reyes"], "A location needs its whole phrase; a character's first and last name work alone, but not the middle one")
        let onlyPlaces = namer.matches(in: "Vale walked to the Pier and read Bell Law", kinds: [.location])
        precondition(onlyPlaces.count == 1 && onlyPlaces[0].kind == .location, "Each kind can be switched off on its own")
        precondition(namer.matches(in: "Vale at the Pier", kinds: []).isEmpty)
        let kinds = namer.matches(in: "Vale walked to the Pier and read Bell Law").map(\.kind)
        precondition(kinds == [.character, .location, .lore], "Each match knows its kind")
        let dupe = NameHighlighter.build(from: [makeCard("Ash", .character), makeCard("Ash", .location)])
        precondition(dupe.matches(in: "Ash").first?.kind == .character, "A character wins over a place with the same name")
        precondition(namer.signature == NameHighlighter.build(from: [makeCard("Bell Law", .lore), makeCard("Cold Keep", .location), makeCard("The Pier", .location), makeCard("Captain Voss", .character), makeCard("Rose", .character), makeCard("Old Tam", .character), makeCard("Marren Vale", .character, aliases: ["The Pilot", "Mara"])]).signature, "Same names, same signature, whatever the order")
        precondition(namer != NameHighlighter.empty)
        var bigCards: [IndexedCard] = []
        for n in 0..<300 { bigCards.append(makeCard("Person Number\(n) Surname\(n)", .character)) }
        let bigText = String(repeating: "Person Number5 Surname5 walked and Surname7 waited near the wall. ", count: 4000)
        let started = Date()
        let bigMatches = NameHighlighter.build(from: bigCards).matches(in: bigText)
        precondition(bigMatches.count >= 4000 && Date().timeIntervalSince(started) < 2, "A long chapter with hundreds of names is still quick: \(Date().timeIntervalSince(started))s")

        // Adding into a particular folder of the project
        try fm.createDirectory(at: indexRoot.appendingPathComponent("Characters/Villains"), withIntermediateDirectories: true)
        let villain = try FictionProject.createItem(.character, named: "Baron Ash", in: indexRoot, folder: indexRoot.appendingPathComponent("Characters/Villains"))
        precondition(villain.deletingLastPathComponent().lastPathComponent == "Villains" && CardParsing.kindByLocation(villain, projectRoot: indexRoot) == .character, "Still a character card")
        do { _ = try FictionProject.createItem(.character, named: "Escape", in: indexRoot, folder: root); preconditionFailure() } catch FolderMoveError.outsideRoot {}

        // Manuscript overview: ordering
        let chapterNames = ["Chapter 10.md", "Chapter 2.md", "Chapter 1.md", "Epilogue.md"]
        precondition(ManuscriptStats.orderedNames(chapterNames, order: nil) == ["Chapter 1.md", "Chapter 2.md", "Chapter 10.md", "Epilogue.md"], "Natural order by default")
        precondition(ManuscriptStats.orderedNames(chapterNames, order: ["Epilogue.md", "Chapter 2.md"]) == ["Epilogue.md", "Chapter 2.md", "Chapter 1.md", "Chapter 10.md"], "Arranged ones first, the rest follow")
        precondition(ManuscriptStats.orderedNames(chapterNames, order: ["Gone.md", "Chapter 2.md", "Chapter 2.md"]) == ["Chapter 2.md", "Chapter 1.md", "Chapter 10.md", "Epilogue.md"], "Missing and repeated names are ignored")
        let base = ["A.md", "B.md", "C.md", "D.md"]
        precondition(ManuscriptStats.moved(base, "D.md", to: "A.md") == ["D.md", "A.md", "B.md", "C.md"], "Drag up")
        precondition(ManuscriptStats.moved(base, "A.md", to: "C.md") == ["B.md", "C.md", "A.md", "D.md"], "Drag down lands after the target")
        precondition(ManuscriptStats.moved(base, "A.md", to: "D.md") == ["B.md", "C.md", "D.md", "A.md"], "Dropping on the last one moves to the end")
        precondition(ManuscriptStats.moved(base, "B.md", to: "B.md") == base && ManuscriptStats.moved(base, "Z.md", to: "A.md") == base)

        // Word counts
        precondition(ManuscriptStats.wordCount(in: "---\ntype: note\nrole: many many words here\n---\n# Title\n\nOne two three. ---\n") == 4, "Front matter and punctuation don't count")
        let manuscript = FictionProject.folder(for: .chapter, in: project)
        for file in try fm.contentsOfDirectory(atPath: manuscript.path) { try fm.removeItem(at: manuscript.appendingPathComponent(file)) }
        try "# One\n\nalpha beta gamma".write(to: manuscript.appendingPathComponent("Chapter 1.md"), atomically: true, encoding: .utf8)
        try "# Two\n\nalpha beta".write(to: manuscript.appendingPathComponent("Chapter 2.md"), atomically: true, encoding: .utf8)
        try "ignored".write(to: manuscript.appendingPathComponent("cover.png"), atomically: true, encoding: .utf8)
        try fm.createDirectory(at: manuscript.appendingPathComponent("Deleted Scenes"), withIntermediateDirectories: true)
        let loaded = ManuscriptStats.load(folder: manuscript, order: nil)
        precondition(loaded.map(\.title) == ["Chapter 1", "Chapter 2"] && loaded.map(\.words) == [4, 3], "Only chapters, counted")
        // Unchanged files reuse their count; changed ones are re-read
        let stale = loaded.map { ChapterStat(url: $0.url, words: 999, modified: $0.modified, size: $0.size) }
        precondition(ManuscriptStats.load(folder: manuscript, order: nil, reusing: stale).map(\.words) == [999, 999], "Cache is used when nothing changed")
        try "# One\n\nalpha beta gamma delta epsilon".write(to: manuscript.appendingPathComponent("Chapter 1.md"), atomically: true, encoding: .utf8)
        precondition(ManuscriptStats.load(folder: manuscript, order: nil, reusing: stale).map(\.words) == [6, 999], "A changed chapter is recounted")

        // Persisting order and goal in the marker, without disturbing anything else
        try FictionProject.setChapterOrder(["Chapter 2.md", "Chapter 1.md"], in: project)
        try FictionProject.setWordGoal(80_000, in: project)
        let saved = FictionProject.load(project)!
        precondition(saved.chapterOrder == ["Chapter 2.md", "Chapter 1.md"] && saved.wordGoal == 80_000 && saved.title == "The Crossing" && saved.created != nil)
        precondition(ManuscriptStats.load(folder: manuscript, order: saved.chapterOrder).map(\.title) == ["Chapter 2", "Chapter 1"])
        try FictionProject.setWordGoal(0, in: project)
        precondition(FictionProject.load(project)?.wordGoal == nil && FictionProject.load(project)?.chapterOrder != nil, "A zero goal clears it")
        do { try FictionProject.setChapterOrder([], in: root); preconditionFailure() } catch FictionProjectError.notProject {}
        // A marker written before these settings existed still opens, and gains them when saved
        try #"{"kind":"fiction","title":"Old One","version":1}"#.write(to: FictionProject.markerURL(in: bare), atomically: true, encoding: .utf8)
        precondition(FictionProject.load(bare)?.title == "Old One" && FictionProject.load(bare)?.chapterOrder == nil)
        try FictionProject.setChapterOrder(["x.md"], in: bare)
        precondition(FictionProject.load(bare)?.chapterOrder == ["x.md"] && FictionProject.load(bare)?.title == "Old One")

        // Projects made before the rename keep working, and are migrated when next saved
        let oldProject = root.appendingPathComponent("Made Before Rename")
        try fm.createDirectory(at: oldProject, withIntermediateDirectories: true)
        try #"{"kind":"fiction","title":"Made Before Rename","version":1}"#.write(to: oldProject.appendingPathComponent(FictionProject.legacyMarkerName), atomically: true, encoding: .utf8)
        precondition(FictionProject.isProject(oldProject) && FictionProject.load(oldProject)?.title == "Made Before Rename", "The old marker name still opens as a project")
        precondition(FictionProject.projectRoot(containing: oldProject.appendingPathComponent("x.md"), within: root) == oldProject.standardizedFileURL)
        try FictionProject.setWordGoal(50_000, in: oldProject)
        precondition(fm.fileExists(atPath: oldProject.appendingPathComponent(FictionProject.markerName).path) && !fm.fileExists(atPath: oldProject.appendingPathComponent(FictionProject.legacyMarkerName).path), "Saving migrates it to the new name")
        precondition(FictionProject.load(oldProject)?.wordGoal == 50_000 && FictionProject.load(oldProject)?.title == "Made Before Rename", "…keeping its settings")
        try #"{"kind":"fiction","title":"Legacy Convert","version":1}"#.write(to: oldProject.appendingPathComponent(FictionProject.legacyMarkerName), atomically: true, encoding: .utf8)
        try FictionProject.convertToRegularFolder(oldProject)
        precondition(!FictionProject.isProject(oldProject), "Converting back removes every marker, old or new")

        // Adopting a regular folder, and converting back
        let novel = root.appendingPathComponent("Novel")
        try fm.createDirectory(at: novel.appendingPathComponent("characters"), withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: novel.appendingPathComponent("draft.md"))
        try FictionProject.adopt(novel, addStandardFolders: true)
        precondition(FictionProject.isProject(novel) && FictionProject.load(novel)?.title == "Novel")
        let names = try fm.contentsOfDirectory(atPath: novel.path)
        precondition(names.filter { $0.lowercased() == "characters" }.count == 1, "Existing folders are reused, not duplicated")
        precondition(names.contains("Manuscript") && names.contains("draft.md"))
        do { try FictionProject.adopt(novel, addStandardFolders: false); preconditionFailure() } catch FictionProjectError.alreadyProject {}
        let before = try fm.contentsOfDirectory(atPath: novel.path).filter { $0 != FictionProject.markerName }.sorted()
        try FictionProject.convertToRegularFolder(novel)
        precondition(!FictionProject.isProject(novel))
        let v3 = try fm.contentsOfDirectory(atPath: novel.path).sorted()
        precondition(v3 == before, "Converting back removes only the marker")
        let v4 = try String(contentsOf: novel.appendingPathComponent("draft.md"), encoding: .utf8)
        precondition(v4 == "keep me")
        do { try FictionProject.convertToRegularFolder(novel); preconditionFailure() } catch FictionProjectError.notProject {}
        // A damaged marker still opens as a project
        try Data("not json".utf8).write(to: FictionProject.markerURL(in: bare))
        precondition(FictionProject.load(bare)?.title == "Bare")
        print("Passed: project creation and structure, detection, items, front matter, cards, images, adopting and converting back.")
    }
}

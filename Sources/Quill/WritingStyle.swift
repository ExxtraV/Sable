import SwiftUI
import AppKit
import QuillCore

struct WritingStyleControls: View {
    @AppStorage("fontFamily") private var family = "Charter"
    @AppStorage("fontSize") private var size = 19.0
    @AppStorage("pageWidth") private var width = 680.0
    @AppStorage("lineSpacing") private var spacing = 0.28
    @AppStorage("appearance") private var appearance = "dark"
    @AppStorage("writingTheme") private var theme = "graphite"
    @AppStorage("pinchToZoom") private var pinch = true
    @AppStorage("customFont") private var customFont = false
    @AppStorage("focusStyle") private var focusStyle = "gradient"
    @AppStorage("typewriterMode") private var typewriterMode = "room"
    @AppStorage("sceneTagsPlacement") private var sceneTagsPlacement = "bottom"
    @AppStorage("sceneTagsFade") private var sceneTagsFade = true
    @AppStorage("sceneTagsColor") private var sceneTagsColor = true
    private let presets = [("Everyday", "Georgia"), ("Literary", "Charter"), ("Classic", "Baskerville"), ("Science fiction", "Menlo"), ("Manuscript", "Courier New")]
    private let families = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    var body: some View {
        Group {
            Section("Typeface") {
                Picker("Writing font", selection: Binding(get: {
                    customFont || !presets.contains(where: { $0.1 == family }) ? "custom" : family
                }, set: { value in
                    customFont = value == "custom"
                    if !customFont { family = value }
                })) {
                    ForEach(presets, id: \.1) { preset in Text("\(preset.0) · \(preset.1)").tag(preset.1) }
                    Text("Choose any font…").tag("custom")
                }
                if customFont || !presets.contains(where: { $0.1 == family }) {
                    Picker("Custom font", selection: $family) {
                        ForEach(families, id: \.self) { name in Text(name).tag(name) }
                    }
                }
                Slider(value: $size, in: 14...30, step: 1) { Text("Size: \(Int(size))") }
                Slider(value: $width, in: 480...880, step: 20) { Text("Page width: \(Int(width))") }
                Slider(value: $spacing, in: 0.1...0.65, step: 0.05) { Text("Line spacing") }
                Text("The story begins with a door.")
                    .font(.custom(family, size: size)).padding(.vertical, 4)
            }
            Section("Theme") {
                Picker("Theme", selection: $theme) {
                    ForEach(WritingTheme.all) { item in Text(item.name).tag(item.id) }
                }
            }
            Section("Scrolling & focus") {
                Picker("Scrolling", selection: $typewriterMode) {
                    Text("Standard").tag("off")
                    Text("Room to scroll past the end").tag("room")
                    Text("Keep the line I’m writing centered").tag("center")
                }
                Picker("Paragraph focus", selection: $focusStyle) {
                    Text("Fade gradually").tag("gradient")
                    Text("Dim evenly").tag("uniform")
                }
                Toggle("Pinch to zoom", isOn: $pinch)
                Text("Zoom: ⌘+ / ⌘− · Reset: ⌘0 · Move the pointer to the top edge for controls.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Scene tags") {
                Picker("Scene tags", selection: $sceneTagsPlacement) {
                    Text("Bottom").tag("bottom")
                    Text("Top left").tag("topLeading")
                    Text("Top right").tag("topTrailing")
                    Text("Bottom left").tag("bottomLeading")
                    Text("Bottom right").tag("bottomTrailing")
                    Text("Off").tag("off")
                }
                Toggle("Fade scene tags while typing", isOn: $sceneTagsFade).disabled(sceneTagsPlacement == "off")
                Toggle("Color-code scene tags", isOn: $sceneTagsColor).disabled(sceneTagsPlacement == "off")
            }
            Section {
                Button("Reset writing style") { family = "Charter"; customFont = false; size = 19; width = 680; spacing = 0.28; appearance = "dark"; theme = "graphite"; WritingZoom.set(1) }
            }
        }
    }
}

struct OutlineControls: View {
    @AppStorage("outlineTitle") private var title = "Outline"
    @AppStorage("outlineLevel") private var level = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Your outline").font(.headline)
            TextField("Section name", text: $title).textFieldStyle(.roundedBorder)
            HStack {
                ForEach(["Chapters", "Episodes", "Scenes", "Outline"], id: \.self) { name in
                    Button(name) { title = name }.font(.caption)
                }
            }
            Picker("Show", selection: $level) {
                Text("All heading levels").tag(0)
                ForEach(1...6, id: \.self) { value in Text("Level \(value) headings only").tag(value) }
            }
            Text("Use any name you like. This changes the sidebar, not your Markdown headings. Applies across documents.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(width: 370)
    }
}

struct SentenceOptions: View {
    @AppStorage("writingTheme") private var themeName = "graphite"
    @AppStorage("syntaxClasses") private var enabled = 0
    @AppStorage("wordColorVersion") private var colorVersion = 0
    @AppStorage("nameHighlights") private var nameHighlights = true
    @AppStorage("nameStyle") private var nameStyle = "shimmer"
    @AppStorage("nameCharacters") private var nameCharacters = true
    @AppStorage("nameLocations") private var nameLocations = true
    @AppStorage("nameLore") private var nameLore = true
    @AppStorage("nameShimmerStrength") private var shimmerStrength = 0.6
    @AppStorage("nameShimmerSpeed") private var shimmerSpeed = 1.0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sentence structure").font(.headline)
            ForEach(WordClass.allCases, id: \.rawValue) { kind in
                HStack {
                    Toggle(isOn: Binding(get: { enabled & kind.rawValue != 0 }, set: { if $0 { enabled |= kind.rawValue } else { enabled &= ~kind.rawValue } })) {
                        Text(kind.label)
                    }
                    Spacer(minLength: 12)
                    ColorPicker(kind.label + " color", selection: colorBinding(for: kind), supportsOpacity: false).labelsHidden()
                }
            }
            HStack {
                Button("Clear colors") { enabled = 0 }
                Button("Reset to default colors") {
                    for kind in WordClass.allCases { UserDefaults.standard.removeObject(forKey: "wordColor.\(kind.rawValue)") }
                    colorVersion += 1
                }
            }
            Text("Defaults are soft pastel tints; use the swatches to pick your own. On-device language predictions, not grammar rules. Invented names and unusual sentences may be misclassified. Colors appear in edit mode and are never saved to your file.")
                .font(.caption).foregroundStyle(.secondary)
            Divider().padding(.vertical, 4)
            Text("Names & places").font(.headline)
            Toggle("Highlight names in a Fiction Project", isOn: $nameHighlights)
            Picker("Style", selection: $nameStyle) {
                Text("Shimmer").tag("shimmer")
                Text("Color only").tag("color")
            }.pickerStyle(.segmented).disabled(!nameHighlights)
            if nameStyle == "shimmer" {
                HStack { Text("Strength"); Slider(value: $shimmerStrength, in: 0.1...1); Text(Int(shimmerStrength * 100).formatted() + "%").monospacedDigit().frame(width: 40, alignment: .trailing) }
                    .disabled(!nameHighlights)
                HStack { Text("Speed"); Slider(value: $shimmerSpeed, in: 0.3...2.5); Text(String(format: "%.1f×", shimmerSpeed)).monospacedDigit().frame(width: 40, alignment: .trailing) }
                    .disabled(!nameHighlights)
            }
            ForEach(CardKind.allCases, id: \.self) { kind in
                HStack {
                    Toggle(kind.pickerTitle, isOn: kindBinding(kind))
                    Spacer(minLength: 12)
                    ColorPicker(kind.pickerTitle + " color", selection: nameColorBinding(for: kind), supportsOpacity: false).labelsHidden()
                }.disabled(!nameHighlights)
            }
            Button("Reset name colors") {
                for kind in CardKind.allCases { UserDefaults.standard.removeObject(forKey: "nameColor.\(kind.rawValue)") }
                colorVersion += 1
            }.disabled(!nameHighlights)
            Text("Characters are found by full name, first name, last name, file name, and aliases. Locations and world notes match the whole phrase only, so \"Academy\" alone won't light up \"Highlandsburg Academy\". Everyday words and titles like Captain are never highlighted. Names are never saved to your file.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(20).frame(width: 340)
    }
    private func kindBinding(_ kind: CardKind) -> Binding<Bool> {
        switch kind {
        case .character: return $nameCharacters
        case .location: return $nameLocations
        case .lore: return $nameLore
        }
    }
    private func nameColorBinding(for kind: CardKind) -> Binding<Color> {
        Binding(
            get: {
                var resolved = NSColor.gray
                let appearance = NSAppearance(named: WritingTheme.named(themeName).dark ? .darkAqua : .aqua)!
                appearance.performAsCurrentDrawingAppearance { resolved = WritingTextView.nameColor(kind).usingColorSpace(.sRGB) ?? .gray }
                return Color(nsColor: resolved)
            },
            set: { newValue in
                UserDefaults.standard.set(NSColor(newValue).quillHex, forKey: "nameColor.\(kind.rawValue)")
                colorVersion += 1
            }
        )
    }
    private func colorBinding(for kind: WordClass) -> Binding<Color> {
        Binding(
            get: {
                var resolved = NSColor.gray
                let appearance = NSAppearance(named: WritingTheme.named(themeName).dark ? .darkAqua : .aqua)!
                appearance.performAsCurrentDrawingAppearance {
                    resolved = WritingTextView.wordColor(kind).usingColorSpace(.sRGB) ?? .gray
                }
                return Color(nsColor: resolved)
            },
            set: { newValue in
                UserDefaults.standard.set(NSColor(newValue).quillHex, forKey: "wordColor.\(kind.rawValue)")
                colorVersion += 1
            }
        )
    }
}

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
    private let presets = [("Everyday", "Georgia"), ("Literary", "Charter"), ("Classic", "Baskerville"), ("Science fiction", "Menlo"), ("Manuscript", "Courier New")]
    private let families = NSFontManager.shared.availableFontFamilies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

    var body: some View {
        Group {
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
            Picker("Theme", selection: $theme) {
                ForEach(WritingTheme.all) { item in Text(item.name).tag(item.id) }
            }
            Toggle("Pinch to zoom", isOn: $pinch)
            Text("Zoom: ⌘+ / ⌘− · Reset: ⌘0 · Move the pointer to the top edge for controls.")
                .font(.caption).foregroundStyle(.secondary)
            Text("The story begins with a door.")
                .font(.custom(family, size: size)).padding(.vertical, 8)
            Button("Reset writing style") { family = "Charter"; customFont = false; size = 19; width = 680; spacing = 0.28; appearance = "dark"; theme = "graphite"; WritingZoom.set(1) }
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
        }.padding(20).frame(width: 340)
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

import Foundation

@main enum ToolbarChecks {
    static func main() {
        let ids = ToolbarLayout.all.map(\.id)
        precondition(Set(ids).count == ids.count, "Tool ids are unique")
        precondition(ToolbarLayout.all.allSatisfy { !$0.title.isEmpty && !$0.icon.isEmpty && !$0.detail.isEmpty }, "Every tool is described")
        precondition(ToolbarLayout.minimal.allSatisfy { ids.contains($0) } && ToolbarLayout.writers.allSatisfy { ids.contains($0) }, "The presets only name real tools")
        precondition(ToolbarLayout.minimal.count <= 5, "The default toolbar is minimal")
        precondition(ToolbarLayout.ids(from: ToolbarLayout.defaultToken) == ToolbarLayout.minimal, "Nothing chosen yet gives the minimal toolbar")
        precondition(ToolbarLayout.ids(from: "bold,italic,heading") == ["bold", "italic", "heading"], "A chosen set keeps its order")
        precondition(ToolbarLayout.ids(from: "italic,bold,italic,nonsense,,heading") == ["italic", "bold", "heading"], "Repeats and unknown tools are dropped")
        precondition(ToolbarLayout.ids(from: "").isEmpty, "An empty toolbar stays empty")
        precondition(ToolbarLayout.encode(ToolbarLayout.writers) == ToolbarLayout.writers.joined(separator: ","), "Encoding round-trips")
        precondition(ToolbarLayout.ids(from: ToolbarLayout.encode(ToolbarLayout.all.map(\.id))) == ids, "Everything round-trips")
        precondition(ToolbarLayout.tools(from: "bullets").first?.group == .blocks && ToolbarLayout.tool("bold")?.editsText == true && ToolbarLayout.tool("desk")?.editsText == false, "Groups and text-editing flags")
        print("Passed: toolbar tools (unique, described, presets valid, storage parsing, order, defaults).")
    }
}

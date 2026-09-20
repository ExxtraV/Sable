import AppKit
import SwiftUI
import Sparkle

/// One updater per process; preview builds never contact the production feed.
@MainActor
final class AppUpdater: ObservableObject {
    @Published var canCheck = false
    @Published var automaticChecks = false
    @Published private(set) var unavailableReason: String?
    private var controller: SPUStandardUpdaterController?

    init() {
        #if QUILL_PREVIEW
        unavailableReason = "Updates are disabled in the preview app."
        #else
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String,
              Data(base64Encoded: key)?.count == 32 else {
            unavailableReason = "Updates will be available once the release channel is connected."
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
        controller.updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticChecks)
        do { try controller.updater.start() }
        catch { unavailableReason = error.localizedDescription }
        #endif
    }

    func check() { controller?.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
}

struct UpdateSettings: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Section("Software updates") {
            if let reason = updater.unavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("Automatically check for updates", isOn: Binding(get: { updater.automaticChecks }, set: { updater.setAutomaticChecks($0) }))
                Text("You choose when to install and restart.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Check for Updates…", action: updater.check).disabled(!updater.canCheck)
        }
    }
}

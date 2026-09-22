import AppKit
import SwiftUI
import Sparkle

/// One updater per process; preview builds never contact the production feed.
@MainActor
final class AppUpdater: ObservableObject {
    @Published var canCheck = false
    @Published var automaticChecks = false
    /// How often Sable looks for an update, in days, while it's open. Sparkle's own default is once a day.
    @Published var checkIntervalDays: Double = 1
    @Published private(set) var lastCheckDate: Date?
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
        controller.updater.publisher(for: \.updateCheckInterval).map { max(1, $0 / 86_400) }.assign(to: &$checkIntervalDays)
        controller.updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastCheckDate)
        do { try controller.updater.start() }
        catch { unavailableReason = error.localizedDescription }
        #endif
    }

    func check() { controller?.checkForUpdates(nil) }
    func setAutomaticChecks(_ enabled: Bool) { controller?.updater.automaticallyChecksForUpdates = enabled }
    func setCheckInterval(days: Double) { controller?.updater.updateCheckInterval = days * 86_400 }
}

struct UpdateSettings: View {
    @ObservedObject var updater: AppUpdater
    private var lastCheckText: String {
        guard let date = updater.lastCheckDate else { return "Hasn't checked yet this launch. Sable only checks while it's open." }
        return "Last checked " + date.formatted(.relative(presentation: .named))
    }
    var body: some View {
        Section("Software updates") {
            if let reason = updater.unavailableReason {
                Text(reason).font(.caption).foregroundStyle(.secondary)
            } else {
                Toggle("Automatically check for updates", isOn: Binding(get: { updater.automaticChecks }, set: { updater.setAutomaticChecks($0) }))
                Picker("Check", selection: Binding(
                    get: { [1.0, 3.0, 7.0].min(by: { abs($0 - updater.checkIntervalDays) < abs($1 - updater.checkIntervalDays) }) ?? 1 },
                    set: { updater.setCheckInterval(days: $0) }
                )) {
                    Text("Every day").tag(1.0)
                    Text("Every 3 days").tag(3.0)
                    Text("Every week").tag(7.0)
                }.disabled(!updater.automaticChecks)
                Text(lastCheckText).font(.caption).foregroundStyle(.secondary)
                Text("You choose when to install and restart.").font(.caption).foregroundStyle(.secondary)
            }
            Button("Check for Updates…", action: updater.check).disabled(!updater.canCheck)
        }
    }
}

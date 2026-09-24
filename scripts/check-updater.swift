import AppKit
import SwiftUI

@main enum UpdaterChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let updater = AppUpdater()
        precondition(!updater.canCheck)
        precondition(updater.unavailableReason != nil)
        updater.check()
        precondition(UpdateChannels.allowed(beta: false).isEmpty, "Stable users must see only untagged items.")
        precondition(UpdateChannels.allowed(beta: true) == ["beta"])
        print("Passed: unconfigured updater stays inactive and manual check is safe; beta channel is opt-in.")
    }
}

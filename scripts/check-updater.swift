import AppKit
import SwiftUI

@main enum UpdaterChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let updater = AppUpdater()
        precondition(!updater.canCheck)
        precondition(updater.unavailableReason != nil)
        updater.check()
        print("Passed: unconfigured updater stays inactive and manual check is safe.")
    }
}

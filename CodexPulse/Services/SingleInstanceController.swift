import AppKit
import Foundation

enum SingleInstanceController {
    static func enforceSingleInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentApp = NSRunningApplication.current
        let currentPID = currentApp.processIdentifier
        let currentLaunchDate = currentApp.launchDate ?? .distantPast

        let siblingInstances = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentPID }

        for app in siblingInstances {
            let siblingLaunchDate = app.launchDate ?? .distantPast

            if siblingLaunchDate <= currentLaunchDate {
                if !app.terminate() {
                    app.forceTerminate()
                }
            } else {
                NSApp.terminate(nil)
                return
            }
        }
    }
}

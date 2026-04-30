import SwiftUI

@main
struct MacMTPApp: App {
    init() {
        // Find the mtp-daemon binary.
        // Search order: app bundle, then development paths.
        var candidates: [String] = []

        // Bundled in app (production)
        if let resourcePath = Bundle.main.resourcePath {
            candidates.append((resourcePath as NSString).appendingPathComponent("mtp-daemon"))
        }

        // Next to the app bundle (development)
        if let bundlePath = Bundle.main.bundlePath as String? {
            let parent = (bundlePath as NSString).deletingLastPathComponent
            candidates.append((parent as NSString).appendingPathComponent("mtp-daemon"))
        }

        // Project source directory (development)
        candidates.append(NSHomeDirectory() + "/Code/MacMTP/mtp-daemon/target/release/mtp-daemon")

        for candidate in candidates {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                MTPBridge.daemonPath = candidate
                return
            }
        }

        // Fallback: set the bundle path even if it doesn't exist yet
        if let resourcePath = Bundle.main.resourcePath {
            MTPBridge.daemonPath = (resourcePath as NSString).appendingPathComponent("mtp-daemon")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .commands {
            BrowserCommands()
        }
    }
}

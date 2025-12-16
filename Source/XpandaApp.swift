import SwiftUI

@main
struct XpandaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var xpManager = XPManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(xpManager)
                .frame(minWidth: 900, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        Settings {
            SettingsView()
                .environmentObject(xpManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var expansionEngine: ExpansionEngine?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the expansion engine
        expansionEngine = ExpansionEngine.shared
        expansionEngine?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        expansionEngine?.stop()
    }
}

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
            CommandGroup(replacing: .appInfo) {
                Button("About Xpanda") {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    AppDelegate.showAboutWindow()
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(xpManager)
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    var expansionEngine: ExpansionEngine?
    static var aboutWindow: NSWindow?

    static func showAboutWindow() {
        if let existing = aboutWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About Xpanda"
        window.center()
        window.contentView = NSHostingView(rootView: AboutView())
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        aboutWindow = window
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Initialize the expansion engine
        expansionEngine = ExpansionEngine.shared
        expansionEngine?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        expansionEngine?.stop()
    }
}

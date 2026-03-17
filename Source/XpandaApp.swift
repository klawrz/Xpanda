import SwiftUI
import UserNotifications

extension Notification.Name {
    static let createXPFromSuggestion = Notification.Name("createXPFromSuggestion")
}

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

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
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
        UNUserNotificationCenter.current().delegate = self

        // Initialize the expansion engine
        expansionEngine = ExpansionEngine.shared
        expansionEngine?.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        expansionEngine?.stop()
        PhraseSuggestionTracker.shared.save()
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if response.actionIdentifier == "CREATE_XP_ACTION" {
            if let phrase = response.notification.request.content.userInfo["suggestedPhrase"] as? String {
                NSApplication.shared.activate(ignoringOtherApps: true)
                NotificationCenter.default.post(
                    name: .createXPFromSuggestion,
                    object: nil,
                    userInfo: ["phrase": phrase]
                )
            }
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

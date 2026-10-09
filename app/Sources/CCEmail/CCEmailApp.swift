import AppKit
import SwiftUI

@main
struct CCEmailApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var app = AppState()

    var body: some Scene {
        WindowGroup("CC Email") {
            RootView()
                .environment(app)
                .frame(minWidth: 900, minHeight: 600)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Refresh Summary") { app.summary.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(app.launchContext == nil)
            }
        }

        Settings {
            SettingsView().environment(app)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // `swift run` starts a bare executable with no bundle; make it a regular foreground app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        DevHooks.applicationDidLaunch()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

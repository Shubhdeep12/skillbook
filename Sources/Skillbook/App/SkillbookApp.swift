import AppKit
import SwiftUI

@main
struct SkillbookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SkillStore()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(store)
        } label: {
            Image(systemName: "book")
        }
        .menuBarExtraStyle(.window)

        Window("Skillbook", id: "manager") {
            ManagerView()
                .environment(store)
                .frame(minWidth: 960, minHeight: 580)
        }
        .defaultSize(width: 1240, height: 800)
        .defaultLaunchBehavior(CommandLine.arguments.contains("--open") ? .presented : .suppressed)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        Settings {
            SettingsView()
                .environment(store)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar app: no Dock icon until the manager window opens.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

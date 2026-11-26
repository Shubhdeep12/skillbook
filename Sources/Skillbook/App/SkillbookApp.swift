import AppKit
import SwiftUI

@main
struct SkillbookApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store: SkillStore
    @State private var updater: Updater

    init() {
        let store = SkillStore()
        _store = State(initialValue: store)
        _updater = State(initialValue: Updater(hasUnsavedEdits: { [weak store] in store?.hasUnsavedEdits ?? false }))
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(store)
                .environment(updater)
        } label: {
            Image(systemName: "book")
        }
        .menuBarExtraStyle(.window)

        Window("Skillbook", id: "manager") {
            ManagerView()
                .environment(store)
                .environment(updater)
                .frame(minWidth: 960, minHeight: 580)
        }
        .defaultSize(width: 1240, height: 800)
        .defaultLaunchBehavior(CommandLine.arguments.contains("--open") ? .presented : .suppressed)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Check for Updates…") { Task { await updater.checkInteractively() } }
                    .disabled(updater.isBusy)
            }
        }

        Settings {
            SettingsView()
                .environment(store)
                .environment(updater)
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

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
            MenuBarIcon()
        }
        .menuBarExtraStyle(.window)

        Window("Skillbook", id: "manager") {
            ManagerView()
                .environment(store)
                .environment(updater)
                .frame(minWidth: 960, minHeight: 580)
        }
        .defaultSize(width: 1240, height: 800)
        // The AppDelegate decides whether to open it at launch (see Launch).
        .defaultLaunchBehavior(.suppressed)
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

/// How Skillbook was started, which decides whether the window opens.
enum Launch {
    /// Passed when Skillbook restarts itself after a background update.
    static let backgroundFlag = "--background"

    /// Set from the launch Apple event: macOS opened Skillbook as a login item.
    @MainActor static var asLoginItem = false

    /// Opened by a person (Dock, Finder, Spotlight, `open`): show the window.
    /// Opened at login or by a background update: stay in the menu bar.
    @MainActor static var showsWindow: Bool {
        if CommandLine.arguments.contains("--open") { return true }
        return !asLoginItem && !CommandLine.arguments.contains(backgroundFlag)
    }
}

extension Notification.Name {
    static let showManager = Notification.Name("Skillbook.showManager")
}

/// The menu bar icon. It stays alive for the whole session, so it also opens the window
/// when the AppDelegate asks (at launch and when the Dock icon is clicked).
private struct MenuBarIcon: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: "book")
            .onReceive(NotificationCenter.default.publisher(for: .showManager)) { _ in
                openWindow(id: "manager")
                NSApp.activate(ignoringOtherApps: true)
            }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Only readable while the launch event is being handled.
        if let event = NSAppleEventManager.shared().currentAppleEvent,
           event.eventID == kAEOpenApplication,
           event.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem {
            Launch.asLoginItem = true
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu bar app: no Dock icon until the manager window opens.
        NSApp.setActivationPolicy(.accessory)
        if Launch.showsWindow {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                NotificationCenter.default.post(name: .showManager, object: nil)
            }
        }
    }

    /// Clicking the Dock icon or opening the app again while it runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NotificationCenter.default.post(name: .showManager, object: nil) }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

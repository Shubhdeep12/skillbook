import AppKit

enum ConflictChoice { case replace, keepBoth, cancel }

/// Modal AppKit alerts. They work the same from the menu bar panel and the manager window.
@MainActor
enum Alerts {
    private static func prepare(_ alert: NSAlert) {
        NSApp.activate(ignoringOtherApps: true)
        alert.icon = NSApp.applicationIconImage
    }

    static func confirm(_ title: String, _ message: String, ok: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        let button = alert.addButton(withTitle: ok)
        button.hasDestructiveAction = destructive
        alert.addButton(withTitle: "Cancel")
        if destructive { alert.alertStyle = .warning }
        prepare(alert)
        return alert.runModal() == .alertFirstButtonReturn
    }

    static func conflict(name: String, in dir: URL) -> ConflictChoice {
        let alert = NSAlert()
        alert.messageText = "“\(name)” already exists in \(dir.path.tildePath)"
        alert.informativeText = "Replace moves the existing folder to the Trash. Keep Both adds a numbered copy."
        alert.addButton(withTitle: "Keep Both")
        let replace = alert.addButton(withTitle: "Replace")
        replace.hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        prepare(alert)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        default: return .cancel
        }
    }

    static func unsavedChanges(name: String) -> Bool? {
        let alert = NSAlert()
        alert.messageText = "Save changes to “\(name)”?"
        alert.informativeText = "Your edits are lost if you don't save them."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        prepare(alert)
        switch alert.runModal() {
        case .alertFirstButtonReturn: return true
        case .alertSecondButtonReturn: return false
        default: return nil
        }
    }

    static func prompt(_ title: String, _ message: String, value: String, ok: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: ok)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        field.stringValue = value
        field.placeholderString = "my-skill"
        alert.accessoryView = field
        prepare(alert)
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        return field.stringValue.nonEmpty
    }

    static func error(_ error: Error) {
        let alert = NSAlert(error: error)
        prepare(alert)
        alert.runModal()
    }

    static func message(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        prepare(alert)
        alert.runModal()
    }

    static func chooseFolder(prompt: String, message: String) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt
        panel.message = message
        panel.directoryURL = Paths.home
        NSApp.activate(ignoringOtherApps: true)
        return panel.runModal() == .OK ? panel.url : nil
    }
}

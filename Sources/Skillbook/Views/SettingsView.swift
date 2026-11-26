import ServiceManagement
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            ScanSettings().tabItem { Label("Locations", systemImage: "folder.badge.gearshape") }
            AboutSettings().tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 540, height: 480)
    }
}

private struct GeneralSettings: View {
    @Environment(SkillStore.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
                Toggle("Open at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                            Alerts.error(error)
                        }
                    }
                Toggle("Rescan when skills change on disk", isOn: $settings.watchForChanges)
                    .onChange(of: settings.watchForChanges) { _, _ in store.configureWatcher() }
            }
            UpdateSettingsSection()
            Section("Show") {
                Toggle("Old plugin versions and marketplace catalog copies", isOn: $settings.showPluginExtras)
                Toggle("SKILL.md files that fail the skill check", isOn: $settings.showUnverified)
            }
            Section("Editor") {
                Stepper(value: $settings.editorFontSize, in: 10...22, step: 1) {
                    Text("Font size: \(Int(settings.editorFontSize)) pt")
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct ScanSettings: View {
    @Environment(SkillStore.self) private var store
    @State private var selectedRoot: String?
    @State private var excludedText = ""

    var body: some View {
        @Bindable var settings = store.settings
        Form {
            Section {
                List(selection: $selectedRoot) {
                    ForEach(settings.scanRoots, id: \.self) { root in
                        Label(root, systemImage: "folder").tag(root)
                    }
                }
                .frame(height: 96)
                HStack {
                    Button {
                        if let url = Alerts.chooseFolder(prompt: "Add", message: "Choose a folder to scan for SKILL.md files") {
                            let path = url.path.tildePath
                            if !settings.scanRoots.contains(path) { settings.scanRoots.append(path) }
                            store.settingsChanged()
                        }
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let sel = selectedRoot { settings.scanRoots.removeAll { $0 == sel } }
                        if settings.scanRoots.isEmpty { settings.scanRoots = ["~"] }
                        store.settingsChanged()
                    } label: { Image(systemName: "minus") }
                    .disabled(selectedRoot == nil)
                    Spacer()
                    Stepper("Max depth: \(settings.maxDepth)", value: $settings.maxDepth, in: 4...24)
                        .onChange(of: settings.maxDepth) { _, _ in store.scheduleRescan() }
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Scan these folders")
            } footer: {
                Text("Your home folder covers ~/.claude, ~/.cursor, ~/.codex, ~/.agents and every repo inside it.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                TextField("Folder names", text: $excludedText, axis: .vertical)
                    .lineLimit(3...5)
                    .font(.system(size: 11.5, design: .monospaced))
                HStack {
                    Button("Restore Defaults") {
                        settings.excludedNames = AppSettings.defaultExcluded
                        excludedText = settings.excludedNames.joined(separator: ", ")
                        store.settingsChanged()
                    }
                    Spacer()
                    Button("Apply") {
                        settings.excludedNames = excludedText.split(separator: ",").map { String($0).trimmed }.filter { !$0.isEmpty }
                        store.settingsChanged()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            } header: {
                Text("Skip folders named")
            }
        }
        .formStyle(.grouped)
        .onAppear { excludedText = settings.excludedNames.joined(separator: ", ") }
    }
}

private struct AboutSettings: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 84, height: 84)
            Text("Skillbook").font(.title.weight(.semibold))
            Text("Version \(updater.currentVersion)").font(.callout).foregroundStyle(.secondary)
            Text("Find, preview and manage agent skills on this Mac.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
                Text("A file counts as a skill when it:").font(.callout.weight(.semibold))
                Text("• is named SKILL.md")
                Text("• starts with a YAML frontmatter block (--- … ---)")
                Text("• has a description in that block (a name is expected too)")
                Text("Files that pass with warnings appear under Needs Attention.")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

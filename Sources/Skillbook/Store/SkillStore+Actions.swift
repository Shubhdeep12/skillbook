import AppKit
import Foundation

struct SkillError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension SkillStore {
    // MARK: Finder & clipboard

    func reveal(_ skills: [Skill]) {
        NSWorkspace.shared.activateFileViewerSelecting(skills.map(\.fileURL))
    }

    func openInDefaultEditor(_ skill: Skill) {
        NSWorkspace.shared.open(skill.fileURL)
    }

    func copyPaths(_ skills: [Skill]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(skills.map(\.folderURL.path).joined(separator: "\n"), forType: .string)
        show(skills.count == 1 ? "Copied path" : "Copied \(skills.count) paths", symbol: "doc.on.clipboard.fill")
    }

    func copyContents(_ skill: Skill) {
        guard let text = try? String(contentsOf: skill.fileURL, encoding: .utf8) else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        show("Copied SKILL.md contents", symbol: "doc.on.clipboard.fill")
    }

    /// Puts the skill folders on the clipboard. Paste them here or in Finder.
    func copyToClipboard(_ skills: [Skill]) {
        guard !skills.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(skills.map { $0.folderURL.resolvingSymlinksInPath() as NSURL })
        show(skills.count == 1 ? "Copied “\(skills[0].name)” — paste it into a location" : "Copied \(skills.count) skills — paste them into a location",
             symbol: "doc.on.doc.fill")
    }

    var clipboardSkillFolders: [URL] {
        let urls = NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        return Self.skillFolders(in: urls)
    }

    static func skillFolders(in urls: [URL]) -> [URL] {
        urls.map { $0.lastPathComponent == "SKILL.md" ? $0.deletingLastPathComponent() : $0 }
            .filter { FileManager.default.fileExists(atPath: $0.appendingPathComponent("SKILL.md").path) }
    }

    func paste(into dir: URL) {
        let folders = clipboardSkillFolders
        guard !folders.isEmpty else {
            show("The clipboard has no skill folders", symbol: "exclamationmark.circle.fill", isError: true)
            return
        }
        transfer(folders: folders, to: dir, mode: .copy)
    }

    // MARK: Copy / move

    func chooseAndTransfer(_ skills: [Skill], mode: TransferMode) {
        guard let dir = Alerts.chooseFolder(prompt: "\(mode.verb) Here", message: "Choose the skills folder to \(mode.verb.lowercased()) into, e.g. a repo's .claude/skills") else { return }
        transfer(skills, to: dir, mode: mode)
    }

    func transfer(_ skills: [Skill], to dir: URL, mode: TransferMode) {
        if mode == .move {
            let managed = skills.filter { $0.managedReason != nil }
            if let first = managed.first {
                let ok = Alerts.confirm(
                    "Move \(managed.count == 1 ? "“\(first.name)”" : "\(managed.count) managed skills") out of its managed location?",
                    first.managedReason! + " The tool that manages it may put it back or break.",
                    ok: "Move Anyway"
                )
                if !ok { return }
            }
        }
        transfer(folders: skills.map(\.folderURL), to: dir, mode: mode)
    }

    func transfer(folders: [URL], to dir: URL, mode: TransferMode) {
        var done: [URL] = []
        for folder in folders {
            do {
                if let url = try transferOne(folder, to: dir, mode: mode) { done.append(url) }
            } catch {
                Alerts.error(error)
            }
        }
        guard let first = done.first else { return }
        let what = done.count == 1 ? "“\(first.lastPathComponent)”" : "\(done.count) skills"
        show("\(mode.pastTense) \(what) to \(dir.path.tildePath)", symbol: mode == .copy ? "doc.on.doc.fill" : "arrow.right.circle.fill")
        if done.count == 1 { focus(first.appendingPathComponent("SKILL.md").path, mode: .preview) }
        rescan()
    }

    func duplicate(_ skill: Skill) {
        transfer(folders: [skill.folderURL], to: skill.containerURL, mode: .copy)
    }

    private func transferOne(_ source: URL, to dir: URL, mode: TransferMode) throws -> URL? {
        let fm = FileManager.default
        let name = source.lastPathComponent
        let realSource = mode == .copy ? source.resolvingSymlinksInPath() : source
        if mode == .move { try ensureRelocatable(source) }

        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        var dest = dir.appendingPathComponent(name, isDirectory: true)

        if dest.standardizedFileURL.path == source.standardizedFileURL.path {
            guard mode == .copy else { return nil }
            dest = uniqueDestination(in: dir, base: name)
        } else if fm.fileExists(atPath: dest.path) {
            switch Alerts.conflict(name: name, in: dir) {
            case .cancel: return nil
            case .keepBoth: dest = uniqueDestination(in: dir, base: name)
            case .replace: try fm.trashItem(at: dest, resultingItemURL: nil)
            }
        }

        if dest.resolvingSymlinksInPath().path.hasPrefix(realSource.resolvingSymlinksInPath().path + "/") {
            throw SkillError(message: "A skill can't be placed inside its own folder.")
        }

        switch mode {
        case .copy: try fm.copyItem(at: realSource, to: dest)
        case .move: try fm.moveItem(at: source, to: dest)
        }
        if dest.lastPathComponent != name { syncNameField(folder: dest) }
        return dest
    }

    private func uniqueDestination(in dir: URL, base: String) -> URL {
        var n = 2
        var url = dir.appendingPathComponent("\(base)-copy")
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(base)-copy-\(n)")
            n += 1
        }
        return url
    }

    /// Keeps the frontmatter `name` matching the folder after a rename or numbered copy.
    private func syncNameField(folder: URL) {
        let file = folder.appendingPathComponent("SKILL.md")
        guard let text = try? String(contentsOf: file, encoding: .utf8) else { return }
        let updated = Frontmatter.setting("name", to: folder.lastPathComponent, in: text)
        if updated != text { try? updated.write(to: file, atomically: true, encoding: .utf8) }
    }

    /// Guards against moving or trashing something bigger than a skill (a whole repo, home, a scan root).
    private func ensureRelocatable(_ folder: URL) throws {
        let path = folder.standardizedFileURL.path
        let roots = Set(settings.rootURLs.map(\.path) + [Paths.home.path, "/"])
        if roots.contains(path) {
            throw SkillError(message: "“\(folder.lastPathComponent)” is a scan root, not a skill folder, so Skillbook won't move or delete it.")
        }
        if FileManager.default.fileExists(atPath: folder.appendingPathComponent(".git").path) {
            throw SkillError(message: "“\(folder.lastPathComponent)” is a git repository root. Skillbook only moves or deletes skill folders, so do this one in Finder.")
        }
    }

    // MARK: Edit, rename, delete, create

    @discardableResult
    func save(_ text: String, to skill: Skill) -> Bool {
        do {
            try text.write(to: skill.fileURL.resolvingSymlinksInPath(), atomically: true, encoding: .utf8)
            show("Saved “\(skill.name)”", symbol: "checkmark.circle.fill")
            rescan()
            return true
        } catch {
            Alerts.error(error)
            return false
        }
    }

    func rename(_ skill: Skill) {
        guard let input = Alerts.prompt("Rename “\(skill.folderName)”",
                                        "Renames the folder and updates the name in its frontmatter.",
                                        value: skill.folderName, ok: "Rename") else { return }
        let newName = input.kebabCased
        guard !newName.isEmpty, newName != skill.folderName else { return }
        let dest = skill.containerURL.appendingPathComponent(newName)
        do {
            try ensureRelocatable(skill.folderURL)
            if FileManager.default.fileExists(atPath: dest.path) {
                throw SkillError(message: "A folder named “\(newName)” already exists here.")
            }
            try FileManager.default.moveItem(at: skill.folderURL, to: dest)
            syncNameField(folder: dest)
            show("Renamed to “\(newName)”", symbol: "pencil.circle.fill")
            focus(dest.appendingPathComponent("SKILL.md").path, mode: .preview)
            rescan()
        } catch {
            Alerts.error(error)
        }
    }

    func trash(_ skills: [Skill]) {
        guard let first = skills.first else { return }
        let title = skills.count == 1 ? "Move “\(first.name)” to the Trash?" : "Move \(skills.count) skills to the Trash?"
        var message = "The skill folder and everything in it goes to the Trash. You can put it back from there."
        if skills.contains(where: { $0.isSymlink }) { message += " Symlinked skills lose only the link; the original stays." }
        guard Alerts.confirm(title, message, ok: "Move to Trash", destructive: true) else { return }
        var count = 0
        for s in skills {
            do {
                try ensureRelocatable(s.folderURL)
                try FileManager.default.trashItem(at: s.folderURL, resultingItemURL: nil)
                count += 1
            } catch {
                Alerts.error(error)
            }
        }
        if count > 0 {
            show(count == 1 ? "Moved “\(first.name)” to the Trash" : "Moved \(count) skills to the Trash", symbol: "trash.fill")
            rescan()
        }
    }

    func createSkill(in dir: URL) {
        guard let input = Alerts.prompt("New Skill", "Creates \(dir.path.tildePath)/<name>/SKILL.md", value: "", ok: "Create") else { return }
        let name = input.kebabCased
        guard !name.isEmpty else { return }
        let folder = dir.appendingPathComponent(name)
        let file = folder.appendingPathComponent("SKILL.md")
        let title = name.split(separator: "-").map { $0.capitalized }.joined(separator: " ")
        let template = """
        ---
        name: \(name)
        description: Say what this skill does and when an agent should use it. Name the requests or phrases that should trigger it.
        ---

        # \(title)

        ## When to use

        - …

        ## Steps

        1. …
        2. …

        """
        do {
            if FileManager.default.fileExists(atPath: folder.path) {
                throw SkillError(message: "“\(name)” already exists in \(dir.path.tildePath).")
            }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try template.write(to: file, atomically: true, encoding: .utf8)
            show("Created “\(name)”", symbol: "plus.circle.fill")
            focus(file.path, mode: .edit)
            rescan()
        } catch {
            Alerts.error(error)
        }
    }

    func chooseFolderAndCreate() {
        guard let dir = Alerts.chooseFolder(prompt: "Create Here", message: "Choose the skills folder for the new skill") else { return }
        createSkill(in: dir)
    }
}

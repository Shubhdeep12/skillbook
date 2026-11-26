import Foundation

struct ScanOptions: Sendable {
    var roots: [URL]
    var excludedNames: Set<String>
    var excludedPaths: Set<String>
    var maxDepth: Int
}

struct ScanResult: Sendable {
    var skills: [Skill]
    var repos: [URL]
    var duration: TimeInterval
}

enum SkillScanner {
    static func scan(_ options: ScanOptions) -> ScanResult {
        let start = Date()
        let crawl = FileCrawler(options).crawl()
        var classifier = Classifier(home: Paths.home.path)

        var skills = crawl.hits.compactMap { classifier.makeSkill(url: $0.url, isSymlink: $0.isSymlink) }
        markStale(&skills)
        disambiguateTitles(&skills)
        skills.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

        let home = Paths.home.path
        let repos = crawl.repos
            .filter { repo in
                // Skip clones that tools manage inside their config dirs (plugin marketplaces etc).
                guard repo.path.hasPrefix(home + "/") else { return true }
                let top = repo.path.dropFirst(home.count + 1).split(separator: "/").first.map(String.init) ?? ""
                return AgentTool.from(component: top) == nil && !top.hasPrefix(".")
            }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        return ScanResult(skills: skills, repos: repos, duration: Date().timeIntervalSince(start))
    }

    /// Two repos both called "web" become "web · client-a" and "web · client-b".
    private static func disambiguateTitles(_ skills: inout [Skill]) {
        var keysByTitle: [String: Set<String>] = [:]
        for s in skills where s.scope == .project || s.scope == .folder {
            keysByTitle["\(s.scope.rawValue)|\(s.group.title)", default: []].insert(s.group.key)
        }
        for i in skills.indices {
            let s = skills[i]
            guard s.scope == .project || s.scope == .folder,
                  (keysByTitle["\(s.scope.rawValue)|\(s.group.title)"]?.count ?? 0) > 1 else { continue }
            let base = s.repoURL ?? s.containerURL
            let parent = base.deletingLastPathComponent().lastPathComponent
            skills[i].group = GroupInfo(key: s.group.key, title: "\(s.group.title) · \(parent)", subtitle: s.group.subtitle, target: s.group.target)
        }
    }

    /// Plugin caches keep every installed version. Keep the newest copy of each skill visible.
    private static func markStale(_ skills: inout [Skill]) {
        var buckets: [String: [Int]] = [:]
        for (i, s) in skills.enumerated() where s.scope == .plugin && !s.isCatalog {
            buckets["\(s.group.key)|\(s.name)", default: []].append(i)
        }
        for indices in buckets.values where indices.count > 1 {
            let ordered = indices.sorted { a, b in
                let va = skills[a].pluginVersion ?? "", vb = skills[b].pluginVersion ?? ""
                if va != vb { return va.compare(vb, options: .numeric) == .orderedDescending }
                return skills[a].modified > skills[b].modified
            }
            for i in ordered.dropFirst() { skills[i].isStale = true }
        }
    }
}

// MARK: - Crawling

/// Walks the scan roots with readdir (no URL objects), fanning out the top levels across cores.
/// Prunes heavy folders and collects SKILL.md files and git repo roots.
final class FileCrawler: @unchecked Sendable {
    struct Hit: Sendable {
        let url: URL
        let isSymlink: Bool
    }

    private let options: ScanOptions
    private let lock = NSLock()
    private var hits: [String: Hit] = [:]
    private var repos: Set<String> = []
    private let group = DispatchGroup()
    private let queue = DispatchQueue(label: "skillbook.crawl", attributes: .concurrent)
    /// Directories at or above this depth are walked on their own task.
    private let fanOutDepth = 3

    init(_ options: ScanOptions) { self.options = options }

    func crawl() -> (hits: [Hit], repos: [URL]) {
        var seen = Set<String>()
        for root in options.roots where root.isDirectory {
            let path = root.resolvingSymlinksInPath().path
            guard seen.insert(path).inserted else { continue }
            schedule(path, depth: 0)
        }
        group.wait()
        return (Array(hits.values), repos.map { URL(fileURLWithPath: $0) })
    }

    private func schedule(_ path: String, depth: Int) {
        group.enter()
        queue.async { [self] in
            walk(path, depth: depth)
            group.leave()
        }
    }

    private func walk(_ path: String, depth: Int) {
        guard let dir = opendir(path) else { return }
        defer { closedir(dir) }
        var subdirs: [String] = []

        while let entry = readdir(dir) {
            let name = withUnsafePointer(to: entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(entry.pointee.d_namlen) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            let full = path == "/" ? "/" + name : path + "/" + name

            switch Int32(entry.pointee.d_type) {
            case DT_DIR:
                if name == ".git" {
                    addRepo(path)
                } else if !options.excludedNames.contains(name), !options.excludedPaths.contains(full),
                          depth + 1 < options.maxDepth, !Self.isPackage(name) {
                    subdirs.append(full)
                }
            case DT_REG:
                if name == "SKILL.md" { add(full, link: false) }
                else if name == ".git" { addRepo(path) } // worktree or submodule
            case DT_LNK:
                if name == "SKILL.md" {
                    add(full, link: true)
                } else if access(full + "/SKILL.md", F_OK) == 0 {
                    add(full + "/SKILL.md", link: true)
                }
            default:
                break
            }
        }

        for sub in subdirs {
            if depth < fanOutDepth { schedule(sub, depth: depth + 1) } else { walk(sub, depth: depth + 1) }
        }
    }

    private static let packageExtensions: Set<String> = ["app", "framework", "bundle", "xcodeproj", "xcworkspace",
                                                        "photoslibrary", "musiclibrary", "plugin", "kext", "xcassets"]
    private static func isPackage(_ name: String) -> Bool {
        guard let dot = name.lastIndex(of: "."), dot != name.startIndex else { return false }
        return packageExtensions.contains(String(name[name.index(after: dot)...]).lowercased())
    }

    private func add(_ path: String, link: Bool) {
        lock.lock(); defer { lock.unlock() }
        if hits[path] == nil { hits[path] = Hit(url: URL(fileURLWithPath: path), isSymlink: link) }
    }

    private func addRepo(_ path: String) {
        lock.lock(); defer { lock.unlock() }
        repos.insert(path)
    }
}

// MARK: - Classification

private struct PluginManifest {
    let name: String
    let version: String?
}

/// Works out the scope, tool and sidebar location for a SKILL.md from its path.
struct Classifier {
    let home: String
    private var repoCache: [String: String] = [:] // dir → repo path, or "" for none
    private var manifests: [String: PluginManifest] = [:]
    private var noManifest: Set<String> = []

    init(home: String) { self.home = home }

    mutating func makeSkill(url: URL, isSymlink: Bool) -> Skill? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let text = String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
        let fm = Frontmatter.parse(text)
        let folder = url.deletingLastPathComponent()
        let validity = SkillValidator.validate(fm, folderName: folder.lastPathComponent)
        let place = locate(folder)
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)

        return Skill(
            fileURL: url,
            name: fm["name"]?.nonEmpty ?? folder.lastPathComponent,
            summary: fm["description"]?.trimmed ?? "",
            fields: fm.fields,
            validity: validity,
            scope: place.scope,
            tool: place.tool,
            group: place.group,
            repoURL: place.repo,
            pluginVersion: place.version,
            managedReason: place.managedReason,
            isSymlink: isSymlink,
            isCatalog: place.isCatalog,
            modified: attrs?[.modificationDate] as? Date ?? .distantPast,
            byteSize: data.count
        )
    }

    private struct Placement {
        var scope: SkillScope
        var tool: AgentTool
        var group: GroupInfo
        var repo: URL? = nil
        var version: String? = nil
        var managedReason: String? = nil
        var isCatalog = false
    }

    private mutating func locate(_ folder: URL) -> Placement {
        let path = folder.path
        let underHome = path.hasPrefix(home + "/")
        let rel = underHome ? String(path.dropFirst(home.count + 1)) : String(path.dropFirst())
        let comps = rel.split(separator: "/").map(String.init)

        if underHome, let top = comps.first, let tool = AgentTool.from(component: top) {
            return locateInConfig(folder: folder, comps: comps, top: top, tool: tool)
        }

        let tool = comps.reversed().lazy.compactMap(AgentTool.from(component:)).first ?? .generic

        if let repo = repoRoot(for: folder) {
            let repoURL = URL(fileURLWithPath: repo)
            return Placement(
                scope: .project,
                tool: tool,
                group: GroupInfo(
                    key: "project:\(repo)",
                    title: repoURL.lastPathComponent,
                    subtitle: repo.tildePath,
                    target: repoURL.appendingPathComponent(".claude/skills")
                ),
                repo: repoURL
            )
        }

        let container = folder.deletingLastPathComponent()
        var titled = container
        if container.lastPathComponent == "skills" {
            titled = container.deletingLastPathComponent()
            if AgentTool.from(component: titled.lastPathComponent) != nil {
                titled = titled.deletingLastPathComponent()
            }
        }
        return Placement(
            scope: .folder,
            tool: tool,
            group: GroupInfo(key: "folder:\(container.path)", title: titled.lastPathComponent, subtitle: container.path.tildePath, target: container)
        )
    }

    private mutating func locateInConfig(folder: URL, comps: [String], top: String, tool: AgentTool) -> Placement {
        let lower = comps.map { $0.lowercased() }
        let topURL = URL(fileURLWithPath: home).appendingPathComponent(top)
        let variant = top.split(separator: "-", maxSplits: 1).dropFirst().first.map(String.init)
        let toolTitle = tool.title + (variant.map { " · \($0)" } ?? "")

        let isPlugin = lower.contains { ["plugins", "extensions", "vendor_imports"].contains($0) || $0.hasSuffix("marketplaces") }
        if isPlugin {
            let isCatalog = lower.contains { $0 == "marketplaces" || $0.hasSuffix("-marketplaces") || $0 == ".tmp" }
            let manifest = findManifest(from: folder, stopAt: topURL.path)
            let name = manifest?.name ?? Self.heuristicPluginName(comps)
            let version = manifest?.version ?? Self.heuristicVersion(comps)
            let kind = lower.contains("extensions") ? "extension" : "plugin"
            return Placement(
                scope: .plugin,
                tool: tool,
                group: GroupInfo(key: "plugin:\(top):\(name)", title: name, subtitle: "\(toolTitle) \(kind)", target: nil),
                version: version,
                managedReason: isCatalog
                    ? "Marketplace catalog copy of “\(name)”. It is not what the agent loads, and updates replace it."
                    : "Installed by the “\(name)” \(kind). Plugin updates replace these files.",
                isCatalog: isCatalog
            )
        }

        if lower.contains("builtin") || lower.contains(".system") || lower.contains("skills-cursor") {
            return Placement(
                scope: .builtin,
                tool: tool,
                group: GroupInfo(key: "builtin:\(top)", title: "\(toolTitle) built-ins", subtitle: "~/\(top)", target: nil),
                managedReason: "Bundled with \(tool.title). App updates replace these files."
            )
        }

        let synced = lower.contains("synced")
        let skillsDir = topURL.appendingPathComponent("skills")
        return Placement(
            scope: .user,
            tool: tool,
            group: GroupInfo(
                key: "user:\(top)\(synced ? ":synced" : "")",
                title: toolTitle + (synced ? " · synced" : ""),
                subtitle: synced ? "Synced from claude.ai" : skillsDir.path.tildePath,
                target: synced ? nil : skillsDir
            ),
            managedReason: synced ? "Synced from your claude.ai account. The next sync may overwrite local edits." : nil
        )
    }

    private static func heuristicPluginName(_ comps: [String]) -> String {
        if comps.contains("vendor_imports") { return "vendor imports" }
        if let i = comps.lastIndex(of: "cache"), i + 2 < comps.count { return comps[i + 2] }
        if let i = comps.lastIndex(where: { $0.hasSuffix("marketplaces") }), i + 1 < comps.count {
            if i + 3 < comps.count, ["plugins", "external_plugins"].contains(comps[i + 2]) { return comps[i + 3] }
            return comps[i + 1]
        }
        if let i = comps.lastIndex(of: "extensions"), i + 1 < comps.count { return comps[i + 1] }
        if let i = comps.lastIndex(of: "local"), i + 1 < comps.count { return comps[i + 1] }
        if let i = comps.lastIndex(of: "skills"), i > 0 { return comps[i - 1] }
        return comps.dropLast().last ?? "plugin"
    }

    private static func heuristicVersion(_ comps: [String]) -> String? {
        if let i = comps.lastIndex(of: "cache"), i + 3 < comps.count { return comps[i + 3] }
        return nil
    }

    private mutating func findManifest(from folder: URL, stopAt: String) -> PluginManifest? {
        var dir = folder.deletingLastPathComponent()
        while dir.path.count > stopAt.count && dir.path.hasPrefix(stopAt) {
            let p = dir.path
            if let m = manifests[p] { return m }
            if !noManifest.contains(p) {
                if let m = Self.readManifest(in: dir) {
                    manifests[p] = m
                    return m
                }
                noManifest.insert(p)
            }
            dir = dir.deletingLastPathComponent()
        }
        return nil
    }

    private static func readManifest(in dir: URL) -> PluginManifest? {
        let candidates = [".claude-plugin/plugin.json", ".cursor-plugin/plugin.json", ".codex-plugin/plugin.json",
                          "plugin.json", "gemini-extension.json", "package.json"]
        for rel in candidates {
            let url = dir.appendingPathComponent(rel)
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let name = (json["name"] as? String)?.nonEmpty else { continue }
            return PluginManifest(name: name, version: json["version"] as? String)
        }
        return nil
    }

    private mutating func repoRoot(for folder: URL) -> String? {
        var visited: [String] = []
        var dir = folder
        var result: String?
        while true {
            let p = dir.path
            if p == home || p == "/" || p.isEmpty { break }
            if let cached = repoCache[p] {
                result = cached.isEmpty ? nil : cached
                break
            }
            visited.append(p)
            if FileManager.default.fileExists(atPath: p + "/.git") {
                result = p
                break
            }
            dir = dir.deletingLastPathComponent()
        }
        for v in visited { repoCache[v] = result ?? "" }
        return result
    }
}

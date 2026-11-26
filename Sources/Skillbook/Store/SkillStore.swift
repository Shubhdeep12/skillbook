import AppKit
import Observation
import SwiftUI

struct Toast: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let symbol: String
    var isError = false
}

/// Asks the manager window to select a skill and show it in a given mode.
struct FocusRequest: Equatable {
    let id = UUID()
    let skillID: String
    let mode: DetailMode
}

@MainActor
@Observable
final class SkillStore {
    let settings = AppSettings()

    private(set) var allSkills: [Skill] = []
    private(set) var repos: [URL] = []
    private(set) var isScanning = false
    private(set) var lastScan: Date?
    private(set) var lastDuration: TimeInterval = 0
    var toast: Toast?
    var focusRequest: FocusRequest?
    /// The editor holds changes that aren't saved yet. Updates wait for these.
    var hasUnsavedEdits = false

    @ObservationIgnored private var watcher: FileWatcher?
    @ObservationIgnored private var pendingRescan: Task<Void, Never>?
    @ObservationIgnored private var toastTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0

    init() {
        rescan()
        configureWatcher()
    }

    // MARK: Visible data

    var skills: [Skill] { allSkills.filter(isVisible) }

    func isVisible(_ s: Skill) -> Bool {
        (settings.showUnverified || s.validity.isSkill) && (settings.showPluginExtras || !s.isExtra)
    }

    var hiddenCount: Int { allSkills.count - skills.count }

    func skill(id: String?) -> Skill? {
        guard let id else { return nil }
        return allSkills.first { $0.id == id }
    }

    func groups(of skills: [Skill]) -> [SkillGroup] {
        var dict: [String: SkillGroup] = [:]
        for s in skills {
            dict[s.group.key, default: SkillGroup(info: s.group, scope: s.scope, tool: s.tool, count: 0)].count += 1
        }
        return dict.values.sorted {
            $0.info.title.localizedStandardCompare($1.info.title) == .orderedAscending
        }
    }

    // MARK: Destinations

    var userDestinations: [Destination] {
        let fm = FileManager.default
        let home = Paths.home
        let tops = ((try? fm.contentsOfDirectory(atPath: home.path)) ?? [])
            .filter { AgentTool.from(component: $0) != nil && $0 != ".github" }
            .sorted()
        return tops.compactMap { top -> Destination? in
            let skillsDir = home.appendingPathComponent(top).appendingPathComponent("skills")
            let always = top == ".claude" || top == ".agents"
            guard always || skillsDir.isDirectory, let tool = AgentTool.from(component: top) else { return nil }
            let variant = top.split(separator: "-", maxSplits: 1).dropFirst().first.map { " · \($0)" } ?? ""
            return Destination(url: skillsDir, title: tool.title + variant, subtitle: skillsDir.path.tildePath)
        }
    }

    /// Repos that already hold skills, with each skills folder found in them.
    var projectDestinations: [RepoDestinations] {
        var containers: [String: Set<String>] = [:]
        for s in allSkills where s.scope == .project {
            guard let repo = s.repoURL else { continue }
            containers[repo.path, default: []].insert(s.containerURL.path)
        }
        return containers.keys.sorted { URL(fileURLWithPath: $0).lastPathComponent.localizedStandardCompare(URL(fileURLWithPath: $1).lastPathComponent) == .orderedAscending }
            .map { repoPath in
                let repo = URL(fileURLWithPath: repoPath)
                var dirs = containers[repoPath] ?? []
                dirs.insert(repo.appendingPathComponent(".claude/skills").path)
                let dests = dirs.sorted().map { dir in
                    Destination(url: URL(fileURLWithPath: dir), title: String(dir.dropFirst(repoPath.count + 1)), subtitle: dir.tildePath)
                }
                return RepoDestinations(repo: repo, containers: dests)
            }
    }

    /// Git repos with no skills yet.
    var otherRepos: [URL] {
        let withSkills = Set(projectDestinations.map(\.repo.path))
        return repos.filter { !withSkills.contains($0.path) }
    }

    // MARK: Scanning

    func rescan() {
        generation += 1
        let gen = generation
        let options = settings.scanOptions()
        isScanning = true
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { SkillScanner.scan(options) }.value
            guard let self, gen == self.generation else { return }
            self.allSkills = result.skills
            self.repos = result.repos
            self.lastDuration = result.duration
            self.lastScan = Date()
            self.isScanning = false
        }
    }

    func scheduleRescan() {
        pendingRescan?.cancel()
        pendingRescan = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            self?.rescan()
        }
    }

    func settingsChanged() {
        configureWatcher()
        rescan()
    }

    func configureWatcher() {
        watcher?.stop()
        watcher = nil
        guard settings.watchForChanges else { return }
        let excludedNames = Set(settings.excludedNames)
        let home = Paths.home
        watcher = FileWatcher(
            paths: settings.rootURLs.map(\.path),
            excluding: [home.appendingPathComponent("Library").path, home.appendingPathComponent(".Trash").path]
        ) { [weak self] paths in
            let relevant = paths.contains { path in
                guard path.hasSuffix("/SKILL.md") || path.contains("/skills/") || path.hasSuffix("/skills") else { return false }
                return !path.split(separator: "/").contains { excludedNames.contains(String($0)) || $0 == ".git" }
            }
            guard relevant else { return }
            MainActor.assumeIsolated { self?.scheduleRescan() }
        }
        watcher?.start()
    }

    // MARK: Feedback

    func show(_ message: String, symbol: String = "checkmark.circle.fill", isError: Bool = false) {
        withAnimation(.spring(duration: 0.3)) {
            toast = Toast(message: message, symbol: symbol, isError: isError)
        }
        toastTask?.cancel()
        toastTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.6))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { self?.toast = nil }
        }
    }

    func focus(_ skillID: String, mode: DetailMode) {
        focusRequest = FocusRequest(skillID: skillID, mode: mode)
    }
}

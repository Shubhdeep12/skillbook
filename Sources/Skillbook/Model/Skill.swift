import Foundation

/// Where a skill lives, from the point of view of the agent that loads it.
enum SkillScope: String, CaseIterable, Sendable, Hashable, Identifiable {
    case user, project, plugin, builtin, folder

    var id: String { rawValue }

    var title: String {
        switch self {
        case .user: "User"
        case .project: "Projects"
        case .plugin: "Plugins"
        case .builtin: "Built-in"
        case .folder: "Folders"
        }
    }

    var singular: String {
        switch self {
        case .user: "User"
        case .project: "Project"
        case .plugin: "Plugin"
        case .builtin: "Built-in"
        case .folder: "Folder"
        }
    }

    var symbol: String {
        switch self {
        case .user: "person"
        case .project: "folder"
        case .plugin: "puzzlepiece.extension"
        case .builtin: "shippingbox"
        case .folder: "tray"
        }
    }
}

/// The coding agent a skill is installed for, inferred from its path.
enum AgentTool: String, CaseIterable, Sendable, Hashable {
    case claude, cursor, codex, gemini, antigravity, agents, copilot, windsurf, opencode, kiro, generic

    var title: String {
        switch self {
        case .claude: "Claude"
        case .cursor: "Cursor"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .antigravity: "Antigravity"
        case .agents: "Agents"
        case .copilot: "Copilot"
        case .windsurf: "Windsurf"
        case .opencode: "OpenCode"
        case .kiro: "Kiro"
        case .generic: "Skill"
        }
    }

    var symbol: String {
        switch self {
        case .claude: "sparkle"
        case .cursor: "cursorarrow.rays"
        case .codex: "terminal.fill"
        case .gemini: "sparkles"
        case .antigravity: "arrow.up.forward.circle.fill"
        case .agents: "person.2.fill"
        case .copilot: "airplane"
        case .windsurf: "wind"
        case .opencode: "chevron.left.forwardslash.chevron.right"
        case .kiro: "bolt.fill"
        case .generic: "doc.text.fill"
        }
    }

    /// Infer a tool from one path component such as `.claude` or `.cursor`.
    static func from(component c: String) -> AgentTool? {
        let s = c.lowercased()
        if s.hasPrefix(".claude") { return .claude }
        if s.hasPrefix(".cursor") { return .cursor }
        if s.hasPrefix(".codex") { return .codex }
        if s.hasPrefix(".gemini") { return .gemini }
        if s.hasPrefix(".antigravity") { return .antigravity }
        if s == ".agents" || s == ".agent" { return .agents }
        if s == ".github" { return .copilot }
        if s.hasPrefix(".windsurf") || s.hasPrefix(".codeium") { return .windsurf }
        if s.hasPrefix(".opencode") { return .opencode }
        if s.hasPrefix(".kiro") { return .kiro }
        return nil
    }
}

enum Validity: Sendable, Hashable {
    case valid
    case warnings([String])
    case invalid(String)

    /// False when the file does not look like a skill at all.
    var isSkill: Bool {
        if case .invalid = self { return false }
        return true
    }

    var issues: [String] {
        switch self {
        case .valid: []
        case .warnings(let w): w
        case .invalid(let reason): [reason]
        }
    }

    var hasIssues: Bool { self != .valid }
}

struct FrontmatterField: Sendable, Hashable, Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

/// Identity of the sidebar location a skill belongs to (a repo, a plugin, `~/.claude/skills`…).
struct GroupInfo: Sendable, Hashable {
    let key: String
    let title: String
    let subtitle: String
    /// Folder where new or pasted skills go for this location, when it accepts them.
    let target: URL?
}

struct Skill: Identifiable, Sendable, Hashable {
    let fileURL: URL
    let name: String
    let summary: String
    let fields: [FrontmatterField]
    let validity: Validity
    let scope: SkillScope
    let tool: AgentTool
    var group: GroupInfo
    let repoURL: URL?
    let pluginVersion: String?
    let managedReason: String?
    let isSymlink: Bool
    /// A copy inside a marketplace catalog rather than an installed plugin.
    let isCatalog: Bool
    /// An older or duplicate copy of an installed plugin skill.
    var isStale: Bool = false
    let modified: Date
    let byteSize: Int

    var id: String { fileURL.path }
    var folderURL: URL { fileURL.deletingLastPathComponent() }
    var folderName: String { folderURL.lastPathComponent }
    var containerURL: URL { folderURL.deletingLastPathComponent() }
    var displayPath: String { fileURL.path.tildePath }
    var isExtra: Bool { isStale || isCatalog }
}

struct SkillGroup: Identifiable, Hashable {
    let info: GroupInfo
    let scope: SkillScope
    let tool: AgentTool
    var count: Int
    var id: String { info.key }
}

struct Destination: Identifiable, Hashable {
    let url: URL
    let title: String
    let subtitle: String
    var id: String { url.path }
}

struct RepoDestinations: Identifiable, Hashable {
    let repo: URL
    let containers: [Destination]
    var id: String { repo.path }
    var name: String { repo.lastPathComponent }
}

enum TransferMode: Sendable {
    case copy, move
    var verb: String { self == .copy ? "Copy" : "Move" }
    var pastTense: String { self == .copy ? "Copied" : "Moved" }
}

enum DetailMode: String, CaseIterable, Hashable {
    case preview, edit, files
    var title: String { rawValue.capitalized }
    var symbol: String {
        switch self {
        case .preview: "eye"
        case .edit: "pencil"
        case .files: "list.bullet.indent"
        }
    }
}

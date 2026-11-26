import AppKit
import SwiftUI
import UniformTypeIdentifiers

extension AgentTool {
    var color: Color {
        switch self {
        case .claude: Color(red: 0.85, green: 0.47, blue: 0.34)
        case .cursor: Color(red: 0.30, green: 0.32, blue: 0.36)
        case .codex: Color(red: 0.07, green: 0.62, blue: 0.50)
        case .gemini: Color(red: 0.26, green: 0.52, blue: 0.96)
        case .antigravity: Color(red: 0.55, green: 0.36, blue: 0.96)
        case .agents: Color(red: 0.35, green: 0.40, blue: 0.90)
        case .copilot: Color(red: 0.42, green: 0.30, blue: 0.75)
        case .windsurf: Color(red: 0.05, green: 0.66, blue: 0.75)
        case .opencode: Color(red: 0.90, green: 0.55, blue: 0.15)
        case .kiro: Color(red: 0.86, green: 0.30, blue: 0.55)
        case .generic: Color(red: 0.50, green: 0.53, blue: 0.58)
        }
    }
}

/// A small colored dot, optionally followed by the tool name.
struct ToolTag: View {
    let tool: AgentTool
    var showsName = true

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(tool.color)
                .frame(width: 7, height: 7)
            if showsName {
                Text(tool.title)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .help(tool.title)
    }
}

/// The plain document glyph used for a skill.
struct SkillGlyph: View {
    var isSkill = true
    var size: CGFloat = 15
    var weight: Font.Weight = .regular

    var body: some View {
        Image(systemName: isSkill ? "doc.text" : "doc")
            .font(.system(size: size, weight: weight))
            .foregroundStyle(isSkill ? .secondary : .tertiary)
            .frame(width: size * 1.25)
    }
}

enum FinderIcons {
    static let folder: NSImage = NSWorkspace.shared.icon(for: .folder)
}

/// Finder folder for user, project and folder locations; a glyph for plugins and built-ins.
struct LocationIcon: View {
    let scope: SkillScope
    var size: CGFloat = 16

    var body: some View {
        switch scope {
        case .plugin, .builtin:
            Image(systemName: scope.symbol)
                .font(.system(size: size * 0.78))
                .foregroundStyle(.secondary)
                .frame(width: size, height: size)
        default:
            Image(nsImage: FinderIcons.folder)
                .resizable()
                .interpolation(.high)
                .frame(width: size, height: size)
        }
    }
}

struct Chip: View {
    let text: String
    var symbol: String? = nil
    var dot: Color? = nil
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let dot { Circle().fill(dot).frame(width: 7, height: 7) }
            if let symbol { Image(systemName: symbol).imageScale(.small) }
            Text(text).lineLimit(1)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(tint.opacity(0.12)))
    }
}

struct ToastView: View {
    let toast: Toast

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: toast.symbol)
                .foregroundStyle(toast.isError ? .orange : .green)
            Text(toast.message)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.08)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.bottom, 16)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// "Copy To" / "Move To" menu listing user folders, repos and a folder picker.
struct DestinationMenu: View {
    @Environment(SkillStore.self) private var store
    let skills: [Skill]
    let mode: TransferMode

    var body: some View {
        Menu {
            Section("User") {
                ForEach(store.userDestinations) { d in
                    Button { store.transfer(skills, to: d.url, mode: mode) } label: {
                        Text("\(d.title)  —  \(d.subtitle)")
                    }
                }
            }
            let projects = store.projectDestinations
            if !projects.isEmpty {
                Section("Projects") {
                    ForEach(projects) { repo in
                        Menu(repo.name) {
                            ForEach(repo.containers) { d in
                                Button(d.title) { store.transfer(skills, to: d.url, mode: mode) }
                            }
                        }
                    }
                }
            }
            let others = store.otherRepos
            if !others.isEmpty {
                Menu("Other Repositories") {
                    ForEach(others, id: \.path) { repo in
                        Button(repo.lastPathComponent) {
                            store.transfer(skills, to: repo.appendingPathComponent(".claude/skills"), mode: mode)
                        }
                    }
                }
            }
            Divider()
            Button("Choose Folder…") { store.chooseAndTransfer(skills, mode: mode) }
        } label: {
            Label("\(mode.verb) To", systemImage: mode == .copy ? "doc.on.doc" : "folder.badge.plus")
        }
    }
}

/// Every action for one or more skills. Used by context menus and the detail toolbar.
struct SkillActionsMenu: View {
    @Environment(SkillStore.self) private var store
    let skills: [Skill]
    var onEdit: ((Skill) -> Void)? = nil

    var body: some View {
        if let one = skills.first, skills.count == 1 {
            if let onEdit {
                Button { onEdit(one) } label: { Label("Edit", systemImage: "pencil") }
            }
            Button { store.openInDefaultEditor(one) } label: { Label("Open in Default App", systemImage: "arrow.up.forward.app") }
        }
        Button { store.reveal(skills) } label: { Label("Show in Finder", systemImage: "folder") }
        Divider()
        Button { store.copyToClipboard(skills) } label: { Label("Copy Skill", systemImage: "doc.on.doc") }
        Button { store.copyPaths(skills) } label: { Label("Copy Path", systemImage: "link") }
        if let one = skills.first, skills.count == 1 {
            Button { store.copyContents(one) } label: { Label("Copy SKILL.md Contents", systemImage: "text.alignleft") }
        }
        Divider()
        DestinationMenu(skills: skills, mode: .copy)
        DestinationMenu(skills: skills, mode: .move)
        if let one = skills.first, skills.count == 1 {
            Button { store.duplicate(one) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
            Button { store.rename(one) } label: { Label("Rename…", systemImage: "character.cursor.ibeam") }
        }
        Divider()
        Button(role: .destructive) { store.trash(skills) } label: { Label("Move to Trash", systemImage: "trash") }
    }
}

struct IssuesCard: View {
    let validity: Validity

    var body: some View {
        let invalid = !validity.isSkill
        VStack(alignment: .leading, spacing: 6) {
            Label(invalid ? "Not recognised as a skill" : "Suggestions",
                  systemImage: invalid ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(invalid ? .red : .orange)
            ForEach(validity.issues, id: \.self) { issue in
                Text("• \(issue)").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill((invalid ? Color.red : .orange).opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder((invalid ? Color.red : .orange).opacity(0.2)))
    }
}

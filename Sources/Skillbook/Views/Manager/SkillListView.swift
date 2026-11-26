import AppKit
import SwiftUI

struct SkillListView: View {
    @Environment(SkillStore.self) private var store
    let skills: [Skill]
    let title: String
    let pasteTarget: URL?
    let showSections: Bool
    @Binding var selection: Set<String>
    @Binding var sort: SkillSort
    let onEdit: (Skill) -> Void

    private struct ListSection: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        var skills: [Skill]
    }

    private var sections: [ListSection] {
        guard showSections else { return [ListSection(id: "all", title: "", subtitle: "", skills: skills)] }
        var order: [String] = []
        var dict: [String: ListSection] = [:]
        for s in skills {
            if dict[s.group.key] == nil {
                order.append(s.group.key)
                dict[s.group.key] = ListSection(id: s.group.key, title: s.group.title, subtitle: s.group.subtitle, skills: [])
            }
            dict[s.group.key]?.skills.append(s)
        }
        let ordered = order.compactMap { dict[$0] }
        guard sort != .modified else { return ordered }
        let scopes = SkillScope.allCases
        return ordered.sorted { a, b in
            let sa = scopes.firstIndex(of: a.skills[0].scope) ?? 0, sb = scopes.firstIndex(of: b.skills[0].scope) ?? 0
            return sa != sb ? sa < sb : a.title.localizedStandardCompare(b.title) == .orderedAscending
        }
    }

    private var isSingleLocation: Bool { pasteTarget != nil || Set(skills.map(\.group.key)).count <= 1 }

    private func selected(_ ids: Set<String>) -> [Skill] {
        skills.filter { ids.contains($0.id) }
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(sections) { section in
                if showSections {
                    Section {
                        rows(section.skills)
                    } header: {
                        HStack(alignment: .firstTextBaseline) {
                            Text(section.title)
                            Spacer()
                            Text(section.subtitle).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.head)
                        }
                    }
                } else {
                    rows(section.skills)
                }
            }
        }
        .listStyle(.inset)
        .contextMenu(forSelectionType: String.self) { ids in
            let chosen = selected(ids)
            if !chosen.isEmpty { SkillActionsMenu(skills: chosen, onEdit: onEdit) }
        } primaryAction: { ids in
            if let first = selected(ids).first { onEdit(first) }
        }
        .onCopyCommand {
            let chosen = selected(selection)
            store.copyToClipboard(chosen)
            return chosen.map { NSItemProvider(object: $0.folderURL as NSURL) }
        }
        .onPasteCommand(of: [.fileURL]) { _ in paste() }
        .onDeleteCommand { store.trash(selected(selection)) }
        .overlay {
            if skills.isEmpty && !store.isScanning {
                ContentUnavailableView("No Skills", systemImage: "magnifyingglass",
                                       description: Text("Nothing here matches. Try another location or search."))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .navigationTitle(title)
        .navigationSubtitle("\(skills.count) skill\(skills.count == 1 ? "" : "s")")
        .toolbar {
            ToolbarItemGroup {
                Menu {
                    Picker("Sort By", selection: $sort) {
                        ForEach(SkillSort.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    @Bindable var settings = store.settings
                    Toggle("Show Old Plugin Versions & Catalog Copies", isOn: $settings.showPluginExtras)
                    Toggle("Show Files That Fail the Skill Check", isOn: $settings.showUnverified)
                } label: {
                    Label("View Options", systemImage: "line.3.horizontal.decrease.circle")
                }
                .help("Sort and filter")

                Button {
                    if let target = pasteTarget ?? store.userDestinations.first?.url {
                        store.createSkill(in: target)
                    } else {
                        store.chooseFolderAndCreate()
                    }
                } label: {
                    Label("New Skill", systemImage: "plus")
                }
                .keyboardShortcut("n")
                .help("New skill in \(pasteTarget?.path.tildePath ?? "~/.claude/skills")")

                Button { store.rescan() } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r")
                .disabled(store.isScanning)
                .help("Scan for skills again (⌘R)")
            }
        }
    }

    private func rows(_ list: [Skill]) -> some View {
        ForEach(list) { skill in
            SkillRow(skill: skill, showLocation: !showSections && !isSingleLocation)
                .tag(skill.id)
                // itemProvider uses the list's own drag handling. onDrag adds a drag
                // gesture to each row that competes with the click that selects it.
                .itemProvider {
                    NSItemProvider(object: skill.folderURL.resolvingSymlinksInPath() as NSURL)
                }
        }
    }

    private func paste() {
        if let target = pasteTarget {
            store.paste(into: target)
        } else if let first = selected(selection).first, first.group.target != nil {
            store.paste(into: first.containerURL)
        } else if let dir = Alerts.chooseFolder(prompt: "Paste Here", message: "Choose the skills folder to paste into") {
            store.paste(into: dir)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if store.hiddenCount > 0 {
            HStack(spacing: 6) {
                Image(systemName: "eye.slash")
                Text("\(store.hiddenCount) duplicate or unverified files hidden")
                Spacer()
            }
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.bar)
        }
    }
}

struct SkillRow: View {
    let skill: Skill
    var showLocation = true

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            SkillGlyph(isSkill: skill.validity.isSkill, size: 16, weight: .light)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(skill.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    if let v = skill.pluginVersion, !showLocation {
                        Text("v\(v)").font(.system(size: 10).monospacedDigit()).foregroundStyle(.tertiary)
                    }
                    if skill.isSymlink {
                        Image(systemName: "arrow.turn.up.right").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                            .help("Symlink")
                    }
                    if skill.validity.hasIssues {
                        Image(systemName: skill.validity.isSkill ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(skill.validity.isSkill ? .orange : .red)
                            .help(skill.validity.issues.joined(separator: "\n"))
                    }
                    if skill.isExtra {
                        Text(skill.isCatalog ? "CATALOG" : "OLD")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(RoundedRectangle(cornerRadius: 3).strokeBorder(.secondary.opacity(0.5)))
                    }
                    Spacer(minLength: 6)
                    ToolTag(tool: skill.tool)
                }
                if !skill.summary.isEmpty {
                    Text(skill.summary)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if showLocation {
                    HStack(spacing: 4) {
                        Image(systemName: skill.scope.symbol)
                        Text(skill.group.title)
                        if let v = skill.pluginVersion { Text("· v\(v)").monospacedDigit() }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

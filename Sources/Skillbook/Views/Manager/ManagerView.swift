import AppKit
import SwiftUI

enum SidebarItem: Hashable {
    case all
    case attention
    case scope(SkillScope)
    case group(String)
}

enum SkillSort: String, CaseIterable {
    case name = "Name", modified = "Date Modified", location = "Location"
}

struct ManagerView: View {
    @Environment(SkillStore.self) private var store
    @State private var sidebar: SidebarItem? = .all
    @State private var selection: Set<String> = []
    @State private var search = ""
    @State private var sort: SkillSort = .name
    @State private var mode: DetailMode = .preview

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $sidebar)
                .navigationSplitViewColumnWidth(min: 210, ideal: 245, max: 340)
        } content: {
            SkillListView(
                skills: filtered,
                title: sidebarTitle,
                pasteTarget: pasteTarget,
                showSections: !isSingleGroup,
                selection: $selection,
                sort: $sort,
                onEdit: { skill in
                    selection = [skill.id]
                    mode = .edit
                }
            )
            .navigationSplitViewColumnWidth(min: 290, ideal: 350, max: 520)
        } detail: {
            detail
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Search skills")
        .overlay(alignment: .bottom) {
            if let toast = store.toast { ToastView(toast: toast) }
        }
        .onChange(of: store.focusRequest, initial: true) { _, request in
            guard let request else { return }
            if let s = store.skill(id: request.skillID), !store.isVisible(s) || !matchesSidebar(s) {
                sidebar = .all
            } else if store.skill(id: request.skillID) == nil {
                sidebar = .all
            }
            search = ""
            selection = [request.skillID]
            mode = request.mode
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    // MARK: Filtering

    private var isSingleGroup: Bool {
        if case .group = sidebar { return true }
        return false
    }

    private func matchesSidebar(_ s: Skill) -> Bool {
        switch sidebar ?? .all {
        case .all: true
        case .attention: s.validity.hasIssues
        case .scope(let scope): s.scope == scope
        case .group(let key): s.group.key == key
        }
    }

    private var filtered: [Skill] {
        let q = search.trimmed.lowercased()
        let list = store.skills.filter { s in
            guard matchesSidebar(s) else { return false }
            guard !q.isEmpty else { return true }
            return s.name.lowercased().contains(q)
                || s.summary.lowercased().contains(q)
                || s.group.title.lowercased().contains(q)
                || s.fileURL.path.lowercased().contains(q)
        }
        switch sort {
        case .name: return list
        case .modified: return list.sorted { $0.modified > $1.modified }
        case .location:
            return list.sorted {
                let order = $0.group.title.localizedStandardCompare($1.group.title)
                return order == .orderedSame ? $0.name < $1.name : order == .orderedAscending
            }
        }
    }

    private var sidebarTitle: String {
        switch sidebar ?? .all {
        case .all: "All Skills"
        case .attention: "Needs Attention"
        case .scope(let scope): scope.title
        case .group(let key): store.allSkills.first { $0.group.key == key }?.group.title ?? "Skills"
        }
    }

    private var pasteTarget: URL? {
        guard case .group(let key) = sidebar else { return nil }
        return store.allSkills.first { $0.group.key == key }?.group.target
    }

    // MARK: Detail

    @ViewBuilder
    private var detail: some View {
        let chosen = selection.compactMap { store.skill(id: $0) }
        if chosen.count == 1, let skill = chosen.first {
            SkillDetailView(skill: skill, mode: $mode)
        } else if chosen.count > 1 {
            MultiSelectionView(skills: chosen)
        } else if store.isScanning && store.allSkills.isEmpty {
            ProgressView("Looking for skills…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label("Select a Skill", systemImage: "book")
            } description: {
                Text("\(store.skills.count) skills found across \(store.groups(of: store.skills).count) locations.")
            }
        }
    }
}

struct MultiSelectionView: View {
    @Environment(SkillStore.self) private var store
    let skills: [Skill]

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 52, weight: .ultraLight))
                .foregroundStyle(.secondary)
                .frame(height: 70)
            Text("\(skills.count) Skills Selected").font(.title2.weight(.semibold))
            HStack {
                Menu { SkillActionsMenu(skills: skills) } label: { Label("Actions", systemImage: "ellipsis.circle") }
                    .fixedSize()
                Button { store.copyToClipboard(skills) } label: { Label("Copy", systemImage: "doc.on.doc") }
                Button(role: .destructive) { store.trash(skills) } label: { Label("Move to Trash", systemImage: "trash") }
            }
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

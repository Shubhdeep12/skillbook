import AppKit
import SwiftUI

struct SidebarView: View {
    @Environment(SkillStore.self) private var store
    @Binding var selection: SidebarItem?
    @State private var expanded: Set<SkillScope> = [.user, .project, .folder]

    var body: some View {
        let skills = store.skills
        let groups = store.groups(of: skills)

        List(selection: $selection) {
            Section("Library") {
                row(.all, "All Skills", "doc.text", count: skills.count)
                ForEach(SkillScope.allCases) { scope in
                    let n = skills.filter { $0.scope == scope }.count
                    if n > 0 { row(.scope(scope), scope.title, scope.symbol, count: n) }
                }
                let issues = skills.filter { $0.validity.hasIssues }.count
                if issues > 0 {
                    row(.attention, "Needs Attention", "exclamationmark.triangle", count: issues)
                }
            }

            ForEach(SkillScope.allCases) { scope in
                let scoped = groups.filter { $0.scope == scope }
                if !scoped.isEmpty {
                    Section(scope.title, isExpanded: binding(for: scope)) {
                        ForEach(scoped) { group in
                            GroupRow(group: group)
                                .tag(SidebarItem.group(group.id))
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                UpdateBanner().padding(.horizontal, 10).padding(.top, 8)
                scanStatus
            }
            .background(.bar)
        }
    }

    private func row(_ item: SidebarItem, _ title: String, _ symbol: String, count: Int) -> some View {
        Label(title, systemImage: symbol)
            .badge(count)
            .tag(item)
    }

    private func binding(for scope: SkillScope) -> Binding<Bool> {
        Binding(
            get: { expanded.contains(scope) },
            set: { if $0 { expanded.insert(scope) } else { expanded.remove(scope) } }
        )
    }

    private var scanStatus: some View {
        HStack(spacing: 6) {
            if store.isScanning {
                ProgressView().controlSize(.small)
                Text("Scanning…")
            } else if let last = store.lastScan {
                Image(systemName: "checkmark.circle")
                Text("Scanned \(last.formatted(date: .omitted, time: .shortened)) · \(String(format: "%.1fs", store.lastDuration))")
            }
            Spacer()
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

private struct GroupRow: View {
    @Environment(SkillStore.self) private var store
    let group: SkillGroup
    @State private var isTargeted = false

    var body: some View {
        Label {
            Text(group.info.title).lineLimit(1)
        } icon: {
            LocationIcon(scope: group.scope)
        }
        .badge(group.count)
        .help(group.info.subtitle)
        .listRowBackground(
            isTargeted ? RoundedRectangle(cornerRadius: 6).fill(Color.accentColor.opacity(0.25)) : nil
        )
        .dropDestination(for: URL.self) { urls, _ in
            guard let target = group.info.target else {
                store.show("\(group.info.title) is managed by its tool, so it doesn't accept skills", symbol: "lock.fill", isError: true)
                return false
            }
            let folders = SkillStore.skillFolders(in: urls)
            guard !folders.isEmpty else { return false }
            let move = NSEvent.modifierFlags.contains(.option)
            store.transfer(folders: folders, to: target, mode: move ? .move : .copy)
            return true
        } isTargeted: { isTargeted = $0 && group.info.target != nil }
        .contextMenu {
            if let target = group.info.target {
                Button { store.createSkill(in: target) } label: { Label("New Skill Here…", systemImage: "plus") }
                Button { store.paste(into: target) } label: { Label("Paste Skill", systemImage: "doc.on.clipboard") }
                    .disabled(store.clipboardSkillFolders.isEmpty)
                Divider()
                Button { NSWorkspace.shared.activateFileViewerSelecting([target]) } label: { Label("Show in Finder", systemImage: "folder") }
            } else if let any = store.allSkills.first(where: { $0.group.key == group.id }) {
                Button { NSWorkspace.shared.activateFileViewerSelecting([any.containerURL]) } label: { Label("Show in Finder", systemImage: "folder") }
            }
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(group.info.target?.path ?? group.info.subtitle, forType: .string)
            } label: { Label("Copy Path", systemImage: "link") }
        }
    }
}

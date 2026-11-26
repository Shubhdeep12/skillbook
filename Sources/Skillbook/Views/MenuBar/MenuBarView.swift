import AppKit
import SwiftUI

/// The panel that drops down from the menu bar icon.
struct MenuBarView: View {
    @Environment(SkillStore.self) private var store
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @State private var query = ""
    @State private var scope: SkillScope?
    @State private var peekID: String?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if let id = peekID, let skill = store.skill(id: id) {
                QuickLookPane(skill: skill, onBack: { withAnimation(.snappy(duration: 0.22)) { peekID = nil } }, openManager: openManager)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                browser
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 410, height: 600)
        .overlay(alignment: .bottom) {
            if let toast = store.toast { ToastView(toast: toast).padding(.bottom, 30) }
        }
        .onAppear { searchFocused = true }
    }

    // MARK: Header & footer

    private var header: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 1) {
                Text("Skillbook").font(.system(size: 13.5, weight: .semibold))
                Text(store.isScanning && store.allSkills.isEmpty
                     ? "Scanning…"
                     : "\(store.skills.count) skills · \(store.groups(of: store.skills).count) locations")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HeaderButton(symbol: "arrow.clockwise", help: "Rescan", spinning: store.isScanning) { store.rescan() }
            HeaderButton(symbol: "macwindow", help: "Open Skillbook") { openManager(nil, .preview) }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let last = store.lastScan {
                Text("Updated \(last.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
            Button { NSApp.terminate(nil) } label: { Image(systemName: "power") }
                .help("Quit Skillbook")
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }

    // MARK: Browser

    private var filtered: [Skill] {
        let q = query.trimmed.lowercased()
        return store.skills.filter { s in
            (scope == nil || s.scope == scope)
                && (q.isEmpty || s.name.lowercased().contains(q) || s.summary.lowercased().contains(q) || s.group.title.lowercased().contains(q))
        }
    }

    private var browser: some View {
        VStack(spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search skills", text: $query)
                    .textFieldStyle(.plain)
                    .focused($searchFocused)
                    .onSubmit {
                        if let first = filtered.first { withAnimation(.snappy(duration: 0.22)) { peekID = first.id } }
                    }
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.tertiary)
                }
            }
            .font(.system(size: 13))
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.06)))
            .padding(.horizontal, 12)
            .padding(.top, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ScopeChip(title: "All", count: store.skills.count, isOn: scope == nil) { scope = nil }
                    ForEach(SkillScope.allCases) { s in
                        let n = store.skills.filter { $0.scope == s }.count
                        if n > 0 {
                            ScopeChip(title: s.title, symbol: s.symbol, count: n, isOn: scope == s) { scope = (scope == s ? nil : s) }
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
            }

            Divider().opacity(0.5)

            let skills = filtered
            if skills.isEmpty {
                if store.isScanning {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView.search(text: query)
                        .frame(maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(sections(skills), id: \.key) { section in
                            Section {
                                ForEach(section.skills) { skill in
                                    MenuSkillRow(skill: skill) {
                                        withAnimation(.snappy(duration: 0.22)) { peekID = skill.id }
                                    } openManager: { mode in
                                        openManager(skill, mode)
                                    }
                                }
                            } header: {
                                SectionHeader(title: section.title, subtitle: section.subtitle, tool: section.tool, scope: section.scope)
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
            }
        }
    }

    private struct PanelSection {
        let key: String
        let title: String
        let subtitle: String
        let tool: AgentTool
        let scope: SkillScope
        var skills: [Skill]
    }

    private func sections(_ skills: [Skill]) -> [PanelSection] {
        var dict: [String: PanelSection] = [:]
        for s in skills {
            dict[s.group.key, default: PanelSection(key: s.group.key, title: s.group.title, subtitle: s.group.subtitle,
                                                    tool: s.tool, scope: s.scope, skills: [])].skills.append(s)
        }
        let order = SkillScope.allCases
        return dict.values.sorted {
            let a = order.firstIndex(of: $0.scope) ?? 0, b = order.firstIndex(of: $1.scope) ?? 0
            return a != b ? a < b : $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
    }

    private func openManager(_ skill: Skill?, _ mode: DetailMode) {
        if let skill { store.focus(skill.id, mode: mode) }
        openWindow(id: "manager")
        NSApp.activate(ignoringOtherApps: true)
    }
}

// MARK: - Pieces

private struct HeaderButton: View {
    let symbol: String
    let help: String
    var spinning = false
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12.5, weight: .medium))
                .rotationEffect(.degrees(spinning ? 360 : 0))
                .animation(spinning ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default, value: spinning)
                .frame(width: 26, height: 26)
                .background(Circle().fill(Color.primary.opacity(hovering ? 0.09 : 0)))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .onHover { hovering = $0 }
        .help(help)
    }
}

private struct ScopeChip: View {
    let title: String
    var symbol: String? = nil
    let count: Int
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).imageScale(.small) }
                Text(title)
                Text("\(count)").foregroundStyle(isOn ? .white.opacity(0.8) : .secondary).monospacedDigit()
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? .white : .primary)
            .background(Capsule().fill(isOn ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color.primary.opacity(0.07))))
        }
        .buttonStyle(.plain)
    }
}

private struct SectionHeader: View {
    let title: String
    let subtitle: String
    let tool: AgentTool
    let scope: SkillScope

    var body: some View {
        HStack(spacing: 6) {
            LocationIcon(scope: scope, size: 13)
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
            Spacer()
            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.head)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }
}

private struct MenuSkillRow: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill
    let peek: () -> Void
    let openManager: (DetailMode) -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: peek) {
            HStack(spacing: 10) {
                SkillGlyph(isSkill: skill.validity.isSkill, size: 14, weight: .light)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(skill.name).font(.system(size: 12.5, weight: .medium)).lineLimit(1)
                        if skill.validity.hasIssues {
                            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 9)).foregroundStyle(.orange)
                        }
                    }
                    if !skill.summary.isEmpty {
                        Text(skill.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                ToolTag(tool: skill.tool, showsName: false)
                if hovering {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(hovering ? Color.accentColor.opacity(0.13) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { hovering = $0 }
        .onDrag { NSItemProvider(object: skill.folderURL.resolvingSymlinksInPath() as NSURL) }
        .contextMenu {
            Button("Open in Skillbook") { openManager(.preview) }
            Button("Edit") { openManager(.edit) }
            Divider()
            SkillActionsMenu(skills: [skill])
        }
    }
}

/// Inline preview inside the menu bar panel.
private struct QuickLookPane: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill
    let onBack: () -> Void
    let openManager: (Skill?, DetailMode) -> Void
    @State private var text = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 12, weight: .semibold))
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.cancelAction)
                SkillGlyph(isSkill: skill.validity.isSkill, size: 16, weight: .light)
                VStack(alignment: .leading, spacing: 0) {
                    Text(skill.name).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    Text("\(skill.tool.title) · \(skill.scope.singular) · \(skill.group.title)").font(.system(size: 10.5)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)

            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !skill.summary.isEmpty {
                        Text(skill.summary)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if skill.validity.hasIssues { IssuesCard(validity: skill.validity) }
                    Divider()
                    let fm = Frontmatter.parse(text)
                    MarkdownView(fm.hasFrontmatter ? fm.body : text, compact: true)
                }
                .padding(14)
            }

            Divider().opacity(0.5)

            HStack(spacing: 6) {
                Button { openManager(skill, .edit) } label: { Label("Edit", systemImage: "pencil") }
                    .buttonStyle(.borderedProminent)
                Button { openManager(skill, .preview) } label: { Label("Open", systemImage: "macwindow") }
                Spacer()
                Button { store.copyToClipboard([skill]) } label: { Image(systemName: "doc.on.doc") }.help("Copy skill")
                Button { store.copyPaths([skill]) } label: { Image(systemName: "link") }.help("Copy path")
                Button { store.reveal([skill]) } label: { Image(systemName: "folder") }.help("Show in Finder")
                Menu {
                    SkillActionsMenu(skills: [skill])
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
            }
            .controlSize(.regular)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .task(id: skill.id) {
            text = (try? String(contentsOf: skill.fileURL, encoding: .utf8)) ?? ""
        }
    }
}

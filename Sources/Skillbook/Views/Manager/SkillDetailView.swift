import AppKit
import SwiftUI

struct SkillDetailView: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill
    @Binding var mode: DetailMode

    @State private var text = ""
    @State private var original = ""
    @State private var loadedID: String?

    private var isDirty: Bool { text != original }

    var body: some View {
        VStack(spacing: 0) {
            if let reason = skill.managedReason {
                ManagedBanner(reason: reason)
            }
            switch mode {
            case .preview:
                SkillPreview(skill: skill, text: text)
            case .edit:
                CodeEditor(text: $text, fontSize: store.settings.editorFontSize)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(alignment: .bottomTrailing) { editorStatus }
            case .files:
                SkillFilesView(folder: skill.folderURL)
            }
        }
        .navigationTitle(skill.name + (isDirty ? " — Edited" : ""))
        .toolbar { toolbar }
        .background { shortcuts }
        .onChange(of: skill.id, initial: true) { oldID, newID in
            if oldID != newID, loadedID == oldID, isDirty {
                if let save = Alerts.unsavedChanges(name: URL(fileURLWithPath: oldID).deletingLastPathComponent().lastPathComponent), save,
                   let old = store.skill(id: oldID) {
                    store.save(text, to: old)
                }
            }
            load()
        }
        .onChange(of: skill.modified) { _, _ in
            if !isDirty { load() }
        }
        .onChange(of: isDirty, initial: true) { _, dirty in store.hasUnsavedEdits = dirty }
        .onDisappear { store.hasUnsavedEdits = false }
    }

    private func load() {
        let loaded = (try? String(contentsOf: skill.fileURL, encoding: .utf8)) ?? ""
        text = loaded
        original = loaded
        loadedID = skill.id
    }

    private func save() {
        if store.save(text, to: skill) { original = text }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Mode", selection: $mode) {
                ForEach(DetailMode.allCases, id: \.self) { m in
                    Label(m.title, systemImage: m.symbol).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .help("Preview ⌘1 · Edit ⌘2 · Files ⌘3")

            if mode == .edit {
                Button { text = original } label: { Label("Revert", systemImage: "arrow.uturn.backward") }
                    .disabled(!isDirty)
                    .help("Discard unsaved changes")
            }
            Button(action: save) { Label("Save", systemImage: "square.and.arrow.down") }
                .keyboardShortcut("s")
                .disabled(!isDirty)
                .help("Save (⌘S)")

            Button { store.reveal([skill]) } label: { Label("Show in Finder", systemImage: "folder") }
                .help("Show in Finder")

            Menu {
                SkillActionsMenu(skills: [skill], onEdit: { _ in mode = .edit })
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("Copy, move, rename and more")
        }
    }

    private var shortcuts: some View {
        ZStack {
            Button("") { mode = .preview }.keyboardShortcut("1")
            Button("") { mode = .edit }.keyboardShortcut("2")
            Button("") { mode = .files }.keyboardShortcut("3")
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private var editorStatus: some View {
        let fm = Frontmatter.parse(text)
        let validity = SkillValidator.validate(fm, folderName: skill.folderName)
        return HStack(spacing: 6) {
            Image(systemName: validity == .valid ? "checkmark.seal.fill" : validity.isSkill ? "exclamationmark.triangle.fill" : "xmark.octagon.fill")
                .foregroundStyle(validity == .valid ? .green : validity.isSkill ? .orange : .red)
            Text(validity == .valid ? "Valid skill" : validity.issues.first ?? "")
                .lineLimit(1)
            if isDirty {
                Text("·  Unsaved").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .padding(14)
        .help(validity.issues.joined(separator: "\n"))
    }
}

private struct ManagedBanner: View {
    let reason: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield")
                .foregroundStyle(.secondary)
            Text(reason)
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.yellow.opacity(0.08))
        .overlay(alignment: .bottom) { Divider() }
    }
}

struct SkillPreview: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill
    let text: String

    var body: some View {
        let fm = Frontmatter.parse(text)
        let validity = SkillValidator.validate(fm, folderName: skill.folderName)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SkillHeader(skill: skill, name: fm["name"]?.nonEmpty ?? skill.name, summary: fm["description"] ?? skill.summary)
                if validity.hasIssues { IssuesCard(validity: validity) }
                let extra = fm.fields.filter { $0.key != "name" && $0.key != "description" }
                if !extra.isEmpty { FrontmatterCard(fields: extra) }
                MarkdownView(fm.hasFrontmatter ? fm.body : text)
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 28)
            .frame(maxWidth: 880, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

struct SkillHeader: View {
    @Environment(SkillStore.self) private var store
    let skill: Skill
    let name: String
    let summary: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 16) {
                SkillGlyph(isSkill: skill.validity.isSkill, size: 34, weight: .ultraLight)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 6) {
                    Text(name)
                        .font(.system(size: 26, weight: .bold))
                        .textSelection(.enabled)
                    if !summary.isEmpty {
                        Text(summary)
                            .font(.system(size: 13.5))
                            .foregroundStyle(.secondary)
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            FlowChips(skill: skill)
            Button {
                store.reveal([skill])
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "folder.fill")
                    Text(skill.displayPath).truncationMode(.middle)
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
        }
    }
}

private struct FlowChips: View {
    let skill: Skill

    var body: some View {
        HStack(spacing: 6) {
            Chip(text: skill.tool.title, dot: skill.tool.color)
            Chip(text: "\(skill.scope.singular) · \(skill.group.title)", symbol: skill.scope.symbol)
            if let v = skill.pluginVersion { Chip(text: "v\(v)", symbol: "tag") }
            if skill.isSymlink { Chip(text: "Symlink", symbol: "arrow.turn.up.right") }
            if skill.isStale { Chip(text: "Older copy", symbol: "clock.arrow.circlepath", tint: .orange) }
            if skill.isCatalog { Chip(text: "Catalog", symbol: "book.closed", tint: .orange) }
            Chip(text: "Edited \(skill.modified.relativeDescription)", symbol: "clock")
        }
    }
}

struct FrontmatterCard: View {
    let fields: [FrontmatterField]

    var body: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 8) {
            ForEach(fields) { f in
                GridRow {
                    Text(f.key)
                        .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.purple)
                    Text(f.value)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.035)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
    }
}

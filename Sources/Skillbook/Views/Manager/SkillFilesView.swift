import AppKit
import SwiftUI

private struct FileEntry: Identifiable, Hashable {
    let url: URL
    let relative: String
    let depth: Int
    let isDirectory: Bool
    let size: Int
    var id: String { url.path }
}

/// Lists everything in the skill folder (scripts, references, assets) with a preview pane.
struct SkillFilesView: View {
    let folder: URL
    @State private var entries: [FileEntry] = []
    @State private var selected: String?

    var body: some View {
        HSplitView {
            List(selection: $selected) {
                ForEach(entries) { entry in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                            .resizable()
                            .frame(width: 16, height: 16)
                        Text(entry.url.lastPathComponent)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                        Spacer()
                        if !entry.isDirectory {
                            Text(ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file))
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.leading, CGFloat(entry.depth) * 14)
                    .tag(entry.id)
                }
            }
            .contextMenu(forSelectionType: String.self) { ids in
                if let id = ids.first {
                    let url = URL(fileURLWithPath: id)
                    Button("Open") { NSWorkspace.shared.open(url) }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                    Button("Copy Path") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.path, forType: .string)
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first { NSWorkspace.shared.open(URL(fileURLWithPath: id)) }
            }
            .frame(minWidth: 200, idealWidth: 250, maxWidth: 380)

            FilePreview(entry: entries.first { $0.id == selected })
                .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: folder) { load() }
    }

    private func load() {
        let root = folder.resolvingSymlinksInPath()
        var result: [FileEntry] = []
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsPackageDescendants]) {
            while let url = e.nextObject() as? URL, result.count < 600 {
                let name = url.lastPathComponent
                if name == ".git" || name == "node_modules" || name == ".DS_Store" {
                    e.skipDescendants()
                    continue
                }
                let v = try? url.resourceValues(forKeys: Set(keys))
                let rel = String(url.path.dropFirst(root.path.count + 1))
                result.append(FileEntry(url: url, relative: rel, depth: e.level - 1,
                                        isDirectory: v?.isDirectory ?? false, size: v?.fileSize ?? 0))
            }
        }
        // Keep the enumerator's parent-before-children order, but sort siblings by name.
        entries = result.sorted { $0.relative.localizedStandardCompare($1.relative) == .orderedAscending }
        if selected == nil || !entries.contains(where: { $0.id == selected }) {
            selected = entries.first { $0.url.lastPathComponent == "SKILL.md" }?.id
        }
    }
}

private struct FilePreview: View {
    let entry: FileEntry?

    var body: some View {
        Group {
            if let entry {
                if entry.isDirectory {
                    placeholder(entry, note: "Folder")
                } else if let text = readText(entry) {
                    ScrollView {
                        if entry.url.pathExtension.lowercased() == "md" {
                            let fm = Frontmatter.parse(text)
                            VStack(alignment: .leading, spacing: 16) {
                                if fm.hasFrontmatter && !fm.fields.isEmpty { FrontmatterCard(fields: fm.fields) }
                                MarkdownView(fm.hasFrontmatter ? fm.body : text)
                            }
                            .padding(24)
                        } else {
                            Text(text)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(20)
                        }
                    }
                } else {
                    placeholder(entry, note: "No text preview")
                }
            } else {
                ContentUnavailableView("No File Selected", systemImage: "doc")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private func placeholder(_ entry: FileEntry, note: String) -> some View {
        VStack(spacing: 12) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable().frame(width: 64, height: 64)
            Text(entry.url.lastPathComponent).font(.headline)
            Text(note).foregroundStyle(.secondary)
            Button("Open") { NSWorkspace.shared.open(entry.url) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func readText(_ entry: FileEntry) -> String? {
        guard entry.size < 768 * 1024, let data = try? Data(contentsOf: entry.url) else { return nil }
        if data.prefix(4096).contains(0) { return nil }
        return String(data: data, encoding: .utf8)
    }
}

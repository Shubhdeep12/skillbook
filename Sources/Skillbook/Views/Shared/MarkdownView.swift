import AppKit
import SwiftUI

// MARK: - Parsing

enum MDBlock: Hashable {
    case heading(Int, String)
    case paragraph(String)
    case code(language: String, text: String)
    case quote(String)
    case list([MDListItem])
    case table([[String]])
    case rule
}

struct MDListItem: Hashable {
    let level: Int
    let marker: String
    let text: String
    let checked: Bool?
}

enum MarkdownParser {
    static func parse(_ source: String) -> [MDBlock] {
        let lines = source.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        var blocks: [MDBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let t = line.trimmed
            if t.isEmpty { i += 1; continue }

            // Fenced code
            if t.hasPrefix("```") || t.hasPrefix("~~~") {
                let fence = String(t.prefix(3))
                let lang = String(t.dropFirst(3)).trimmed
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmed.hasPrefix(fence) {
                    body.append(lines[i])
                    i += 1
                }
                i += 1
                blocks.append(.code(language: lang, text: body.joined(separator: "\n")))
                continue
            }
            if let h = heading(t) {
                blocks.append(.heading(h.0, h.1))
                i += 1
                continue
            }
            if isRule(t) {
                blocks.append(.rule)
                i += 1
                continue
            }
            if t.hasPrefix(">") {
                var body: [String] = []
                while i < lines.count, lines[i].trimmed.hasPrefix(">") {
                    body.append(String(lines[i].trimmed.dropFirst()).trimmed)
                    i += 1
                }
                blocks.append(.quote(body.joined(separator: "\n")))
                continue
            }
            if t.hasPrefix("|") {
                var rows: [[String]] = []
                while i < lines.count, lines[i].trimmed.hasPrefix("|") {
                    let cells = splitRow(lines[i].trimmed)
                    if !cells.allSatisfy(isSeparatorCell) { rows.append(cells) }
                    i += 1
                }
                blocks.append(.table(rows))
                continue
            }
            if listItem(line) != nil {
                var items: [MDListItem] = []
                while i < lines.count {
                    let l = lines[i]
                    if let item = listItem(l) {
                        items.append(item)
                        i += 1
                    } else if l.trimmed.isEmpty {
                        // A blank line continues the list only if another item follows.
                        if i + 1 < lines.count, listItem(lines[i + 1]) != nil { i += 1 } else { break }
                    } else if l.first?.isWhitespace == true, let last = items.popLast() {
                        items.append(MDListItem(level: last.level, marker: last.marker, text: last.text + " " + l.trimmed, checked: last.checked))
                        i += 1
                    } else { break }
                }
                blocks.append(.list(items))
                continue
            }

            // Paragraph
            var para: [String] = []
            while i < lines.count {
                let l = lines[i]
                let lt = l.trimmed
                if lt.isEmpty || lt.hasPrefix("```") || lt.hasPrefix("~~~") || heading(lt) != nil || lt.hasPrefix(">")
                    || lt.hasPrefix("|") || (listItem(l) != nil && !para.isEmpty) || isRule(lt) { break }
                para.append(lt)
                i += 1
            }
            blocks.append(.paragraph(para.joined(separator: "\n")))
        }
        return blocks
    }

    private static func heading(_ t: String) -> (Int, String)? {
        let hashes = t.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(hashes), t.count > hashes, t[t.index(t.startIndex, offsetBy: hashes)] == " " else { return nil }
        var text = String(t.dropFirst(hashes)).trimmed
        while text.hasSuffix("#") { text.removeLast() }
        return (hashes, text.trimmed)
    }

    private static func isRule(_ t: String) -> Bool {
        let compact = t.replacingOccurrences(of: " ", with: "")
        guard compact.count >= 3, let c = compact.first, "-*_".contains(c) else { return false }
        return compact.allSatisfy { $0 == c }
    }

    private static func listItem(_ line: String) -> MDListItem? {
        let indent = line.prefix(while: { $0 == " " || $0 == "\t" }).reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        let t = line.trimmed
        var marker: String?
        var rest = ""
        if let f = t.first, "-*+".contains(f), t.dropFirst().first == " " {
            marker = "•"
            rest = String(t.dropFirst(2))
        } else {
            let digits = t.prefix(while: \.isNumber)
            if !digits.isEmpty, digits.count < 4 {
                let after = t.dropFirst(digits.count)
                if let p = after.first, p == "." || p == ")", after.dropFirst().first == " " {
                    marker = "\(digits)."
                    rest = String(after.dropFirst(2))
                }
            }
        }
        guard let marker else { return nil }
        var checked: Bool?
        if rest.hasPrefix("[ ] ") { checked = false; rest = String(rest.dropFirst(4)) }
        else if rest.lowercased().hasPrefix("[x] ") { checked = true; rest = String(rest.dropFirst(4)) }
        return MDListItem(level: min(indent / 2, 6), marker: marker, text: rest, checked: checked)
    }

    private static func splitRow(_ row: String) -> [String] {
        var s = row
        if s.hasPrefix("|") { s.removeFirst() }
        if s.hasSuffix("|") { s.removeLast() }
        var cells: [String] = []
        var current = ""
        var escaped = false
        var inCode = false
        for ch in s {
            if escaped { current.append(ch); escaped = false; continue }
            if ch == "\\" { escaped = true; continue }
            if ch == "`" { inCode.toggle() }
            if ch == "|" && !inCode {
                cells.append(current.trimmed)
                current = ""
            } else {
                current.append(ch)
            }
        }
        cells.append(current.trimmed)
        return cells
    }

    private static func isSeparatorCell(_ c: String) -> Bool {
        !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" || $0 == " " }
    }

    static func inline(_ s: String) -> AttributedString {
        var attr = (try? AttributedString(
            markdown: s,
            options: .init(allowsExtendedAttributes: true, interpretedSyntax: .inlineOnlyPreservingWhitespace, failurePolicy: .returnPartiallyParsedIfPossible)
        )) ?? AttributedString(s)
        for run in attr.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                attr[run.range].font = .system(size: 12, design: .monospaced)
                attr[run.range].backgroundColor = Color.primary.opacity(0.07)
                attr[run.range].foregroundColor = Color(nsColor: .systemPink).opacity(0.9)
            }
        }
        return attr
    }
}

// MARK: - Rendering

struct MarkdownView: View {
    let blocks: [MDBlock]
    var compact = false

    init(_ source: String, compact: Bool = false) {
        self.blocks = MarkdownParser.parse(source)
        self.compact = compact
    }

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var bodySize: CGFloat { compact ? 12.5 : 14 }

    @ViewBuilder
    private func view(for block: MDBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            VStack(alignment: .leading, spacing: 6) {
                Text(MarkdownParser.inline(text))
                    .font(headingFont(level))
                    .padding(.top, level <= 2 ? (compact ? 4 : 10) : 4)
                if level <= 2 && !compact { Divider().opacity(0.6) }
            }
        case .paragraph(let text):
            Text(MarkdownParser.inline(text))
                .font(.system(size: bodySize))
                .lineSpacing(compact ? 2 : 4)
                .fixedSize(horizontal: false, vertical: true)
        case .code(let lang, let text):
            CodeBlockView(language: lang, code: text, compact: compact)
        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 1.5).fill(Color.accentColor.opacity(0.6)).frame(width: 3)
                Text(MarkdownParser.inline(text))
                    .font(.system(size: bodySize))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        case .list(let items):
            VStack(alignment: .leading, spacing: compact ? 3 : 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if let checked = item.checked {
                            Image(systemName: checked ? "checkmark.square.fill" : "square")
                                .foregroundStyle(checked ? Color.accentColor : .secondary)
                        } else {
                            Text(item.marker)
                                .font(.system(size: bodySize, weight: item.marker == "•" ? .bold : .medium).monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(minWidth: 14, alignment: .trailing)
                        }
                        Text(MarkdownParser.inline(item.text))
                            .font(.system(size: bodySize))
                            .lineSpacing(compact ? 1 : 3)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.leading, CGFloat(item.level) * 18)
                }
            }
        case .table(let rows):
            TableBlockView(rows: rows, compact: compact)
        case .rule:
            Divider().padding(.vertical, 4)
        }
    }

    private func headingFont(_ level: Int) -> Font {
        if compact {
            return .system(size: level == 1 ? 16 : level == 2 ? 14.5 : 13, weight: .semibold)
        }
        switch level {
        case 1: return .system(size: 26, weight: .bold)
        case 2: return .system(size: 20, weight: .semibold)
        case 3: return .system(size: 16.5, weight: .semibold)
        default: return .system(size: 14, weight: .semibold)
        }
    }
}

struct CodeBlockView: View {
    let language: String
    let code: String
    var compact = false
    @State private var hovering = false
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !language.isEmpty || hovering {
                HStack {
                    Text(language.isEmpty ? " " : language.uppercased())
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.6)
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(code, forType: .string)
                        copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { copied = false }
                    } label: {
                        Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 10.5))
                    }
                    .buttonStyle(.borderless)
                    .opacity(hovering || copied ? 1 : 0)
                }
                .padding(.horizontal, 12)
                .padding(.top, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: compact ? 11 : 12, design: .monospaced))
                    .lineSpacing(2)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.primary.opacity(0.07)))
        .onHover { hovering = $0 }
    }
}

struct TableBlockView: View {
    let rows: [[String]]
    var compact = false

    var body: some View {
        let columns = rows.map(\.count).max() ?? 0
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(0..<columns, id: \.self) { col in
                            Text(MarkdownParser.inline(col < row.count ? row[col] : ""))
                                .font(.system(size: compact ? 11.5 : 12.5, weight: index == 0 ? .semibold : .regular))
                                .frame(maxWidth: 360, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                        }
                    }
                    .background(index == 0 ? Color.primary.opacity(0.06) : index.isMultiple(of: 2) ? Color.primary.opacity(0.025) : .clear)
                    if index < rows.count - 1 {
                        Divider().gridCellUnsizedAxes(.horizontal)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
        }
    }
}

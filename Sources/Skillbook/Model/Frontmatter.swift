import Foundation

/// A small YAML-frontmatter reader that covers what SKILL.md files use:
/// `key: value`, quoted strings, `|` / `>` block scalars, and indented lists or maps.
struct Frontmatter: Sendable {
    var fields: [FrontmatterField] = []
    var body: String
    var hasFrontmatter: Bool

    subscript(key: String) -> String? {
        fields.first { $0.key == key }?.value
    }

    static func parse(_ raw: String) -> Frontmatter {
        var text = raw.replacingOccurrences(of: "\r\n", with: "\n")
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        let lines = text.components(separatedBy: "\n")

        guard let first = lines.first, first.trimmed == "---" else {
            return Frontmatter(body: text, hasFrontmatter: false)
        }
        guard let close = lines.indices.dropFirst().first(where: { lines[$0].trimmed == "---" || lines[$0].trimmed == "..." }) else {
            return Frontmatter(body: text, hasFrontmatter: false)
        }

        let yaml = Array(lines[1..<close])
        let body = lines[(close + 1)...].joined(separator: "\n")
        return Frontmatter(fields: parseFields(yaml), body: body, hasFrontmatter: true)
    }

    private static func parseFields(_ lines: [String]) -> [FrontmatterField] {
        var fields: [FrontmatterField] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            i += 1
            guard let first = line.first, !first.isWhitespace, first != "#", first != "-",
                  let colon = line.firstIndex(of: ":") else { continue }

            let key = String(line[..<colon]).trimmed
            let rest = String(line[line.index(after: colon)...]).trimmed

            // Collect indented continuation lines.
            var continuation: [String] = []
            while i < lines.count {
                let next = lines[i]
                if next.trimmed.isEmpty || next.first?.isWhitespace == true || next.hasPrefix("- ") {
                    continuation.append(next)
                    i += 1
                } else { break }
            }
            while continuation.last?.trimmed.isEmpty == true { continuation.removeLast() }

            let value: String
            if rest.hasPrefix("|") || rest.hasPrefix(">") {
                let joiner = rest.hasPrefix("|") ? "\n" : " "
                value = dedent(continuation).joined(separator: joiner).trimmed
            } else if rest.isEmpty {
                // List or nested map.
                let items = continuation.map(\.trimmed).filter { !$0.isEmpty }
                value = items.map { $0.hasPrefix("- ") ? unquote(String($0.dropFirst(2))) : $0 }.joined(separator: ", ")
            } else {
                let tail = continuation.map(\.trimmed).filter { !$0.isEmpty }
                value = unquote(([rest] + tail).joined(separator: " "))
            }
            fields.append(FrontmatterField(key: key, value: value))
        }
        return fields
    }

    private static func dedent(_ lines: [String]) -> [String] {
        let indent = lines.filter { !$0.trimmed.isEmpty }
            .map { $0.prefix(while: { $0 == " " || $0 == "\t" }).count }
            .min() ?? 0
        return lines.map { $0.count >= indent ? String($0.dropFirst(indent)) : $0.trimmed }
    }

    private static func unquote(_ s: String) -> String {
        let t = s.trimmed
        guard t.count >= 2, let f = t.first, let l = t.last, f == l, f == "\"" || f == "'" else {
            if t.hasPrefix("[") && t.hasSuffix("]") {
                return t.dropFirst().dropLast().split(separator: ",").map { unquote(String($0)) }.joined(separator: ", ")
            }
            return t
        }
        let inner = String(t.dropFirst().dropLast())
        return f == "\"" ? inner.replacingOccurrences(of: "\\\"", with: "\"") : inner.replacingOccurrences(of: "''", with: "'")
    }

    /// Return `text` with `key:` set to `value` in its frontmatter (added if missing).
    static func setting(_ key: String, to value: String, in text: String) -> String {
        var lines = text.components(separatedBy: "\n")
        guard lines.first?.trimmed == "---" else { return text }
        for i in 1..<lines.count {
            if lines[i].trimmed == "---" {
                lines.insert("\(key): \(value)", at: i)
                return lines.joined(separator: "\n")
            }
            if lines[i].hasPrefix("\(key):") {
                lines[i] = "\(key): \(value)"
                return lines.joined(separator: "\n")
            }
        }
        return text
    }
}

enum SkillValidator {
    static func validate(_ fm: Frontmatter, folderName: String) -> Validity {
        guard fm.hasFrontmatter else {
            return .invalid("No YAML frontmatter (--- … ---) at the top of the file")
        }
        let name = fm["name"]?.trimmed ?? ""
        let description = fm["description"]?.trimmed ?? ""
        if name.isEmpty && description.isEmpty {
            return .invalid("Frontmatter has neither a name nor a description")
        }
        if description.isEmpty {
            return .invalid("Missing description — agents use it to decide when to load the skill")
        }

        var warnings: [String] = []
        if name.isEmpty {
            warnings.append("No name field — agents fall back to the folder name")
        } else {
            if !name.isKebabCase {
                warnings.append("Name should use lowercase letters, digits and hyphens")
            }
            if name.count > 64 {
                warnings.append("Name is \(name.count) characters (limit 64)")
            }
            if name != folderName && name.isKebabCase {
                warnings.append("Name “\(name)” differs from its folder “\(folderName)”")
            }
        }
        if description.count > 1024 {
            warnings.append("Description is \(description.count) characters (limit 1024)")
        }
        if fm.body.trimmed.isEmpty {
            warnings.append("No instructions after the frontmatter")
        }
        return warnings.isEmpty ? .valid : .warnings(warnings)
    }
}

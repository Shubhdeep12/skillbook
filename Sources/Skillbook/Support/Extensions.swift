import Foundation

extension String {
    var tildePath: String { (self as NSString).abbreviatingWithTildeInPath }
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
    var nonEmpty: String? {
        let t = trimmed
        return t.isEmpty ? nil : t
    }

    var isKebabCase: Bool {
        range(of: "^[a-z0-9]+(-[a-z0-9]+)*$", options: .regularExpression) != nil
    }

    /// "My Cool Skill!" → "my-cool-skill"
    var kebabCased: String {
        let lowered = lowercased()
        var out = ""
        var lastWasDash = false
        for ch in lowered {
            if ch.isLetter || ch.isNumber {
                out.append(ch)
                lastWasDash = false
            } else if !lastWasDash && !out.isEmpty {
                out.append("-")
                lastWasDash = true
            }
        }
        while out.hasSuffix("-") { out.removeLast() }
        return out
    }
}

extension URL {
    var isDirectory: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    var homeURL: URL { FileManager.default.homeDirectoryForCurrentUser }
}

enum Paths {
    static let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }
}

extension Date {
    var relativeDescription: String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f.localizedString(for: self, relativeTo: Date())
    }
}

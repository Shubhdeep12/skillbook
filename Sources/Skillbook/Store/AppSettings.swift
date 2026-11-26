import Foundation
import Observation

@MainActor
@Observable
final class AppSettings {
    @ObservationIgnored private let defaults = UserDefaults.standard

    static let defaultExcluded: [String] = [
        "Library", "node_modules", ".Trash", ".trash", "Pictures", "Movies", "Music", "Applications",
        ".npm", ".pnpm-store", ".yarn", ".cache", ".bun", ".nvm", ".pyenv", ".rbenv", ".rustup", ".cargo",
        ".gradle", ".m2", ".android", ".docker", ".orbstack", ".venv", "venv", "__pycache__", "Pods",
        "DerivedData", ".build", ".next", ".turbo", ".Spotlight-V100", "target", "dist",
    ]

    var scanRoots: [String] { didSet { defaults.set(scanRoots, forKey: "scanRoots") } }
    var excludedNames: [String] { didSet { defaults.set(excludedNames, forKey: "excludedNames") } }
    var maxDepth: Int { didSet { defaults.set(maxDepth, forKey: "maxDepth") } }
    /// Show old plugin versions and marketplace catalog copies.
    var showPluginExtras: Bool { didSet { defaults.set(showPluginExtras, forKey: "showPluginExtras") } }
    /// Show SKILL.md files that fail the skill check.
    var showUnverified: Bool { didSet { defaults.set(showUnverified, forKey: "showUnverified") } }
    var watchForChanges: Bool { didSet { defaults.set(watchForChanges, forKey: "watchForChanges") } }
    var editorFontSize: Double { didSet { defaults.set(editorFontSize, forKey: "editorFontSize") } }

    init() {
        scanRoots = defaults.stringArray(forKey: "scanRoots") ?? ["~"]
        excludedNames = defaults.stringArray(forKey: "excludedNames") ?? Self.defaultExcluded
        maxDepth = defaults.object(forKey: "maxDepth") as? Int ?? 12
        showPluginExtras = defaults.bool(forKey: "showPluginExtras")
        showUnverified = defaults.bool(forKey: "showUnverified")
        watchForChanges = defaults.object(forKey: "watchForChanges") as? Bool ?? true
        editorFontSize = defaults.object(forKey: "editorFontSize") as? Double ?? 13
    }

    var rootURLs: [URL] { scanRoots.map(Paths.expand) }

    func scanOptions() -> ScanOptions {
        ScanOptions(
            roots: rootURLs,
            excludedNames: Set(excludedNames),
            excludedPaths: [Paths.home.appendingPathComponent("go/pkg/mod").path],
            maxDepth: maxDepth
        )
    }
}

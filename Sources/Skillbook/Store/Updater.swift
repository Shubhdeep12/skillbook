import AppKit
import CryptoKit
import Foundation
import Observation

/// A newer Skillbook published on GitHub.
struct AppRelease: Equatable {
    let version: String
    let pageURL: URL
    let zipURL: URL
    let checksumsURL: URL
}

struct UpdateError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

/// Checks GitHub for a newer release, then downloads it, verifies it, swaps it in
/// place of the running app and relaunches.
@MainActor
@Observable
final class Updater {
    enum Phase: Equatable {
        case idle
        case checking
        case upToDate
        case available(AppRelease)
        case installing(AppRelease)
        case failed(String)
    }

    nonisolated static let repo = "Shubhdeep12/skillbook"
    static let installCommand = "curl -fsSL https://skillbook.okshubh.in/install.sh | bash"
    private static let checkEvery: TimeInterval = 6 * 60 * 60

    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private let hasUnsavedEdits: @MainActor () -> Bool

    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private(set) var phase: Phase = .idle
    private(set) var lastCheck: Date? { didSet { defaults.set(lastCheck, forKey: "updates.lastCheck") } }
    var checkAutomatically: Bool { didSet { defaults.set(checkAutomatically, forKey: "updates.check") } }
    /// Install found updates on their own, but only while no Skillbook window is open.
    var installAutomatically: Bool { didSet { defaults.set(installAutomatically, forKey: "updates.install") } }

    init(hasUnsavedEdits: @escaping @MainActor () -> Bool) {
        self.hasUnsavedEdits = hasUnsavedEdits
        lastCheck = defaults.object(forKey: "updates.lastCheck") as? Date
        checkAutomatically = defaults.object(forKey: "updates.check") as? Bool ?? true
        installAutomatically = defaults.object(forKey: "updates.install") as? Bool ?? true
        Task {
            try? await Task.sleep(for: .seconds(10))
            while true {
                await tick()
                try? await Task.sleep(for: .seconds(30 * 60))
            }
        }
    }

    var available: AppRelease? {
        if case .available(let release) = phase { return release }
        return nil
    }

    var isBusy: Bool {
        switch phase {
        case .checking, .installing: true
        default: false
        }
    }

    // MARK: Checking

    private func tick() async {
        guard checkAutomatically, !isBusy else { return }
        let due = lastCheck.map { Date().timeIntervalSince($0) > Self.checkEvery } ?? true
        if available == nil, due { await check() }
        if let release = available, installAutomatically, isQuiet {
            await install(release)
        }
    }

    /// Nobody is using Skillbook: it isn't frontmost and no window (manager, settings) is open,
    /// so restarting it can't interrupt anything.
    private var isQuiet: Bool {
        !NSApp.isActive && !hasUnsavedEdits()
            && !NSApp.windows.contains { $0.styleMask.contains(.titled) && ($0.isVisible || $0.isMiniaturized) }
    }

    func check() async {
        guard !isBusy else { return }
        phase = .checking
        do {
            let release = try await Self.fetchLatest()
            lastCheck = Date()
            if let release, Self.isVersion(release.version, newerThan: currentVersion) {
                phase = .available(release)
            } else {
                phase = .upToDate
            }
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    /// "Check for Updates…": checks, then reports the result in an alert.
    func checkInteractively() async {
        await check()
        switch phase {
        case .available(let release):
            if Alerts.confirm("Skillbook \(release.version) is available",
                              "You have \(currentVersion). Skillbook downloads the update and restarts.",
                              ok: "Update") {
                await installInteractively(release)
            }
        case .upToDate:
            Alerts.message("Skillbook is up to date", "Version \(currentVersion) is the latest.")
        case .failed(let message):
            Alerts.message("Couldn't check for updates", message)
        default:
            break
        }
    }

    // MARK: Installing

    /// The Update button: confirms first if an edit is unsaved, and reports failures.
    func installInteractively(_ release: AppRelease) async {
        if hasUnsavedEdits(), !Alerts.confirm("Discard your unsaved edit?",
                                                "Skillbook restarts to update. Save your edit first to keep it.",
                                                ok: "Update Anyway", destructive: true) {
            return
        }
        await install(release)
        if case .failed(let message) = phase {
            Alerts.message("Couldn't install the update", message
                + "\n\nYou can also update by running this in Terminal:\n\(Self.installCommand)")
        }
    }

    private func install(_ release: AppRelease) async {
        guard !isBusy || phase == .available(release) else { return }
        phase = .installing(release)
        let bundle = Bundle.main.bundleURL
        do {
            let newApp = try await Self.downloadAndVerify(release, near: bundle)
            try await Self.replace(bundle, with: newApp)
            Self.relaunch(bundle)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Steps (off the main thread)

    private struct GitHubRelease: Decodable {
        struct Asset: Decodable {
            let name: String
            let browser_download_url: URL
        }
        let tag_name: String
        let html_url: URL
        let assets: [Asset]
    }

    private nonisolated static var arch: String {
        #if arch(arm64)
        "arm64"
        #else
        "x86_64"
        #endif
    }

    private nonisolated static func fetchLatest() async throws -> AppRelease? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        guard status == 200 else { throw UpdateError("GitHub answered with status \(status). Try again later.") }

        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        let assets = Dictionary(release.assets.map { ($0.name, $0.browser_download_url) }, uniquingKeysWith: { a, _ in a })
        guard let zip = assets["Skillbook-\(version)-mac-\(arch).zip"], let sums = assets["SHA256SUMS.txt"] else { return nil }
        return AppRelease(version: version, pageURL: release.html_url, zipURL: zip, checksumsURL: sums)
    }

    /// Downloads the zip next to the app (same volume, so the swap is atomic), checks it
    /// against the release's SHA256SUMS.txt, unzips it and checks the app inside.
    private nonisolated static func downloadAndVerify(_ release: AppRelease, near bundle: URL) async throws -> URL {
        let fm = FileManager.default
        if bundle.path.contains("/AppTranslocation/") {
            throw UpdateError("macOS is running Skillbook from a temporary location. Move Skillbook to your Applications folder, open it from there and try again.")
        }
        guard fm.isWritableFile(atPath: bundle.deletingLastPathComponent().path) else {
            throw UpdateError("Skillbook can't write to \(bundle.deletingLastPathComponent().path).")
        }
        let work = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: bundle, create: true)

        let (downloaded, response) = try await URLSession.shared.download(from: release.zipURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw UpdateError("The download failed. Try again later.") }
        let zip = work.appendingPathComponent("Skillbook.zip")
        try fm.moveItem(at: downloaded, to: zip)

        let (sums, _) = try await URLSession.shared.data(from: release.checksumsURL)
        let name = release.zipURL.lastPathComponent
        let expected = String(decoding: sums, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .first { $0.hasSuffix(" " + name) }?
            .split(separator: " ").first.map { $0.lowercased() }
        let actual = SHA256.hash(data: try Data(contentsOf: zip)).map { String(format: "%02x", $0) }.joined()
        guard let expected, expected == actual else {
            throw UpdateError("The download doesn't match the release's checksum, so it wasn't installed.")
        }

        let unpacked = work.appendingPathComponent("unpacked")
        try run("/usr/bin/ditto", "-x", "-k", zip.path, unpacked.path)
        let app = unpacked.appendingPathComponent("Skillbook.app")
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info?["CFBundleShortVersionString"] as? String == release.version else {
            throw UpdateError("The download doesn't contain Skillbook \(release.version).")
        }
        try run("/usr/bin/codesign", "--verify", "--deep", "--strict", app.path)
        try? run("/usr/bin/xattr", "-dr", "com.apple.quarantine", app.path)
        return app
    }

    private nonisolated static func replace(_ bundle: URL, with newApp: URL) async throws {
        _ = try FileManager.default.replaceItemAt(bundle, withItemAt: newApp)
        // newApp was work/unpacked/Skillbook.app; remove the download folder.
        try? FileManager.default.removeItem(at: newApp.deletingLastPathComponent().deletingLastPathComponent())
    }

    /// Quits, then reopens the app once this process has exited. The window comes back
    /// only if it was open; otherwise Skillbook returns to the menu bar alone.
    private static func relaunch(_ bundle: URL) {
        let windowOpen = NSApp.windows.contains { $0.styleMask.contains(.titled) && $0.isVisible }
        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$2\" --args \"$3\"",
                           "sh", String(getpid()), bundle.path, windowOpen ? "--open" : Launch.backgroundFlag]
        try? shell.run()
        NSApp.terminate(nil)
    }

    private nonisolated static func run(_ tool: String, _ arguments: String...) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError("\(URL(fileURLWithPath: tool).lastPathComponent) failed while installing the update.")
        }
    }

    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}

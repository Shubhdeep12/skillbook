import SwiftUI

/// "Skillbook 1.2 is available [Update]". Shown in the menu bar panel and the sidebar
/// only while an update is available or installing.
struct UpdateBanner: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        switch updater.phase {
        case .available(let release):
            HStack(spacing: 9) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Skillbook \(release.version)")
                        .font(.system(size: 12, weight: .semibold))
                    Link("What's new", destination: release.pageURL)
                        .font(.system(size: 11))
                }
                .lineLimit(1)
                Spacer(minLength: 6)
                Button("Update") { Task { await updater.installInteractively(release) } }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .fixedSize()
                    .help("Download Skillbook \(release.version) and restart")
            }
            .bannerStyle()
        case .installing(let release):
            HStack(spacing: 9) {
                ProgressView().controlSize(.small)
                Text("Updating to \(release.version)…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
            }
            .bannerStyle()
        default:
            EmptyView()
        }
    }
}

private extension View {
    func bannerStyle() -> some View {
        padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.accentColor.opacity(0.1)))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).strokeBorder(Color.accentColor.opacity(0.18)))
    }
}

/// The Updates section of Settings → General.
struct UpdateSettingsSection: View {
    @Environment(Updater.self) private var updater

    var body: some View {
        @Bindable var updater = updater
        Section {
            Toggle("Check for updates automatically", isOn: $updater.checkAutomatically)
            Toggle("Install updates automatically", isOn: $updater.installAutomatically)
                .disabled(!updater.checkAutomatically)
            HStack {
                Text(status).foregroundStyle(.secondary)
                Spacer()
                if updater.isBusy { ProgressView().controlSize(.small) }
                Button("Check Now") { Task { await updater.checkInteractively() } }
                    .disabled(updater.isBusy)
            }
        } header: {
            Text("Updates")
        } footer: {
            Text("Updates come from Skillbook's GitHub releases. Automatic installs wait until no Skillbook window is open, then Skillbook restarts in the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var status: String {
        let version = "Version \(updater.currentVersion)"
        switch updater.phase {
        case .checking: return "\(version) · Checking…"
        case .available(let r): return "\(version) · \(r.version) is available"
        case .installing(let r): return "Updating to \(r.version)…"
        case .failed: return "\(version) · Last check failed"
        case .idle, .upToDate:
            guard let last = updater.lastCheck else { return version }
            return "\(version) · Checked \(last.formatted(.relative(presentation: .named)))"
        }
    }
}

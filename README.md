# Skillbook

<img src="assets/icon.svg" width="96" alt="Skillbook icon">

A macOS menu bar app that finds every agent skill (`SKILL.md`) on your Mac and lets you preview, edit, copy, move and organise them.

## Install

Paste this into Terminal:

```sh
curl -fsSL https://skillbook.okshubh.in/install.sh | bash
```

It downloads the latest release, puts Skillbook.app in `/Applications` (or `~/Applications`) and opens it. Installing this way skips the "Apple could not verify" warning, because files downloaded with curl aren't quarantined. The script is [`site/public/install.sh`](site/public/install.sh). Skillbook keeps itself up to date: it checks GitHub for new releases, shows an **Update** button in the menu bar panel and the sidebar, and installs updates on its own while no Skillbook window is open. Turn either off in Settings → General → Updates. Versions before 1.0.2 don't have the updater, so run the install command once more to get it.

### Or download the zip

Get the latest `Skillbook-<version>-mac-arm64.zip` from the [Releases](https://github.com/Shubhdeep12/skillbook/releases) page, unzip it, and move **Skillbook.app** to Applications. It needs macOS 15 or later on Apple Silicon.

Skillbook isn't notarized by Apple yet, so the first launch shows *"Apple could not verify “Skillbook” is free of malware"*. To open it anyway:

1. Click **Done** in that dialog.
2. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the Skillbook message.
3. Confirm with your password. After that it opens normally.

Or skip the dialog by running this once in Terminal:

```sh
xattr -dr com.apple.quarantine /Applications/Skillbook.app
```

## What it finds

It scans your home folder (configurable) and skips heavy folders like `Library` and `node_modules`. A full scan takes about a second. Each `SKILL.md` is sorted into one of these:

| Scope | Examples |
| --- | --- |
| **User** | `~/.claude/skills`, `~/.agents/skills`, `~/.claude-personal/skills`, claude.ai synced skills |
| **Projects** | any git repo, e.g. `repo/.claude/skills`, `repo/.cursor/skills` |
| **Plugins** | `~/.claude/plugins/cache/…`, Cursor and Codex plugin caches, editor extensions |
| **Built-in** | `~/.cursor/skills-cursor`, `~/.codex/skills/.system`, Gemini built-ins |
| **Folders** | anything else, e.g. `~/Downloads/skills` |

The tool (Claude, Cursor, Codex, Gemini, Agents, Copilot, Windsurf…) is worked out from the path.

**What counts as a skill:** the file is named `SKILL.md`, starts with a `---` YAML frontmatter block, and has a `description`. Warnings, shown under *Needs Attention*, flag a missing `name`, a name that isn't kebab-case or doesn't match its folder, a name over 64 or a description over 1024 characters, and an empty body.

Plugin caches keep every installed version, so only the newest copy of each plugin skill is shown. Marketplace catalog copies are hidden too. *View Options* or Settings shows them.

## Using it

- **Menu bar panel:** search, filter by scope, click a skill for a quick preview, then *Edit* or *Open*. Right-click a row for every action.
- **Manager window** (⌘-click *Open*, or the window button in the panel):
  - **Preview** (⌘1): rendered Markdown, frontmatter card, validation notes
  - **Edit** (⌘2): plain-text editor with highlighting, live validation and ⌘S to save
  - **Files** (⌘3): the skill folder's scripts, references and assets
- **Copy / Move To:** user skill folders, any repo (existing skills folders or a new `.claude/skills`), or *Choose Folder…*
- **Clipboard:** ⌘C copies the selected skill folders. Select a location in the sidebar, then ⌘V pastes them there. You can also paste them into Finder.
- **Drag and drop:** drag skills onto a sidebar location to copy them. Hold ⌥ while dropping to move them. You can also drag them to Finder.
- Duplicate, Rename (renames the folder and its `name:`), New Skill (⌘N), Move to Trash (⌘⌫)
- It rescans by itself when a `SKILL.md` changes on disk.

Safety: deleting sends folders to the Trash. Skillbook refuses to move or delete a folder that is a git repo root or a scan root. Before moving plugin, built-in or synced skills, it warns that their tool may overwrite them.

## Build

Only the Command Line Tools are needed. No Xcode.

```sh
scripts/build-app.sh            # → build/Skillbook.app
scripts/build-app.sh --install  # also copies to ~/Applications and launches it
scripts/build-app.sh --zip      # also makes build/Skillbook-<version>-mac-arm64.zip for a release
```

The app icon comes from `assets/icon.svg`. The build renders it into `AppIcon.icns` whenever the SVG changes.

The script calls `swiftc` directly and picks the newest macOS 26 SDK, because the macOS 27 SDK's SwiftUI needs a macro plugin that ships only with Xcode. `Package.swift` works when Xcode is installed. Pass `--open` at launch to show the manager window right away: `open ~/Applications/Skillbook.app --args --open`.

## Website

`site/` is the landing page (Astro). It has the same layout, fonts and theme switch as the cLogs site, plus an interactive demo of the app with made-up skills.

```sh
cd site && npm install && npm run dev
```

`.github/workflows/site.yml` deploys it to GitHub Pages on every push to `main` that touches `site/`. One-time setup: repo Settings → Pages → Source: GitHub Actions. The download button reads the latest GitHub release and links to its `*-mac-arm64.zip`. Until there is a release, it points to the build-from-source steps. `site/src/site.ts` assumes the repo is `Shubhdeep12/skillbook`; change `REPO` there if it's named differently.

## Releases

`.github/workflows/ci.yml` compiles the app on every push and pull request. `.github/workflows/release.yml` builds and zips the app when you push a version tag, then publishes a GitHub Release with the zip and its checksum. To release, bump `CFBundleShortVersionString` in `Resources/Info.plist`, commit, then:

```sh
git tag v1.0
git push origin v1.0
```

## License

MIT. See [LICENSE](LICENSE).

#!/usr/bin/env bash
# Skillbook installer: https://skillbook.okshubh.in
#
#   curl -fsSL https://skillbook.okshubh.in/install.sh | bash
#
# Downloads the latest release from GitHub, puts Skillbook.app in /Applications
# (or ~/Applications if /Applications isn't writable) and opens it.
# Source: https://github.com/Shubhdeep12/skillbook
#
# Options (environment variables):
#   SKILLBOOK_DIR=/path   install somewhere else
#   SKILLBOOK_NO_OPEN=1   don't open the app afterwards

set -euo pipefail

REPO="Shubhdeep12/skillbook"
TMP_DIR=""
trap 'rm -rf "${TMP_DIR:-}"' EXIT

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
info() { printf '  %s\n' "$*"; }
fail() { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }

# Wrapped in a function so a half-downloaded script never runs.
main() {
  bold "Installing Skillbook"

  [[ "$(uname -s)" == "Darwin" ]] || fail "Skillbook is a macOS app."
  [[ "$(uname -m)" == "arm64" ]] || fail "Skillbook needs an Apple Silicon Mac (M1 or later)."
  local major
  major="$(sw_vers -productVersion | cut -d. -f1)"
  (( major >= 15 )) || fail "Skillbook needs macOS 15 or later (this Mac has $(sw_vers -productVersion))."

  # The latest-release page redirects to .../releases/tag/vX.Y, which gives the version.
  local tag version url
  tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/$REPO/releases/latest" | sed 's#.*/tag/##')"
  [[ "$tag" == v* ]] || fail "Couldn't find the latest release at https://github.com/$REPO/releases"
  version="${tag#v}"
  url="https://github.com/$REPO/releases/download/$tag/Skillbook-$version-mac-arm64.zip"

  local dest="${SKILLBOOK_DIR:-}"
  if [[ -z "$dest" ]]; then
    if [[ -w /Applications ]]; then dest="/Applications"; else dest="$HOME/Applications"; fi
  fi
  mkdir -p "$dest"

  TMP_DIR="$(mktemp -d)"
  local tmp="$TMP_DIR"

  info "Downloading Skillbook ${version}..."
  curl -fsSL --retry 2 -o "$tmp/Skillbook.zip" "$url" || fail "Download failed: $url"
  ditto -x -k "$tmp/Skillbook.zip" "$tmp/unpacked"
  [[ -d "$tmp/unpacked/Skillbook.app" ]] || fail "The download didn't contain Skillbook.app."

  # Quit a running copy before replacing it.
  if pgrep -x Skillbook >/dev/null 2>&1; then
    info "Quitting the running Skillbook..."
    osascript -e 'quit app "Skillbook"' >/dev/null 2>&1 || pkill -x Skillbook || true
    sleep 1
  fi

  info "Installing to $dest/Skillbook.app"
  rm -rf "${dest:?}/Skillbook.app"
  ditto "$tmp/unpacked/Skillbook.app" "$dest/Skillbook.app"
  # Files fetched with curl aren't quarantined; clear the flag anyway in case a proxy added it.
  xattr -dr com.apple.quarantine "$dest/Skillbook.app" 2>/dev/null || true

  if [[ -z "${SKILLBOOK_NO_OPEN:-}" ]]; then
    open "$dest/Skillbook.app"
    bold "Done. Skillbook is in your menu bar (the book icon)."
  else
    bold "Done. Installed $dest/Skillbook.app"
  fi
}

main "$@"

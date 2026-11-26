// Change REPO if the GitHub repository gets a different name.
export const REPO = 'Shubhdeep12/skillbook';
export const REPO_URL = `https://github.com/${REPO}`;
export const RELEASES_URL = `${REPO_URL}/releases`;
export const VERSION = '1.0.3';
/** For search results and link previews (about 155 characters). */
export const DESCRIPTION =
  'A free macOS menu bar app that finds every agent skill (SKILL.md) for Claude, Cursor, Codex and more, then lets you preview, check, edit, copy and move them.';
export const TAGLINE = 'Every agent skill on your Mac, in one place. Find, check, preview and edit them from the menu bar.';

/** Path under the configured base, e.g. url('icon-512.png'). */
export const url = (p = '') => `${import.meta.env.BASE_URL.replace(/\/$/, '')}/${p.replace(/^\//, '')}`;

// Change REPO if the GitHub repository gets a different name.
export const REPO = 'Shubhdeep12/skillbook';
export const REPO_URL = `https://github.com/${REPO}`;
export const RELEASES_URL = `${REPO_URL}/releases`;
export const VERSION = '1.0.3';
export const TAGLINE = 'Every agent skill on your Mac, in one place. Find, check, preview and edit them from the menu bar.';

/** Path under the configured base, e.g. url('icon-512.png'). */
export const url = (p = '') => `${import.meta.env.BASE_URL.replace(/\/$/, '')}/${p.replace(/^\//, '')}`;

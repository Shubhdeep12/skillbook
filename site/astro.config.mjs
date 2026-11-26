import { defineConfig } from 'astro/config';

// SITE_ORIGIN / SITE_BASE come from actions/configure-pages in CI, so the same
// build works on https://<user>.github.io/skillbook and on a custom domain (base "/").
export default defineConfig({
  site: process.env.SITE_ORIGIN || 'https://shubhdeep12.github.io',
  base: process.env.SITE_BASE ?? '/skillbook',
});

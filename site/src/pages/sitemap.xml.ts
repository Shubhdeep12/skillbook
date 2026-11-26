import type { APIRoute } from 'astro';
import { url } from '../site';

// One page, so a hand-written sitemap is enough.
export const GET: APIRoute = ({ site }) => {
  const home = new URL(url(''), site).href;
  const today = new Date().toISOString().slice(0, 10);
  const xml = `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
  <url>
    <loc>${home}</loc>
    <lastmod>${today}</lastmod>
  </url>
</urlset>
`;
  return new Response(xml, { headers: { 'Content-Type': 'application/xml; charset=utf-8' } });
};

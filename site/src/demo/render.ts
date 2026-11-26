// Pure HTML-string renderers for the interactive demo. Used on the server for
// the first paint and in the browser after every interaction.
import type { Scope, Skill } from './data';
import { LOCATIONS, SCOPES, SKILLS, TOOLS } from './data';

export type Tab = 'preview' | 'edit' | 'files';
export type State = {
  where: string; // 'all' | scope id | location id
  sel: string;
  tab: Tab;
  q: string;
  texts: Record<string, string>;
};

export const initialState = (): State => ({
  where: 'all',
  sel: 's1',
  tab: 'preview',
  q: '',
  texts: Object.fromEntries(SKILLS.map((s) => [s.id, s.text])),
});

const esc = (s: string) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

// ---- skill parsing + the same checks the app runs ----

export function parse(text: string) {
  const lines = text.split('\n');
  if (lines[0]?.trim() !== '---') return { ok: false, fields: [] as [string, string][], body: text };
  const end = lines.findIndex((l, i) => i > 0 && l.trim() === '---');
  if (end < 0) return { ok: false, fields: [] as [string, string][], body: text };
  const fields: [string, string][] = [];
  for (const l of lines.slice(1, end)) {
    const m = l.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    if (m) fields.push([m[1], m[2].trim()]);
  }
  return { ok: true, fields, body: lines.slice(end + 1).join('\n') };
}

export function check(skill: Skill, text: string): { level: 'ok' | 'warn' | 'bad'; issues: string[] } {
  const p = parse(text);
  if (!p.ok) return { level: 'bad', issues: ['No YAML frontmatter (--- … ---) at the top'] };
  const get = (k: string) => p.fields.find(([key]) => key === k)?.[1] ?? '';
  const name = get('name'), desc = get('description');
  if (!desc) return { level: 'bad', issues: ['Missing description, which agents use to decide when to load it'] };
  const issues: string[] = [];
  if (!name) issues.push('No name field, so agents fall back to the folder name');
  else if (!/^[a-z0-9]+(-[a-z0-9]+)*$/.test(name)) issues.push('Name should use lowercase letters, digits and hyphens');
  else if (name !== skill.folder) issues.push(`Name “${name}” differs from its folder “${skill.folder}”`);
  if (desc.length > 1024) issues.push(`Description is ${desc.length} characters (limit 1024)`);
  if (!p.body.trim()) issues.push('No instructions after the frontmatter');
  return { level: issues.length ? 'warn' : 'ok', issues };
}

const nameOf = (st: State, s: Skill) => parse(st.texts[s.id]).fields.find(([k]) => k === 'name')?.[1] || s.folder;
const descOf = (st: State, s: Skill) => parse(st.texts[s.id]).fields.find(([k]) => k === 'description')?.[1] || '';
const locOf = (s: Skill) => LOCATIONS.find((l) => l.id === s.loc)!;

// ---- tiny Markdown (headings, lists, tables, quotes, code) ----

function inline(s: string) {
  return esc(s)
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>')
    .replace(/(^|\W)\*([^*]+)\*/g, '$1<i>$2</i>');
}

export function markdown(src: string) {
  const lines = src.split('\n');
  let html = '';
  for (let i = 0; i < lines.length; ) {
    const t = lines[i].trim();
    if (!t) { i++; continue; }
    if (t.startsWith('```')) {
      const lang = t.slice(3).trim();
      const body: string[] = [];
      for (i++; i < lines.length && !lines[i].trim().startsWith('```'); i++) body.push(lines[i]);
      i++;
      html += `<div class="code">${lang ? `<em>${esc(lang)}</em>` : ''}<pre>${esc(body.join('\n'))}</pre></div>`;
      continue;
    }
    const h = t.match(/^(#{1,4})\s+(.*)$/);
    if (h) { html += `<h${h[1].length + 2}>${inline(h[2])}</h${h[1].length + 2}>`; i++; continue; }
    if (t.startsWith('>')) {
      const q: string[] = [];
      for (; i < lines.length && lines[i].trim().startsWith('>'); i++) q.push(lines[i].trim().slice(1).trim());
      html += `<blockquote>${inline(q.join(' '))}</blockquote>`;
      continue;
    }
    if (t.startsWith('|')) {
      const rows: string[][] = [];
      for (; i < lines.length && lines[i].trim().startsWith('|'); i++) {
        const cells = lines[i].trim().replace(/^\||\|$/g, '').split('|').map((c) => c.trim());
        if (!cells.every((c) => /^:?-+:?$/.test(c))) rows.push(cells);
      }
      html += `<table>${rows.map((r, ri) => `<tr>${r.map((c) => (ri ? `<td>${inline(c)}</td>` : `<th>${inline(c)}</th>`)).join('')}</tr>`).join('')}</table>`;
      continue;
    }
    if (/^([-*+]|\d+\.)\s/.test(t)) {
      const ordered = /^\d+\./.test(t);
      const items: string[] = [];
      for (; i < lines.length && /^([-*+]|\d+\.)\s/.test(lines[i].trim()); i++) items.push(lines[i].trim().replace(/^([-*+]|\d+\.)\s+/, ''));
      const tag = ordered ? 'ol' : 'ul';
      html += `<${tag}>${items.map((x) => `<li>${inline(x)}</li>`).join('')}</${tag}>`;
      continue;
    }
    const para: string[] = [];
    for (; i < lines.length && lines[i].trim() && !/^(#|```|>|\||[-*+]\s|\d+\.\s)/.test(lines[i].trim()); i++) para.push(lines[i].trim());
    html += `<p>${inline(para.join(' '))}</p>`;
  }
  return html;
}

// ---- icons ----

export const FOLDER = `<svg class="ico-folder" viewBox="0 0 20 16" aria-hidden="true"><path d="M1 3.2C1 2 1.9 1 3.1 1h4.1c.6 0 1.1.2 1.5.6l1.1 1.1c.4.4.9.6 1.5.6h5.6c1.2 0 2.1.9 2.1 2.1V13c0 1.2-.9 2.1-2.1 2.1H3.1C1.9 15.1 1 14.2 1 13z" fill="#1b8cf2"/><path d="M1 5.6c0-1.1.9-2 2-2h14c1.1 0 2 .9 2 2V13c0 1.2-.9 2.1-2.1 2.1H3.1C1.9 15.1 1 14.2 1 13z" fill="#4fb0ff"/></svg>`;
const DOC = `<svg class="ico-doc" viewBox="0 0 16 20" aria-hidden="true"><path d="M3 1.5h6.5L14 6v11.3c0 .7-.6 1.2-1.2 1.2H3.2c-.7 0-1.2-.6-1.2-1.2V2.7C2 2 2.5 1.5 3.2 1.5z M9.3 1.7V6.2h4.5" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linejoin="round"/><path d="M5 10h6M5 12.6h6M5 15.2h4" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>`;
const SCOPE_ICON: Record<Scope, string> = {
  user: FOLDER,
  project: FOLDER,
  plugin: `<svg class="ico-glyph" viewBox="0 0 16 16" aria-hidden="true"><path d="M6 2.5a1.5 1.5 0 0 1 3 0V4h3v3h-1.5a1.5 1.5 0 0 0 0 3H12v3.5H8.5V12a1.5 1.5 0 0 0-3 0v1.5H2V10h1.5a1.5 1.5 0 0 0 0-3H2V4h4z" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linejoin="round"/></svg>`,
  builtin: `<svg class="ico-glyph" viewBox="0 0 16 16" aria-hidden="true"><path d="M8 1.5 14 4.5v7L8 14.5 2 11.5v-7zM2 4.5l6 3 6-3M8 7.5v7" fill="none" stroke="currentColor" stroke-width="1.1" stroke-linejoin="round"/></svg>`,
};

// ---- views ----

export function visible(st: State) {
  const q = st.q.trim().toLowerCase();
  return SKILLS.filter((s) => {
    const loc = locOf(s);
    const inWhere = st.where === 'all' || st.where === loc.scope || st.where === loc.id;
    const text = `${nameOf(st, s)} ${descOf(st, s)} ${loc.title}`.toLowerCase();
    return inWhere && (!q || text.includes(q));
  });
}

export function renderSide(st: State) {
  const count = (pred: (s: Skill) => boolean) => SKILLS.filter(pred).length;
  const item = (id: string, label: string, icon: string, n: number) =>
    `<button class="si${st.where === id ? ' sel' : ''}" data-act="where" data-id="${id}">${icon}<span>${esc(label)}</span><i>${n}</i></button>`;
  let html = `<div class="sec">Library</div>`;
  html += item('all', 'All Skills', DOC, SKILLS.length);
  for (const sc of SCOPES) html += item(sc.id, sc.title, sc.id === 'user' || sc.id === 'project' ? SCOPE_ICON.project : SCOPE_ICON[sc.id], count((s) => locOf(s).scope === sc.id));
  for (const sc of SCOPES) {
    const locs = LOCATIONS.filter((l) => l.scope === sc.id);
    html += `<div class="sec">${sc.title}</div>`;
    for (const l of locs) html += item(l.id, l.title, SCOPE_ICON[l.scope], count((s) => s.loc === l.id));
  }
  return html;
}

export function renderList(st: State) {
  const list = visible(st);
  if (!list.length) return `<div class="none">No skills match.</div>`;
  let html = '';
  let last = '';
  for (const s of list) {
    const loc = locOf(s);
    if (loc.id !== last) {
      html += `<div class="lh"><b>${esc(loc.title)}</b><span>${esc(loc.sub)}</span></div>`;
      last = loc.id;
    }
    const c = check(s, st.texts[s.id]);
    const warn = c.level === 'ok' ? '' : `<em class="w-${c.level}" title="${esc(c.issues.join('\n'))}">${c.level === 'bad' ? '✕' : '!'}</em>`;
    html += `<button class="row${st.sel === s.id ? ' sel' : ''}" data-act="row" data-id="${s.id}">
      ${DOC}
      <span class="rt"><b>${esc(nameOf(st, s))}${warn}</b><span>${esc(descOf(st, s))}</span></span>
      <span class="tool"><i style="background:${TOOLS[s.tool].color}"></i>${TOOLS[s.tool].name}</span>
    </button>`;
  }
  return html;
}

export function renderDetail(st: State) {
  const s = SKILLS.find((x) => x.id === st.sel);
  if (!s) return `<p class="pick">Select a skill</p>`;
  const text = st.texts[s.id];
  const loc = locOf(s);
  const c = check(s, text);
  const tabs = (['preview', 'edit', 'files'] as Tab[])
    .map((t) => `<button class="${st.tab === t ? 'on' : ''}" data-act="tab" data-id="${t}">${t[0].toUpperCase() + t.slice(1)}</button>`)
    .join('');
  const actions = `<span class="acts">
      <button data-act="copy">Copy To…</button><button data-act="move">Move To…</button><button data-act="reveal">Show in Finder</button>
    </span>`;
  let body = '';
  if (st.tab === 'preview') {
    const p = parse(text);
    const extra = p.fields.filter(([k]) => k !== 'name' && k !== 'description');
    body = `<div class="pv">
      <div class="hd">${DOC}<div><h3>${esc(nameOf(st, s))}</h3><p>${esc(descOf(st, s))}</p></div></div>
      <div class="chips"><span><i style="background:${TOOLS[s.tool].color}"></i>${TOOLS[s.tool].name}</span><span>${loc.scope === 'builtin' ? 'Built-in' : loc.scope[0].toUpperCase() + loc.scope.slice(1)} · ${esc(loc.title)}</span><span>Edited ${s.edited}</span></div>
      <div class="path">${esc(s.path)}</div>
      ${c.level === 'ok' ? '' : `<div class="issues ${c.level}"><b>${c.level === 'bad' ? 'Not recognised as a skill' : 'Suggestions'}</b>${c.issues.map((x) => `<span>• ${esc(x)}</span>`).join('')}</div>`}
      ${extra.length ? `<dl>${extra.map(([k, v]) => `<dt>${esc(k)}</dt><dd>${esc(v)}</dd>`).join('')}</dl>` : ''}
      <div class="md">${markdown(p.ok ? p.body : text)}</div>
    </div>`;
  } else if (st.tab === 'edit') {
    body = `<div class="ed"><textarea spellcheck="false" data-editor aria-label="SKILL.md">${esc(text)}</textarea>
      <span class="status ${c.level}" data-status>${statusLabel(c)}</span></div>`;
  } else {
    body = `<div class="files">${s.files.map(([f, size]) => `<div class="file">${f.includes('/') ? FOLDER : DOC}<span>${esc(f)}</span><i>${size}</i></div>`).join('')}</div>`;
  }
  return `<div class="tabs">${tabs}${actions}</div><div class="dbody">${body}</div>`;
}

export function statusLabel(c: ReturnType<typeof check>) {
  return c.level === 'ok' ? '✓ Valid skill' : `${c.level === 'bad' ? '✕' : '!'} ${esc(c.issues[0])}`;
}

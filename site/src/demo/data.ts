// Made-up skills for the interactive demo on the landing page.

export type Tool = 'claude' | 'agents' | 'cursor' | 'codex';
export type Scope = 'user' | 'project' | 'plugin' | 'builtin';

export type Location = { id: string; title: string; sub: string; scope: Scope };

export type Skill = {
  id: string;
  folder: string;
  tool: Tool;
  loc: string;
  path: string;
  edited: string;
  text: string;
  files: [string, string][];
};

export const TOOLS: Record<Tool, { name: string; color: string }> = {
  claude: { name: 'Claude', color: '#d97857' },
  agents: { name: 'Agents', color: '#5a66e6' },
  cursor: { name: 'Cursor', color: '#98989d' },
  codex: { name: 'Codex', color: '#12a080' },
};

export const SCOPES: { id: Scope; title: string }[] = [
  { id: 'user', title: 'User' },
  { id: 'project', title: 'Projects' },
  { id: 'plugin', title: 'Plugins' },
  { id: 'builtin', title: 'Built-in' },
];

export const LOCATIONS: Location[] = [
  { id: 'claude', title: 'Claude', sub: '~/.claude/skills', scope: 'user' },
  { id: 'agents', title: 'Agents', sub: '~/.agents/skills', scope: 'user' },
  { id: 'acme-web', title: 'acme-web', sub: '~/code/acme-web', scope: 'project' },
  { id: 'payments-api', title: 'payments-api', sub: '~/code/payments-api', scope: 'project' },
  { id: 'release-kit', title: 'release-kit', sub: 'Claude plugin · v2.1.0', scope: 'plugin' },
  { id: 'cursor-builtins', title: 'Cursor built-ins', sub: '~/.cursor', scope: 'builtin' },
];

const md = (name: string, description: string, body: string, extra = '') =>
  `---\nname: ${name}\ndescription: ${description}\n${extra}---\n\n${body.trim()}\n`;

export const SKILLS: Skill[] = [
  {
    id: 's1', folder: 'pr-review', tool: 'claude', loc: 'claude', path: '~/.claude/skills/pr-review/SKILL.md', edited: '2 days ago',
    text: md('pr-review', 'Review a pull request for bugs, risky changes and missing tests. Use when the user asks for a review or pastes a PR link.', `
# PR review

Read the diff first, then the files it touches.

## Steps

1. Run \`gh pr diff\` and list every changed file.
2. Flag anything that changes behaviour without a test.
3. Check error paths, not only the happy path.
4. Write findings **most severe first**, one line each.

## Output

| Severity | Meaning |
| --- | --- |
| High | Wrong result or data loss |
| Low | Style or naming |
`, 'allowed-tools: Bash(gh *), Read, Grep\n'),
    files: [['SKILL.md', '1.2 KB'], ['checklist.md', '640 B']],
  },
  {
    id: 's2', folder: 'release-notes', tool: 'claude', loc: 'claude', path: '~/.claude/skills/release-notes/SKILL.md', edited: '1 week ago',
    text: md('release-notes', 'Draft release notes from merged pull requests since the last tag. Use for "write the changelog" or "what shipped".', `
# Release notes

Group merged PRs by user-facing change, not by author.

- Lead with what people can now do.
- Link each item to its PR.
- Leave out refactors nobody will notice.

\`\`\`sh
git log $(git describe --tags --abbrev=0)..HEAD --merges --oneline
\`\`\`
`),
    files: [['SKILL.md', '820 B'], ['template.md', '410 B']],
  },
  {
    id: 's3', folder: 'brand-voice', tool: 'agents', loc: 'agents', path: '~/.agents/skills/brand-voice/SKILL.md', edited: '3 weeks ago',
    text: md('brand-voice', 'Rewrite copy in the house voice: plain, warm, no hype. Use whenever writing UI text, emails or docs.', `
# Brand voice

> Say the thing. Then stop.

- Short sentences. Active voice.
- No "simply", "just" or "seamless".
- Numbers as digits.
`),
    files: [['SKILL.md', '540 B'], ['examples/before-after.md', '2.3 KB']],
  },
  {
    id: 's4', folder: 'db-migrations', tool: 'claude', loc: 'acme-web', path: '~/code/acme-web/.claude/skills/db-migrations/SKILL.md', edited: 'yesterday',
    text: md('db-migrations', 'Write and check Postgres migrations for acme-web. Use when adding a column, index or table.', `
# Migrations

1. Generate with \`pnpm db:new <name>\`.
2. Every migration needs a down step.
3. Add indexes \`CONCURRENTLY\` on big tables.
4. Run \`pnpm db:check\` before committing.
`),
    files: [['SKILL.md', '960 B'], ['scripts/check.sh', '1.1 KB']],
  },
  {
    id: 's5', folder: 'design-tokens', tool: 'cursor', loc: 'acme-web', path: '~/code/acme-web/.cursor/skills/design-tokens/SKILL.md', edited: '4 days ago',
    text: md('Design Tokens', 'Use the acme design tokens instead of raw colours and spacing.', `
# Design tokens

Use \`var(--space-3)\`, never \`12px\`.
`),
    files: [['SKILL.md', '300 B']],
  },
  {
    id: 's6', folder: 'incident-triage', tool: 'codex', loc: 'payments-api', path: '~/code/payments-api/.agents/skills/incident-triage/SKILL.md', edited: '2 months ago',
    text: md('incident-triage', 'Triage a production incident in payments-api: find the failing service, the first bad deploy and the blast radius.', `
# Incident triage

## First five minutes

1. Check the error-rate dashboard.
2. Find the first deploy after errors began.
3. Decide: roll back or fix forward.

Write the timeline as you go.
`),
    files: [['SKILL.md', '1.4 KB'], ['runbook.md', '3.8 KB'], ['scripts/last-deploys.sh', '700 B']],
  },
  {
    id: 's7', folder: 'changelog', tool: 'claude', loc: 'release-kit', path: '~/.claude/plugins/cache/acme/release-kit/2.1.0/skills/changelog/SKILL.md', edited: '1 month ago',
    text: md('changelog', 'Keep CHANGELOG.md in Keep a Changelog format. Use when cutting a release.', `
# Changelog

Sections: **Added**, **Changed**, **Fixed**, **Removed**.
`),
    files: [['SKILL.md', '450 B']],
  },
  {
    id: 's8', folder: 'version-bump', tool: 'claude', loc: 'release-kit', path: '~/.claude/plugins/cache/acme/release-kit/2.1.0/skills/version-bump/SKILL.md', edited: '1 month ago',
    text: md('version-bump', 'Bump the version in package.json and tag the release. Use for "cut 1.4.0" or "bump the patch".', `
# Version bump

1. Update \`package.json\`.
2. Commit as \`release: vX.Y.Z\`.
3. Tag and push the tag.
`),
    files: [['SKILL.md', '380 B']],
  },
  {
    id: 's9', folder: 'create-rule', tool: 'cursor', loc: 'cursor-builtins', path: '~/.cursor/skills-cursor/create-rule/SKILL.md', edited: '3 months ago',
    text: md('create-rule', 'Create a Cursor rule file from a description of the behaviour you want.', `
# Create rule

Ask what the rule should do, then write it to \`.cursor/rules\`.
`),
    files: [['SKILL.md', '610 B']],
  },
];

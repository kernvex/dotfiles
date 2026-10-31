# Global preferences

## Teaching workspaces (the `teach` skill)

A teaching workspace is any directory holding a `MISSION.md` beside `lessons/`
and `reference/` — most live under `~/Documents/Learning/`.

Every lesson and reference page in such a workspace must load the fullscreen
component, which binds `f` to toggle fullscreen reading:

```html
<script src="../assets/fullscreen.js"></script>
```

Before writing a page, make sure `assets/fullscreen.js` exists in the workspace;
if it doesn't, copy it from `~/.claude/templates/teach/fullscreen.js`. Never
inline or reimplement it — the template is the single source of truth, and
`teach-fullscreen --apply` re-syncs every workspace from it.

The one exception is a page that already binds fullscreen itself (slide decks
with their own key handler): a second binding would toggle twice on one keypress.

## Opening things in my browser

Safari is my default browser so that stray links land somewhere harmless; I read
in Chrome, where each account has its own browser identity (a Chrome profile).
Whatever you open for me — an `http(s)` URL, or a local `.html`/`.htm` page such
as a teach lesson or a report — goes to the browser identity of the folder that
owns it:

```bash
identity browser open --from <dir> <url>
```

`<dir>` is that folder:

- a URL: your primary working directory;
- a file inside your primary working directory: that directory, even when the
  file's path runs through a symlink that leads elsewhere, because the work still
  belongs to the folder you are in;
- any other file: the folder the file lives in.

Pass a file as an absolute `file://` URL: Chrome is launched from `/`, so a
relative path resolves against the wrong place.

When a tool would open the page itself (`gh pr view --web`, `gh browse`), fetch
its URL instead — `gh browse --no-browser`, `gh pr view --json url -q .url` — and
open that. Login flows (`gh auth login` and the like) run as they are.

Plain `open` keeps everything else: an app named on purpose (`open -a DataGrip`,
Obsidian, Finder) and a file whose default app is not a browser. A browser you
drive (Claude in Chrome, Playwright) picks its profile by its own mechanism and
sits outside this rule.

When `identity` is not on PATH (any other machine), use plain `open`. When it
refuses, the refusal is the answer: show me its error, which names the fix,
together with the link. Plain `open` at that point would put the link in Safari,
the detour this rule exists to remove.

## Arabic-script text in HTML

Any HTML page you author containing Arabic-script text (U+0600–U+06FF — Persian,
Arabic, Kurdish) must set this stack on that text:

```css
font-family: "Vazirmatn", "Geeza Pro", system-ui, sans-serif;
```

Vazirmatn is the font; the rest is fallback. Note it is *Vazirmatn*, not the
discontinued *Vazir*.

Ship the font with the page: `@font-face` pointing at a local
`fonts/vazirmatn-400.woff2` (plus `-700` where bold is used), copied from a
workspace that already has them. Never `@import` from a CDN and never rely on the
font being installed — both render correctly here and degrade the moment the file
travels. Never use Roboto for this text: it has no Arabic coverage and falls back
unpredictably.

This is keyed to the script in the file, not to the directory, so it holds
everywhere — not only in teaching workspaces.

## Text I will send as myself

When you draft something for me to send — an email, a message, a post, anything
addressed to another person — it must not read as machine-written. This covers
the draft only. Repo docs, ADRs and your replies to me are exempt, and their
em-dash-heavy style is deliberate, not an oversight.

In drafts, avoid:

1. Em-dashes (`—`), and en-dashes (`–`) standing in for them
2. Curly quotes and the `…` ellipsis character
3. "It's not just X, it's Y" and similar antithesis-for-emphasis
4. Rule-of-three lists where two items would do
5. Bullet lists or bold headers inside what should be a paragraph
6. Filler openers such as "I hope this finds you well"

Fix these by rewriting the sentence, never by swapping `—` for ` - `. The
substitution keeps the interrupted-clause rhythm, which is the real tell, and
adds a second one.

Use `—` only when quoting verbatim, writing about the character itself, when it
appears in a proper noun or title, or when I ask for it. That list is closed.

Treat a draft as in scope when I say so, or when it plainly looks like a message.
Bias toward treating borderline cases as in scope; when it is a genuine
coin-flip, ask.

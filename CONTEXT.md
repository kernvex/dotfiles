# Glossary

Ubiquitous language for this dotfiles repo. Glossary only — no implementation
details, no decisions (those live in `docs/adr/`).

## Identity terms

- **Effective identity** — the commit identity git actually resolves in the
  current directory: `git config user.name` evaluated in that cwd, after all
  `[include]` and `[includeIf]` routing has been applied. This is "who you are
  about to commit as, right now."

- **Default identity** — the personal identity set at the top of the public
  `~/.gitconfig` (`kernvex`). Applies wherever no `includeIf` rule takes over.

- **Routed identity** — an identity supplied by an `[includeIf "gitdir:…"]` rule
  (e.g. a company account for repos under that company's folder). The routing rules
  themselves live in machine-local, untracked config (`~/.config/git/local.inc`),
  never in this public repo.

- **Expected identity** — the identity a directory *should* commit as, derived
  from the `includeIf gitdir` rules: the routed identity if the cwd falls under a
  routing rule, otherwise the default identity. Computed independently of what git
  actually resolved, so it can be compared against the effective identity.

- **Identity mismatch** — effective identity ≠ expected identity. Means the
  routing that should have applied did not (or a local `.git/config` override
  fired). The "am I about to commit as the wrong person?" alarm.

- **Routed folder** — a directory an `includeIf gitdir:` rule covers. Since the
  routing rules exist precisely to separate employers from personal work, "is
  this folder routed?" is how tooling asks "is this company work?" without any
  identity, employer or path being named in the code.

- **Seat** — the Claude Code account answering in a session, selected by the
  `CLAUDE_CONFIG_DIR` environment variable. One macOS account can carry several,
  one per human-and-employer pair.

- **Default seat** — the machine owner's, used when `CLAUDE_CONFIG_DIR` is unset
  or points at `~/.claude`.

- **Named seat** — any other: a directory `~/.claude-<first>-<last>-<company>`,
  named so that two people sharing a first name cannot collide. The directory
  name is the seat's unique identifier.

- **Seat account** — the address a seat last logged in as, recorded as
  `oauthAccount.emailAddress` in that seat's config file. Distinct from Keychain
  state, which is what `claude auth status` reports.

- **Seat mismatch** — the seat account disagrees with the effective identity of
  the folder you are in: a company folder answered by the wrong account, or a
  personal folder answered by someone else's seat. The "whose subscription is
  paying for this, and whose transcripts is it landing in?" alarm, and the
  Claude-side counterpart of an identity mismatch.

## Location terms

- **Display path** — the human-facing location string shown for a directory:
  - not in a git repo → the leaf directory name;
  - at a repo root → `<parent-dir>/<repo-name>` (e.g. `kernvex/dotfiles`), so the
    surrounding "world" (personal `kernvex` vs a client folder) stays visible;
  - nested inside a repo → `<repo-name>/<path-within-repo>`.

## Session terms

- **Search path** — a root directory the sessionizer walks to gather candidates,
  descending a fixed number of levels rather than to the bottom of the tree. The
  standing set (`~/`, `~/Documents/Projects`) is the "where my work lives" answer.

- **Extra search path** — a search path that carries its own depth (`~/.config:2`,
  `~/Documents/Learning:1`) instead of inheriting the default. For a root whose
  useful directories sit at one level and whose scaffolding sits below them, the
  explicit depth is what keeps the scaffolding out of the picker.

- **Session candidate** — anything the picker offers: a walked directory, or a live
  tmux session shown as `[TMUX] <name>`. The current session is never a candidate —
  you cannot jump to where you already are.

## Teaching terms

- **Teaching workspace** — a directory that *is* a course: a `MISSION.md` saying why
  the topic matters, beside the `lessons/` and `reference/` pages built from it. The
  unit the `teach` skill reads and writes. Most sit under `~/Documents/Learning`, but
  it is the mission file that makes one, not the location — a course copied into
  `Documents/Projects` is still a teaching workspace.

## Drafting terms

- **Shareable draft** — text written for you to send onward as your own: an email, a
  message, a post. Distinguished from repo prose (docs, ADRs, commit messages), which
  is openly agent-written, and from replies in a conversation, which never leave it.
  The line is *apparent authorship*: a shareable draft will be read as your writing,
  by someone who was not here when it was written.

- **AI tell** — a feature of text that marks it as machine-written regardless of
  whether it is any good: the characteristic punctuation, antithesis for emphasis,
  three-item cadence, bulleted structure where a paragraph belongs. A property of
  form, not of correctness — a paragraph can be accurate, well-argued, and still
  riddled with them.

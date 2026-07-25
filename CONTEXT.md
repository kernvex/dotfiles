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
  (e.g. company `josh-y8` for repos under the Bench folder). The routing rules
  themselves live in machine-local, untracked config (`~/.config/git/local.inc`),
  never in this public repo.

- **Expected identity** — the identity a directory *should* commit as, derived
  from the `includeIf gitdir` rules: the routed identity if the cwd falls under a
  routing rule, otherwise the default identity. Computed independently of what git
  actually resolved, so it can be compared against the effective identity.

- **Identity mismatch** — effective identity ≠ expected identity. Means the
  routing that should have applied did not (or a local `.git/config` override
  fired). The "am I about to commit as the wrong person?" alarm.

## Location terms

- **Display path** — the human-facing location string shown for a directory:
  - not in a git repo → the leaf directory name;
  - at a repo root → `<parent-dir>/<repo-name>` (e.g. `kernvex/dotfiles`), so the
    surrounding "world" (personal `kernvex` vs company `Bench`) stays visible;
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

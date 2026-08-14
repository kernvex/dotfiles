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
  - nested inside a repo → `<repo-name>/<path-within-repo>`;
  - inside a linked worktree → anchored on the **owning repo** rather than on the
    worktree, which is a repo root in its own right and would otherwise show only
    its scaffolding (`.worktrees/feature`). The world and the owning repo lead at
    every depth, so the repo the work belongs to can never scroll out of the
    string. A worktree parked outside its repo keeps both ends and elides the
    journey between them with a single `…`.

- **Owning repo** — for a linked worktree, the repo it was created from: the one
  whose history a commit there lands in. Distinct from the directory the worktree
  sits in, which is scaffolding and may be anywhere on disk.

## Sessionizer terms

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

- **Candidate path** — the absolute directory a session candidate stands for: the
  walked directory itself, or, for a live session, the directory that session works
  in. What the picker means by a candidate regardless of how the line reads, so that
  jumping to one and copying one are the same question answered twice.

## Conversation terms

- **Conversation** — one Claude Code session: the transcript a pane is attached
  to, brought back by `claude --resume`. Called a *conversation* here and never a
  session, because a session in this repo is already a tmux session (above), and
  the two differ in the way that matters most — a tmux session dies with its
  server, a conversation does not.

- **Conversation id** — Claude's own identifier for a conversation, read from the
  SessionStart hook's `session_id` and stamped onto its pane as
  `@claude_session`. A resume reuses it, which makes it the only name for a
  conversation that survives a restart, and therefore the only safe answer to
  "is this record mine?".

- **Pane id** — tmux's `%N`. Unique only within one tmux server: a restored
  layout comes up under a new server that re-issues ids from `%0`, so a pane id
  written in a previous life belongs to nobody. Identifies a slot for as long as
  the server lives, never a conversation.

- **Handle** — the one name worn by both a tmux window and the conversation
  inside it: what `prefix+,` sets, what the window pill shows, and what is pushed
  into Claude as `/rename`. One name in two places, kept equal.

- **Conversation map** — the append-only record joining a conversation id to the
  pane, directory and handle it was last seen under, kept on disk as
  `sessions.log`. Rewritten on every start and resume, so it heals itself rather
  than having to be right in advance.

- **Taken handle** — a handle already spoken for in a directory: a live window's
  name, or one held in the conversation map by a conversation other than this
  one. A dead pane does not release a handle, because that conversation is still
  resumable under the name it was given. Only a window's *own* past is forgiven,
  matched by conversation id; everything else collides and walks to `-2`.

## Window navigation terms

- **Slot** — a digit 0–9 that permanently names one destination, reached by holding
  Hyper and pressing it. A slot's meaning is fixed: it points at the same place after a
  restart, after the thing it names has been closed, and after that thing has been
  renamed. The same idea as a harpoon mark, a tmux window index or a WezTerm tab number,
  raised to the level of macOS windows.

- **Slot table** — the mapping from each slot to what it names. Machine-local and never
  committed: it carries real account labels, and the profile directories it refers to
  denote different people on different machines, so a shared copy would be both a leak
  and wrong on arrival.

- **Target** — what a slot names. Either an *application*, where any window of that app
  will do, or a *browser identity*, where one profile's window is the only acceptable
  answer.

- **Browser identity** — a single Chrome profile, treated as its own destination even
  though every profile on the machine runs inside one Chrome process. The reason
  application-level switching is not enough: "go to Chrome" is ambiguous across four
  windows signed into four accounts, and those accounts cannot be merged.

- **Profile directory** — Chrome's durable identifier for a profile (`Default`,
  `Profile 70`). Never changes, and means nothing to a human. What the slot table stores.

- **Profile name** — the label a profile shows in Chrome's interface, editable at any
  moment. What a human recognises, and therefore unusable as an identifier.

- **Profile signature** — the tail a Chrome window title carries to say which profile
  owns the window. Built from the profile name and the signed-in account, so it moves
  when either does, and it cannot be read backwards: two profiles can produce
  identically shaped signatures that decompose differently. A signature is something to
  predict and compare against, never to parse.

- **Reachable window** — a window on the currently active Desktop. Only reachable
  windows can be found or focused; a window one Desktop away is not slow to reach but
  absent altogether, whether it is full-screen or perfectly ordinary. This is why every
  window a slot can reach shares a single Desktop.

- **Pinning** — binding a slot to whatever the window in front of you represents: its
  browser identity if it is a browser window, otherwise its application. Instead of
  writing the slot table by hand. How the table comes into existence on a new machine,
  and the reason nobody has to look up profile directory numbers. A browser window that
  cannot be attributed to one identity is refused rather than pinned as its
  application — "the browser" is the ambiguity slots exist to remove.

- **Adoption** — a slot claiming a window it did not itself open, by recognising the
  window's signature. What keeps a slot honest when you open a window from Chrome's own
  profile menu rather than by pressing the key.

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

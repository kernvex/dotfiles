# Claude seat on the status line

Date: 2026-08-03
Status: approved, not yet implemented

> **Placeholders only.** `CONTEXT.md` records that identity routing lives in
> untracked machine-local config, "never in this public repo", and `origin` is
> `github.com/kernvex/dotfiles`. Real coworker names, addresses and seat
> directory names therefore appear nowhere in this document, the ADR, the
> glossary, the code or its comments. This file writes `<person>@<company>` and
> `<owner>@<mail>`; the real values stay in `~/.config/git/local.inc` and in the
> seat directory names on disk, both untracked.

## Problem

One macOS account, several humans, several employers. Claude Code's logged-in
account is selected by `CLAUDE_CONFIG_DIR`, an environment variable — so it is
invisible, sticky across a `cd`, and wrong in exactly the situations where being
wrong is expensive: company work billed to a personal subscription, or personal
work filed into an employer's transcripts.

Git already solved its half of this. `includeIf gitdir:` routes the commit
identity by folder, and `whereami` reports both the effective identity and
whether it is the one the folder expects. The Claude seat has no equivalent, and
nothing on screen says which account is answering.

This adds that: one segment at the head of status line two, naming the seat and
colouring it by whether it agrees with the git identity of the folder you are
standing in.

## What renders

Line two gains a leading segment. Today, and after:

```
       Opus 5 (1M context) · high  kernvex/dotfiles  main*  ☉ kernvex

◈ <owner>@<mail> · max  Opus 5 (1M context) · high  kernvex/dotfiles  main*  ☉ kernvex
```

The segment is `◈ <account email> · <tier>`. The email comes from the seat's
`oauthAccount`, the tier from the same record's `organizationType` with its
`claude_` prefix stripped (`claude_max` → `max`). If the tier is absent but the
email is not, the `· <tier>` half is dropped and the email renders alone.

The seat segment and the trailing `☉ <identity>` always carry the same colour, so
the two ends of the line either agree or both shout.

The segment is always present, including in the neutral case.

## Sources of truth

| Fact | Read from |
|---|---|
| which seat is active | `$CLAUDE_CONFIG_DIR`, defaulting to `~/.claude` |
| the seat's account and tier | `<config dir>/.claude.json` → `oauthAccount.emailAddress`, `.organizationType` |
| the folder's git identity | `whereami --json` → `identity_email` (new) |
| whether the folder is routed | `whereami --json` → `identity_routed` (new) |

Reading `oauthAccount` costs 0.7 ms, measured. The considered alternatives were a
declarative seat map in this repo — rejected, it is a *claim* that goes stale
silently and would report blue for precisely the mistake the segment exists to
catch — and `claude auth status --json`, which is authoritative including
Keychain state but pays a Node cold start, roughly a second, on a line that
redraws constantly. This trade is the subject of ADR 0007.

### Seat directory naming

The machine owner keeps the default `~/.claude`. Every other seat is a *named*
seat at `~/.claude-<first>-<last>-<company>`. First and last name together with
the company is what makes it collision-proof: two people sharing a first name is
the ordinary case, not the exotic one.

The directory name is the seat's unique identifier. It is not what renders —
the account email is — but it is the fallback when the account cannot be read,
and it is what `CLAUDE_CONFIG_DIR` is set to.

## State

Two questions decide the colour: is this folder *routed* by an `includeIf` rule,
and is the active seat the *default* one or a *named* one.

| Folder | Seat | Colour | Reads as |
|---|---|---|---|
| routed | account email matches git email | blue | verified: right seat, right company |
| routed | account email differs | red | company code on the wrong seat |
| routed | either email unreadable | yellow | cannot verify |
| unrouted | default | dim | home, nothing to check |
| unrouted | named | red | someone else's seat on your own work |
| not a repo | default | dim | no claim available |
| not a repo | named | yellow | cannot verify, and not on your own seat |

As logic:

```
in a repo, routed folder:
    both emails known  ->  verified if equal (case-folded) else mismatch
    either unknown     ->  unverifiable
in a repo, unrouted folder:
    neutral if default seat else mismatch
not in a repo:
    neutral if default seat else unverifiable
```

Three signals, three meanings, held to strictly:

- **red** — I know this is wrong.
- **yellow** — I cannot check, and you are carrying a seat that is not yours.
- **dim** — nothing to say.

Blue therefore means one thing only: a comparison ran and passed. If blue also
meant "no comparison happened" you could not tell a verified seat from an
unverified one at a glance, and the segment would not be worth reading.

Two rows deserve their reasoning recorded, because both look like overreach
until you see the accident they catch:

- **unrouted folder, named seat → red.** The mirror of the obvious mistake:
  personal work burning an employer's tokens and filing personal transcripts
  into their `projects/`. Same error, opposite direction.
- **not a repo, named seat → yellow.** Routing is defined on git directories, so
  outside a repo there is nothing to compare against — but a named seat is still
  unusual enough to mark. Yellow says "unverifiable", which is exactly true.

"Unrouted" is how "the git identity is not the personal one" gets decided
*without the personal identity's name appearing anywhere in the code*. A routed
folder is a company folder by git's own rules, so a second employer works the day
it is added, with no code change. This is ADR 0001's principle, carried forward.

## Palette

The terminal is Gruvbox Dark Hard. The script uses basic ANSI codes throughout so
the theme picks the hue, and this design keeps that — no hardcoded colour.

| Role | Code | Renders as |
|---|---|---|
| verified | bright blue `94` | `#83a598` |
| mismatch | red `31` | `#cc241d`, the same red the identity segment already uses |
| unverifiable | yellow `33` | `#d79921` |
| neutral | dim `2` | dimmed foreground |

The cost of theme purity, accepted deliberately: Gruvbox exposes no orange in its
ANSI 16, so the unverifiable state shares yellow with the dirty-tree `*` and the
pace warnings on line one. A true orange (`38;5;208`) would separate them but
would pin one colour to one theme in a script that otherwise defers to it
entirely. Distinctness lost, consistency kept.

Note also that Gruvbox's `cyan` (`36`, used today for the branch) is `#689d6a` —
green in practice. Bright blue is chosen partly so "verified" cannot be confused
with it.

## Components

### `bin/.local/bin/whereami`

Two new fields on `--json`:

- **`identity_email`** — `git config user.email`, the effective identity's
  address. The file already reports the name; this is the missing half of
  "as whom?".
- **`identity_routed`** — whether an `includeIf gitdir` rule covers this repo.

`identity_mismatch()` already computes the matched rule internally. Lift that
loop into a `_matched_include(gitdir)` helper returning the matched target or
`None`, so both callers share one parse of `git config -l --show-origin` rather
than walking it twice.

The human `whereami` block is unchanged. Its job is a quick glance and the email
only adds width.

### `claude/.claude/statusline-pace.py`

One new section, four functions:

```
seat_dir()      -> (path, is_default)   from $CLAUDE_CONFIG_DIR, default ~/.claude
seat_account()  -> (email, tier)        oauthAccount.{emailAddress, organizationType}
seat_state()    -> verified | mismatch | unverifiable | neutral
render_seat()   -> the painted "◈ email · tier" segment
```

`render_seat()`'s output is prepended to `head`, ahead of the bold model name.

### The colour collision

`render_git()` already paints `☉ <identity>` red on a *git* identity mismatch —
`includeIf` failed to fire and you are about to commit as the wrong person. This
design also wants that segment to carry the seat's colour. Two independent faults,
one colour slot.

Resolution: **git mismatch wins, then the seat colour.** Both faults are red, so
nothing is ever lost — the existing alarm keeps working and the new signal layers
underneath it.

## Failure

Every seat read is wrapped exactly as `render_sys()` and `whereami()` already are:
any `OSError` or `ValueError` yields `(None, None)` and the segment degrades
rather than taking the status line down with it.

When the account cannot be read, the display falls back to the config directory's
basename — `personal` for the default directory, the `.claude-` prefix stripped
otherwise — and the state is *unverifiable*. A broken read looks like a broken
read.

The seat email is what that config directory **last logged in as**. If someone
logs a directory into a different account this tracks it, which is the point, but
it is not Keychain truth. `claude auth status` is, and it is a second away rather
than 0.7 ms away.

## Gating assumption

The design rests on one unverified fact: **Claude Code spawns the status line
with the session's `CLAUDE_CONFIG_DIR` in its environment.** It is very likely —
the status line is a child of the same process the `Bash` tool is a child of, and
that one carries the full session environment — but if it is false the seat is
unreadable and nothing else here matters.

Proving it is step 1 of implementation, before anything else is written.

## Verification

The repo has no test framework. This adds its first test, a harness over every
row of the state table.

- **Seats are synthetic** — temp directories holding a hand-written
  `.claude.json` with just an `oauthAccount` block. No real login is touched, so
  the test does not depend on any seat having been provisioned.
- **Folders are real, entered read-only** — a routed repo, an unrouted repo, and
  a directory that is not a repo.
- Three folders crossed with two seat kinds gives six combinations; a seventh
  case, a routed folder whose seat has no readable account, covers the
  *unverifiable* branch that the cross does not reach. Each gets a fixture
  payload piped to `statusline-pace.py`; the assertion is the ANSI code on the
  seat segment.

Real accounts, real addresses and real folder names stay out of it: the routed
folder is discovered by asking git for its own `includeIf` rules, not by naming
one.

## Documents

- **`CONTEXT.md`** — glossary entries in the existing *Identity terms* block:
  *seat*, *default seat*, *named seat*, *seat account*, *seat mismatch*.
  Definitions only; it is a glossary.
- **`docs/adr/0007-the-status-line-reads-the-seat-from-its-config-dir.md`** — reading `oauthAccount` from the config directory rather
  than asking `claude auth status`. Surprising without context (it is not
  Keychain truth), chosen against a real alternative, and precisely what a future
  reader would "fix" by shelling out to `claude`, discovering the one-second cost
  only afterwards.

## Out of scope

- **Switching seats.** This design only *reports*. The `--on-variable PWD` fish
  handler, the `SessionStart` and `UserPromptSubmit` hooks, and `job-doc doctor`
  are separate work and depend on the undocumented
  `CLAUDE_SECURESTORAGE_CONFIG_DIR`.
- **Keychain state.** Out of reach at 0.7 ms; `claude auth status` is the tool
  for it, in `doctor`, not here.
- **Non-repo directories under a work root.** Routing is defined on git
  directories. Matching a bare cwd against the `includeIf` conditions would
  extend the check, but nothing needs it yet.

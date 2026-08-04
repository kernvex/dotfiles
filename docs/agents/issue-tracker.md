# Issue tracker: Local Markdown

Issues and specs (you may know a spec as a PRD) for this repo live as markdown
files, split by durability: **specs are committed, issues are not.**

| Artifact | Path | Tracked? |
| --- | --- | --- |
| Spec | `docs/superpowers/specs/YYYY-MM-DD-<topic>-<kind>.md` | yes |
| Issue | `.scratch/<feature-slug>/issues/<NN>-<slug>.md` | no |
| Wayfinder map | `.scratch/<effort>/map.md` | no |

`<kind>` is `design` or `spec`. Both genres live under one path so that
`superpowers:brainstorming`, whose location is hardcoded, and `/to-spec`, whose
location is this file, write to the same place without either being bent out of
shape.

## Conventions

- One feature per directory under `.scratch/`: `.scratch/<feature-slug>/`
- Implementation issues are one file per ticket at `.scratch/<feature-slug>/issues/<NN>-<slug>.md`, numbered from `01` — never a single combined tickets file
- Triage state is recorded as a `Status:` line near the top of each spec and issue file (see `triage-labels.md` for the role strings)
- Comments and conversation history append to the bottom of the file under a `## Comments` heading

## Why specs are committed and issues are not

A spec is the durable half: it justifies the `docs/adr/` entries beside it and
it is read long after the work lands. Issues are the disposable half — claimed,
resolved, and of no interest a week later.

This matters mechanically, not just aesthetically: `.scratch/` is in
`.gitignore`. Publishing a spec there would silently untrack it. Any skill whose
default is `.scratch/<feature-slug>/spec.md` should read that as
`docs/superpowers/specs/` instead.

## When a skill says "publish to the issue tracker"

A spec goes to `docs/superpowers/specs/`, dated and committed. Anything else
goes in a new file under `.scratch/<feature-slug>/`, creating the directory if
needed.

## When a skill says "fetch the relevant ticket"

Read the file at the referenced path. The user will normally pass the path or the issue number directly.

## Why not GitHub Issues

The remote has Issues enabled, so the skills' usual default would reach for
them. Two reasons this repo doesn't:

- The working habit is already files under `docs/` — ADRs, notes, specs. Issues
  would be a second, emptier home for the same thing.
- The repo is public. Work here regularly touches employer and coworker
  identity, which `CONTEXT.md` keeps out of the repo entirely; a tracker that is
  world-readable by default makes that a thing you must remember every time.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a file with one **child** file per ticket.

- **Map**: `.scratch/<effort>/map.md` — the Notes / Decisions-so-far / Fog body. Untracked, like every other `.scratch/` artifact.
- **Child ticket**: `.scratch/<effort>/issues/NN-<slug>.md`, numbered from `01`, with the question in the body. A `Type:` line records the ticket type (`research`/`prototype`/`grilling`/`task`); a `Status:` line records `claimed`/`resolved`.
- **Blocking**: a `Blocked by: NN, NN` line near the top. A ticket is unblocked when every file it lists is `resolved`.
- **Frontier**: scan `.scratch/<effort>/issues/` for files that are open, unblocked, and unclaimed; first by number wins.
- **Claim**: set `Status: claimed` and save before any work.
- **Resolve**: append the answer under an `## Answer` heading, set `Status: resolved`, then append a context pointer (gist + link) to the map's Decisions-so-far in `map.md`.

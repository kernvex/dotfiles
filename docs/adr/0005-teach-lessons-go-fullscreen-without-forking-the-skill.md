# Lessons go fullscreen without touching the upstream skill

Every `teach` lesson and reference doc should toggle fullscreen on `f`. The obvious
place to say so is the skill itself — and that is the one place it cannot go.
`skills/productivity/teach/` is a fork tracking `mattpocock/skills`, so a paragraph
added to `SKILL.md` becomes a permanent conflict on every upstream pull, for a
preference upstream has no reason to ever adopt. The behaviour has to reach 59 pages
across 14 workspaces without a byte of the skill changing.

The skill already has the seams for this, which is the thing worth noticing before
reaching for machinery. It reads `./assets/` before authoring a lesson and treats
reuse as the default; it reads `NOTES.md` specifically to recover preferences about
how the user wants to be taught. Those are extension points by design, not holes.

**Decision:** ship the behaviour as a component (`assets/fullscreen.js`) declared as
a preference (a line in each workspace's `NOTES.md`), with a short rule in the global
`~/.claude/CLAUDE.md` that seeds both into any workspace that lacks them. The
canonical copy lives at `claude/.claude/templates/teach/fullscreen.js` and is stowed;
`bin/.local/bin/teach-fullscreen` installs it and links it from every
`lessons/*.html` and `reference/*.html`.

The rejected alternative was a `PostToolUse` hook rewriting lesson HTML after each
write. It is the only option that cannot be forgotten, and it pays for that by
regex-editing documents on every write in every project, to enforce a rule that
matters in one directory tree. A global-rule-only version was rejected from the other
side: it costs context in every unrelated session and does nothing for the 53 pages
that already existed.

**Consequence:** the rule is stated in three places at once, which is redundancy with
a purpose — the global rule seeds new workspaces, the `NOTES.md` line survives without
the global rule in context, and the script repairs both. Redundancy is also drift, so
the template is the single source of truth and `teach-fullscreen` is idempotent: it
rewrites nothing already current, and re-running it after editing the template
propagates the change everywhere. Evidence it works: `ipkvm` was created a day after
rollout and its five lessons carried a byte-identical component with no intervention.

## The component scales by zoom, not font-size

The natural way to enlarge type in fullscreen is to override the root font-size, and
it does not survive contact with these workspaces. They size text inconsistently —
`tmux` pins `body { font-size: 19px }` with `rem` children, `sar` pins
`html { font-size: 18px }` with the same — and the stylesheets are not even named
alike (`style.css`, `lesson.css`, `course.css`, `theme.css`, `deck.css`). A root
`font-size` rule scales `sar` correctly and leaves `tmux`'s body text untouched while
enlarging its headings, which is worse than doing nothing.

**Decision:** `html:fullscreen { zoom: 1.15 }`, and ship the styles inside the script
as an injected `<style>` rather than a CSS file. Zoom scales px, rem and em alike, so
it is indifferent to how a workspace sizes anything; a self-injecting style means one
`<script>` tag is the entire integration and no filename can collide.

**Consequence:** fullscreening `<html>` paints an unstyled backdrop behind the body's
own background, which is black in most browsers — every workspace would letterbox its
cream or pink page in black margins. The component reads the body's computed
background at toggle time and copies it onto the root, so the backdrop matches
whatever theme that workspace happens to use instead of a colour hardcoded here.

## `f` is a letter, and some pages already own it

Two hazards follow from binding a bare letter. The quiz and drill widgets across these
workspaces read from text inputs, and `Cmd-F` is the browser's find — so the handler
ignores the key inside inputs, textareas, selects and contenteditable, and whenever a
modifier is held. And `IC_Panel_Call/assets/deck.js` already binds `f` to
`requestFullscreen`: a second handler would enter fullscreen and leave it again on one
keypress.

**Decision:** the script resolves each page's `<script src>` references and skips any
page whose scripts — or whose own inline code — already call `requestFullscreen`,
reporting them for a manual look rather than guessing. The component additionally
guards on `window.__teachFullscreen`, so a double inclusion is inert.

**Consequence:** the deck was never actually at risk, because `deck/slides.html` sits
outside `lessons/` and `reference/` and was out of scope regardless. The detector is
kept anyway, and tested against both an external-script and an inline-script case,
because the failure it prevents is silent — a key that appears to do nothing.

**Consequence:** 12 of the 13 retrofitted workspaces are not under git, so a mass edit
of 49 files has no undo. The script therefore prints a plan and does nothing until
given `--apply`. That default is worth keeping even now that the rollout is done,
since its remaining job is drift repair on the same unversioned files.

# Persian HTML ships its own font

Generated HTML that contains Persian keeps arriving in whatever font the page
happened to specify, and the default for generated markup is a Latin face — Roboto
being the usual one, which has no Arabic coverage at all. The text does not fail
loudly. It falls back to whatever the system offers for that script, so the page
renders, badly, and the only symptom is that the Persian looks wrong beside the
English.

Three ways of fixing that had already grown here without anyone choosing between
them. `sar` self-hosts Vazirmatn as `.woff2` under `assets/fonts/`. `vincent`
`@import`s the same font from the Google Fonts CDN. `phonetic` names it in a stack
and relies on it being installed. All three render identically on this machine
today, because Vazirmatn v33.003 is installed system-wide and the CDN is reachable,
which is precisely why the drift went unnoticed for months.

**Decision:** self-host. Any HTML containing Arabic-script text declares
`"Vazirmatn", "Geeza Pro", system-ui, sans-serif` and ships `vazirmatn-400.woff2`
(plus `-700` where bold is used) beside itself, bound by `@font-face`. Vazirmatn is
the font; the rest of the stack is fallback, in descending order of how much is
known about what will be there. The name matters: *Vazir* is discontinued,
*Vazirmatn* is its maintained successor, and only the latter is installed here.

The CDN import was rejected because these pages are archival by intent — the whole
premise of a reference doc is that it is read years later — and an `@import` makes
correct rendering contingent on a network and a third party's URL scheme forever
after. The name-only stack was rejected for the same reason one step removed: it is
correct on the machine that made it and nowhere else. Neither is a live bug today;
both are documents that quietly stop being right at a time nobody will connect to a
decision made now.

**Consequence:** roughly 42K of font per workspace, which is the honest price and a
cheap one. The bundled files are subsets — 366 glyphs, 142 of the Arabic block's
256 — verified to cover Persian's distinct letters (farsi yeh, keheh, gaf, peh,
tcheh, jeh), the Arabic forms, combining hamza, ZWNJ, and both digit sets. What they
do not cover is the Urdu, Pashto and Sindhi extensions. The rule is deliberately
written against the *script* rather than the language, since language is not
reliably detectable from generated markup, so Urdu is inside the rule's scope but
outside the shipped font's coverage. That is a known soft spot, not an oversight;
the day Urdu is actually written here it needs a Nastaliq face and its own carve-out.

**Consequence:** the trigger is the script present in the file, not the directory it
sits in. `Documents/Projects/sar/sar-offline` is the reason — a standalone copy of
the `sar` lessons, Persian throughout, living outside `~/Documents/Learning`. Any
rule keyed to teaching workspaces would have skipped it while looking correct. This
is a deliberate departure from ADR 0005, where the fullscreen key *is* scoped to
teaching workspaces: reading ergonomics are a property of the kind of document, but
rendering the script correctly is a property of the text itself.

**Consequence:** this repo now says two opposite things about Vazirmatn, and both are
right. `wezterm/.config/wezterm/wezterm.lua` deliberately ranks DejaVu Sans Mono
*above* Vazirmatn for Persian, because a terminal gives every character one cell and
Vazirmatn is proportional — its advances run 3 to 11.25 against a 9px cell, so the
joins in a cursive script come apart. That constraint does not exist in HTML, where
proportional is simply correct. The rule is therefore scoped to HTML in the wording,
not merely by convention: the deciding factor is the medium's advance model, so
neither choice generalises to the other.

## Reversing this

The rule lives in `claude/.claude/CLAUDE.md` under *Arabic-script text in HTML*.
Deleting that section stops it applying to anything written afterwards, and nothing
else depends on it — no script enforces it and no build step reads it.

Existing pages are unaffected by that deletion, since the font is bound in each
workspace's own stylesheet. To unwind a workspace as well, drop its `@font-face`
blocks and `assets/fonts/*.woff2`, and leave the `font-family` stack in place: with
Vazirmatn installed system-wide the page keeps rendering correctly here, which
returns it to exactly the `phonetic` arrangement this ADR argued against. That is
the reversal's real cost — it looks like nothing broke.

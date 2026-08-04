# whereami derives the "expected" git identity from git's own config, never a hardcoded rule

`whereami` colors the active commit identity red when it mismatches what a
directory *should* commit as. Computing "should" needs a folder→identity map —
but this machine deliberately keeps company identity — the client folder path,
the company name and email — out of the public dotfiles repo, routed instead
through a machine-local `~/.config/git/local.inc` → `<company>.inc` `includeIf`
chain (see `git-ssh-identities`). `whereami` lives in the public `bin/` package.

That constraint applies to this document too. An ADR explaining why a client
relationship is kept out of a public repo is a poor place to name one, and this
one did for months.

**Decision:** derive the expected identity by enumerating git's own `includeIf
gitdir` rules at runtime (`git config -l --show-origin` surfaces each rule as a
literal `includeif.gitdir:<cond>.path` key even when its condition doesn't match,
and `git config --file <target> user.name` reads the routed name), rather than
baking any path or identity into the script. The public script stays fully
generic; new identities added to `local.inc` work with no code change; and no
company detail ever lands in the public repo.

**Consequence:** the check must fail *safe* — whenever expected identity can't be
determined confidently (unparseable rule, unusual `gitdir` glob form, missing
target file), `whereami` reports no mismatch rather than a false red alarm.

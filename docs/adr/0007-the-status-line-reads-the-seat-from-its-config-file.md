# The status line reads the Claude seat from its config file, not from `claude auth status`

The status line names the Claude seat answering a session and colours it by
whether that account agrees with the folder's git identity. Getting the account
needs a source, and there are two.

`claude auth status --json` is the authoritative one: non-interactive, reports
`email` / `orgId` / `orgName` without printing a secret, and — unlike anything on
disk — reflects **Keychain** state, which is where the credential actually lives.
It costs a Node cold start, roughly a second.

**Decision:** read `oauthAccount.emailAddress` and `.organizationType` from the
seat's own config file instead. It costs 0.7 ms, measured, which is what a line
redrawn on every render can afford. `claude auth status` belongs in a `doctor`
command run on demand, where a second is free.

A third option — a declarative seat map committed to this repo — was rejected
outright. It is a *claim* rather than an observation, so it would keep reporting
"verified" after someone logged a directory into a different account, which is
exactly the mistake the segment exists to catch. A stale green light is worse
than no light.

**Consequence — the file is not where you would guess.** Verified against Claude
Code 2.1.221 by pointing `CLAUDE_CONFIG_DIR` at an empty directory and watching
what appeared in it:

```
CLAUDE_CONFIG_DIR set    ->  $CLAUDE_CONFIG_DIR/.claude.json
CLAUDE_CONFIG_DIR unset  ->  ~/.claude.json   (a SIBLING of ~/.claude)
```

The path is keyed to whether the variable is *set*; whether a seat counts as the
machine owner's is keyed to where it *points*. Reading `<config dir>/.claude.json`
unconditionally finds nothing for the owner and silently renders the fallback
label — the right colour beside the wrong text, which no colour assertion
catches. `test-statusline-seat.py` asserts the label for this reason.

**Consequence — this is not Keychain truth.** It is what that config directory
last logged in as. It tracks a re-login, which is the point, but a credential
revoked or expired in the Keychain still reads as a healthy account here. The
segment answers "which account is configured", not "will it authenticate".

**Consequence — undocumented surface.** `oauthAccount` is internal to Claude
Code's config file and carries no compatibility promise. If a future version
moves or renames it, every read here returns `(None, None)` and the segment
degrades to the directory-name fallback in yellow, which is the designed failure
mode rather than a broken status line.

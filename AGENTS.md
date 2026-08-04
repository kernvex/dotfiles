# AGENTS.md

Instructions for coding agents working in this repository.

This is a personal dotfiles repo, stowed into `$HOME`. It is **public**: real
employer names, coworker names and addresses belong in no committed file. See
`CONTEXT.md` for the vocabulary and `docs/adr/` for the decisions.

## Agent skills

### Issue tracker

Markdown files, split by durability: specs are committed to
`docs/superpowers/specs/`, issues are untracked under `.scratch/<feature-slug>/`.
Publishing a spec to `.scratch/` would silently untrack it. See
`docs/agents/issue-tracker.md`.

### Triage labels

The five canonical roles, each label string equal to its name, recorded as a
`Status:` line in each issue file. See `docs/agents/triage-labels.md`.

### Domain docs

Glossary at `CONTEXT.md`, decisions in `docs/adr/`. See `docs/agents/domain.md`.

# Maintainer Notes

## Source of Truth

This repository is the public-source working tree. New work should happen here:

```text
gradigit/LiquidBar
```

Older local working folders may contain useful background, but they are private
archives. Do not merge them wholesale and do not copy generated notes, chat
exports, prompt files, local status files, or machine-specific paths into this
repository.

## Bringing Forward Prior Knowledge

When older notes contain useful conclusions:

1. Re-check the current source tree.
2. Rewrite the conclusion as a small, current document.
3. Keep only details that help future maintainers build, test, debug, or
   operate the current code.
4. Remove local paths, historical prompt text, private workflow state, and
   comparisons that are not necessary for maintaining LiquidBar.

## Documentation Layout

- `README.md`: project overview and quick commands.
- `CONTRIBUTING.md`: contribution workflow.
- `SECURITY.md`: security reporting and permission-sensitive change guidance.
- `docs/START_HERE.md`: public-safe fresh-session onboarding packet.
- `docs/ARCHITECTURE.md`: source map and runtime flow.
- `docs/DEVELOPMENT.md`: local setup and common commands.
- `docs/TESTING.md`: test commands, UI testing, visual regression, artifacts.
- `docs/PERFORMANCE.md`: local benchmark capture, A/B comparison, and perf
  ledger workflow.
- `docs/research/`: future public research notes, if needed.

If a document references a script, asset, or source file, keep that referenced
file in the same commit or remove the reference. Public docs should describe the
state of the repository, not a private local worktree.

## Release Hygiene

- Keep the canonical release namespace as `gradigit/LiquidBar` unless ownership
  is intentionally changed.
- Keep CI actions pinned to reviewed commit SHAs.
- Do not publish unsigned or unnotarized binaries as official releases.
- Keep generated scan reports and local build artifacts out of git; summarize
  durable conclusions in tracked docs instead.

## Public Research Notes

Research files are welcome when they are current, source-bounded, and useful.
Each research note should include:

- date
- scope
- sources or commands used
- conclusions
- open risks

Avoid broad transcripts. Prefer concise findings that can be reviewed and kept
up to date.

# Start Here

This is the public-safe onboarding packet for a fresh LiquidBar work session.
Read this before changing code.

## Current Status

- Repository: `gradigit/LiquidBar`
- Primary branch: `main`
- License: MIT
- CI: GitHub Actions runs `swift test -c debug` on `macos-26`
- Package: SwiftPM executable target `LiquidBar` plus test target
  `LiquidBarTests`
- Current release line: `v1.0.1`
- Runtime baseline: native AppKit panels with retained AppKit/Core Animation
  rendering, not a permanent full-surface GPU render loop
- Release trust: official update checks and release links are scoped to
  `gradigit/LiquidBar`

## First Read Order

1. `README.md`
2. `CONTRIBUTING.md`
3. `SECURITY.md`
4. `docs/ARCHITECTURE.md`
5. `docs/DEVELOPMENT.md`
6. `docs/TESTING.md`
7. `docs/PERFORMANCE.md` for performance-sensitive work
8. `docs/RELEASE.md` for release or packaging work
9. `docs/MAINTAINER_NOTES.md`
10. The source files directly related to the requested change

Do not start implementation until you understand the requested scope, current
git status, and relevant tests.

## Fresh Session Prompt

Use this prompt when starting a new coding session in this repository:

```text
Work only in the LiquidBar repository currently open in this session.

First read:
- README.md
- CONTRIBUTING.md
- SECURITY.md
- docs/START_HERE.md
- docs/ARCHITECTURE.md
- docs/DEVELOPMENT.md
- docs/TESTING.md
- docs/PERFORMANCE.md if performance-sensitive work is in scope
- docs/RELEASE.md if release or packaging work is in scope
- docs/MAINTAINER_NOTES.md

Treat older local LiquidBar folders as private archives. Do not read, copy, or
import from them unless explicitly asked. If older knowledge is needed, re-check
the current source and rewrite conclusions as clean, current documentation.

Before editing, run:
- git status --short --branch

For source changes, validate with:
- swift test -c debug

For release-oriented local validation, use:
- ./scripts/run_all_tests.sh

Keep changes focused, public-safe, and free of local paths, generated logs, raw
session transcripts, prompt text, and private workflow state.
```

## Migration Context

This repository was prepared as the clean source of truth after a private
rewrite and migration. The old working history is intentionally not part of this
repository.

What was brought forward:

- current source code
- current tests
- build/test scripts needed for development
- public-safe architecture, development, testing, contribution, and security
  docs
- CI, MIT license, Dependabot, and hardened ignore rules
- release trust hardening for the canonical GitHub namespace

What was intentionally left out:

- raw session logs and transcripts
- generated status files and local handoff bundles
- machine-specific paths
- private worktree state
- unreviewed historical research notes
- old local planning artifacts

## Working Rules

- Use this repository as the source of truth.
- Prefer small branches and focused commits.
- Keep user config isolated with `LIQUIDBAR_CONFIG_DIR` during tests.
- Run UI automation only when the requested work needs it.
- Do not make destructive git or filesystem changes without explicit approval.
- Do not weaken tests or ignore rules to make a change pass.

## Validation Baseline

Before broad changes, run:

```sh
swift test -c debug
```

For UI or windowing work, also read `docs/TESTING.md` and use the scripted UI
test path:

```sh
./scripts/run_ui_tests.sh
```

For release-oriented work, run:

```sh
./scripts/run_all_tests.sh
```

For performance-sensitive work, use the baseline/candidate workflow in
`docs/PERFORMANCE.md`.

## Where To Add Future Context

- Stable architecture or subsystem knowledge: `docs/ARCHITECTURE.md`
- Development workflow changes: `docs/DEVELOPMENT.md`
- Test/runbook changes: `docs/TESTING.md`
- Performance benchmark workflow changes: `docs/PERFORMANCE.md`
- Release packaging, signing, and notarization changes: `docs/RELEASE.md`
- Permission or release trust changes: `SECURITY.md`
- Maintainer policy or migration rules: `docs/MAINTAINER_NOTES.md`
- Public research notes: `docs/research/`

Do not add raw logs or session transcripts. Convert them into concise,
source-grounded notes first.

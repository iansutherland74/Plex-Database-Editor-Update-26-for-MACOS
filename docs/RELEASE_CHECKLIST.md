# Release Checklist

## Scope
- Use this checklist before creating a release/tag.
- Goal: produce repeatable evidence that build/tests/smoke checks passed.

## Pre-Release Steps
1. Confirm branch and sync latest changes.
2. Run release prep script.
3. Review generated report and ensure no failures.
4. Review generated release notes draft and adjust if needed.
5. Run optional live smoke checks if targeting a local Plex environment.
6. Confirm working tree is clean.
7. Create release notes/tag.

## Commands

Run Stage 3 workflow tests directly:

```bash
cd /Users/sutherland/repo
./run_stage3_tests.sh
```

Run Stage 4 release-tag tests directly:

```bash
cd /Users/sutherland/repo
./run_stage4_tests.sh
```

Run Stage 5 tooling contract tests directly:

```bash
cd /Users/sutherland/repo
./run_stage5_tests.sh
```

Run Stage 6 release automation regression tests directly:

```bash
cd /Users/sutherland/repo
./run_stage6_tests.sh
```

Run Stage 7 CI/release workflow contract tests directly:

```bash
cd /Users/sutherland/repo
./run_stage7_tests.sh
```

Run full release prep (includes build):

```bash
cd /Users/sutherland/repo
./run_release_prep.sh
```

Equivalent shortcut:

```bash
cd /Users/sutherland/repo
make release-prep
```

Skip build (when already built in current session):

```bash
cd /Users/sutherland/repo
./run_release_prep.sh --skip-build
```

Equivalent shortcut:

```bash
cd /Users/sutherland/repo
make release-prep-fast
```

Include live read-only smoke:

```bash
cd /Users/sutherland/repo
./run_release_prep.sh --skip-build --include-live-smoke
```

Include live non-destructive write checks:

```bash
cd /Users/sutherland/repo
./run_release_prep.sh --skip-build --include-live-write
```

Generate draft release notes:

```bash
cd /Users/sutherland/repo
./run_release_prep.sh --skip-build --notes-from-tag v1.0.0 --notes-to-ref HEAD
```

Optional helper to prepare and create/push a release tag:

```bash
cd /Users/sutherland/repo
./create_release_tag.sh --version v1.0.1
# then: ./create_release_tag.sh --version v1.0.1 --apply --push
```

## Outputs
- Report file: `docs/release_prep_report_<timestamp>.md`
- Notes file: `docs/release_notes_<timestamp>.md` (unless `--notes-output` is used)
- Report includes:
  - quality gate output
  - release notes generation output
  - git status snapshot
  - recent commits
- Generated default output files are ignored by git via `.gitignore` patterns.

## Notes
- Live smoke checks require Plex token availability (`PLEX_TOKEN` or local defaults).
- `run_live_plex_smoke.sh` never triggers empty-trash actions.
- Remaining interactive UI-only checks are tracked in `docs/STAGE1_STABILIZATION_REPORT.md`.
- Optional hosted path: run GitHub Actions workflow `Release Prep` (manual dispatch) to generate `release-prep-report` and `release-notes-draft` artifacts.

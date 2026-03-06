# Release Checklist

## Scope
- Use this checklist before creating a release/tag.
- Goal: produce repeatable evidence that build/tests/smoke checks passed.

## Pre-Release Steps
1. Confirm branch and sync latest changes.
2. Run release prep script.
3. Review generated report and ensure no failures.
4. Run optional live smoke checks if targeting a local Plex environment.
5. Confirm working tree is clean.
6. Create release notes/tag.

## Commands

Run full release prep (includes build):

```bash
cd /Users/sutherland/repo
./run_release_prep.sh
```

Skip build (when already built in current session):

```bash
cd /Users/sutherland/repo
./run_release_prep.sh --skip-build
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

## Outputs
- Report file: `docs/release_prep_report_<timestamp>.md`
- Report includes:
  - quality gate output
  - git status snapshot
  - recent commits

## Notes
- Live smoke checks require Plex token availability (`PLEX_TOKEN` or local defaults).
- `run_live_plex_smoke.sh` never triggers empty-trash actions.
- Remaining interactive UI-only checks are tracked in `docs/STAGE1_STABILIZATION_REPORT.md`.

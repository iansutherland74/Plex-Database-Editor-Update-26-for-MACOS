# Release Operator Guide

This guide is the shortest safe path to prepare and publish a release from this repository.

## 1) Preconditions

- Work from `main` with latest remote changes.
- Ensure working tree is clean (`git status --short` should be empty).
- Run the quality gate at least once on your candidate commit.

## 2) Fast Validation Commands

```bash
cd /Users/sutherland/repo
./run_quality_gate.sh --skip-build
./run_quality_gate.sh --skip-build --quiet
```

Use `--quiet` in CI-style runs where you want concise logs and failure-only detail.

## 3) Release Prep

Generate report + notes draft:

```bash
cd /Users/sutherland/repo
./run_release_prep.sh --skip-build
```

Low-noise mode:

```bash
./run_release_prep.sh --skip-build --quiet
```

Default outputs:

- Report: `docs/release_prep_report_<timestamp>.md`
- Notes: `docs/release_notes_<timestamp>.md`

## 4) RC Tag Flow

Dry-run (recommended first):

```bash
cd /Users/sutherland/repo
./create_release_tag.sh --version vX.Y.Z-rcN --quiet
```

Create local tag:

```bash
./create_release_tag.sh --version vX.Y.Z-rcN --apply
```

Create and push tag:

```bash
./create_release_tag.sh --version vX.Y.Z-rcN --apply --push
```

## 5) Stable Tag Flow

Dry-run first:

```bash
cd /Users/sutherland/repo
./create_release_tag.sh --version vX.Y.Z --quiet
```

Create and push:

```bash
./create_release_tag.sh --version vX.Y.Z --apply --push
```

## 6) Stage Runner Quiet Mode

All stage wrappers support `--quiet`:

```bash
./run_stage6_tests.sh --quiet
./run_stage11_tests.sh --quiet
```

Behavior:

- Success path: concise start/finish wrapper output.
- Failure path: full captured command output is printed before exit.

## 7) If You Need to Roll Back a Tag

Delete local + remote tag:

```bash
git tag -d vX.Y.Z
git push origin :refs/tags/vX.Y.Z
```

## 8) Publish GitHub Release Object

If CLI auth is unavailable, publish via the GitHub web release page after tag push.

## 9) Related Documents

- Checklist: `docs/RELEASE_CHECKLIST.md`
- CI contracts and stage commands: `README.md`

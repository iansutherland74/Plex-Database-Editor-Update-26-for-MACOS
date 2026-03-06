# Plex Database Editor Update 26 for macOS

Native macOS app for editing Plex TV metadata and artwork, with TMDB-assisted remap tools.

## What This App Does

- Browse Plex TV shows, seasons, and episodes from the Plex SQLite database
- Manually edit episode title, season, and episode number
- Apply TMDB metadata in bulk (title, date, summary, year)
- Run Smart Season thumbnail remap that keeps the same S/E numbers
- Update episode and season artwork fields (`thumb`, `art`, `banner`, `square art`)
- Preview a Plex-style pre-play panel before/after artwork updates
- Create automatic DB backups before write operations

## Repository Layout

- `PlexTVEditor/`: SwiftUI app source
- `build_swift_app.sh`: Builds and installs the Swift app to `/Applications/Plex TV Editor.app`
- `PlexTVEditor.xcworkspace/`: Workspace metadata
- `README_MACOS_APP.md`: Older macOS notes
- `plex_gui.py`, `plex_tv_editor.py`: Legacy Python tooling kept for reference

## Requirements

- macOS
- Xcode Command Line Tools (`xcode-select --install`)
- Plex Media Server installed locally
- Access to Plex DB file:
  - `~/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db`
- TMDB API key

## Build and Run

```bash
cd /Users/sutherland/repo
chmod +x build_swift_app.sh
./build_swift_app.sh
open /Applications/Plex\ TV\ Editor.app
```

## Run Dry-Run Tests

```bash
cd /Users/sutherland/repo
./run_dry_run_tests.sh
```

## Run Stage 2 Reliability Tests

```bash
cd /Users/sutherland/repo
./run_stage2_tests.sh
```

## Run Full Quality Gate

Run the full local validation gate (build + tests + script checks):

```bash
cd /Users/sutherland/repo
./run_quality_gate.sh
```

Common variants:

```bash
# Skip build when build was already run
./run_quality_gate.sh --skip-build

# Include live Plex endpoint checks
./run_quality_gate.sh --include-live-smoke

# Include live non-destructive write queue checks
./run_quality_gate.sh --include-live-write
```

## Run Live Plex Smoke Tests

Read-only endpoint checks:

```bash
cd /Users/sutherland/repo
./run_live_plex_smoke.sh
```

Include non-destructive queue checks (`refresh`/`analyze`):

```bash
cd /Users/sutherland/repo
./run_live_plex_smoke.sh --include-write
```

Use explicit server/token if needed:

```bash
PLEX_SERVER_URL="http://127.0.0.1:32400" PLEX_TOKEN="<token>" ./run_live_plex_smoke.sh
```

## Run Release Prep

Generate a release-prep report with quality gate evidence:

```bash
cd /Users/sutherland/repo
./run_release_prep.sh
```

Useful variants:

```bash
# Skip build if already built in this session
./run_release_prep.sh --skip-build

# Include live read-only smoke checks
./run_release_prep.sh --skip-build --include-live-smoke

# Include live non-destructive write checks
./run_release_prep.sh --skip-build --include-live-write
```

Release checklist reference: `docs/RELEASE_CHECKLIST.md`

## First Launch Setup

In the app Settings tab, verify:

- TMDB API key
- Plex SQLite path (macOS default):
  - `/Applications/Plex Media Server.app/Contents/MacOS/Plex SQLite`
- Plex DB path
- Plex Server URL (default: `http://127.0.0.1:32400`)
- Plex Token

Use `Test Plex API` in Settings to validate server connectivity and view server identity details.

## Safety Notes

- Stop Plex scans/playback when doing heavy remaps
- Keep backups before large edits (the app also creates automatic backups)
- Validate a small sample first when changing numbering rules

## Development Notes

- Main UI: `PlexTVEditor/ContentView.swift`
- Orchestration + TMDB logic: `PlexTVEditor/PlexTVEditorViewModel.swift`
- Plex SQL read/write layer: `PlexTVEditor/PlexDatabaseManager.swift`

## CI Checks

GitHub Actions workflow `macOS Swift Build` runs on pushes/PRs to `main` and validates:

- Swift source compile for the app target files
- `./run_dry_run_tests.sh`
- `./run_stage2_tests.sh`
- Shell script syntax checks
- `./run_live_plex_smoke.sh --help` sanity check

## Known Build Warnings

Current builds may show Swift `Sendable` capture warnings in `PlexTVEditorViewModel.swift`. They are non-blocking and do not stop app compilation.

## Contributing

See `CONTRIBUTING.md`.

## Credits

- Original project foundation and early tooling: `VirtualD` (Jean Ransier)
- macOS Swift app updates and ongoing maintenance: `Ian Loveshack`
- Upstream/original repository lineage: `https://github.com/ransierJ/Plex-Recently-Added-movies-editor`

See `CREDITS.md` for attribution details.

## License

MIT License. See `LICENSE`.

# Contributing

## Setup

1. Install Xcode Command Line Tools:
   - `xcode-select --install`
2. Build locally:
   - `./build_swift_app.sh`
3. Launch app:
   - `open /Applications/Plex\ TV\ Editor.app`

## Coding Guidelines

- Keep write operations transactional in `PlexDatabaseManager.swift`
- Add short comments above non-obvious remap logic
- Prefer explicit status messages for user-visible operations
- Keep UI behavior consistent with Plex-style visual language

## Pull Request Checklist

- Build succeeds locally via `./build_swift_app.sh`
- No new hard-coded secrets
- Backup/DB safety behavior remains intact
- Updated docs when adding or changing major workflows

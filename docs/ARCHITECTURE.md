# Architecture Overview

## High-Level Flow

1. UI actions in `PlexTVEditor/ContentView.swift`
2. Operation orchestration in `PlexTVEditor/PlexTVEditorViewModel.swift`
3. Plex DB reads/writes in `PlexTVEditor/PlexDatabaseManager.swift`
4. TMDB network calls in `PlexTVEditor/TMDBClient.swift`

## Main Workflows

### Smart Thumb Season

- Entry: `smartRemapCurrentSeasonThumbnailsFromTMDB(...)`
- Keeps current Plex season/episode numbers
- Fetches TMDB season payload for matching season
- Updates episode artwork and season poster fields

### TV Metadata Remap

- Entry: `remapEpisodesFromTMDB(...)`
- Supports start point (season/episode) and rolling cursor mapping
- Can create missing Plex seasons when needed
- Applies title/date/summary/year/artwork based on options

### Manual Episode Edit

- Entry: `updateEpisodeTitleAndNumber(...)`
- Updates title + numbering in one DB transaction
- Runs best-effort artwork sync after successful remap

## Database Strategy

- Reads done via `sqlite3_*` APIs for lightweight fetches
- Writes done via Plex SQLite binary for compatibility and parity with Plex schema behavior
- Each write updates timestamps to trigger Plex metadata refresh behavior
- Backup helper stores timestamped copies in `~/.plex_tv_editor_backups`

## UI Notes

- Episode panel preview is responsive and resizes hero media based on available space
- Action buttons use a consistent Plex orange visual style

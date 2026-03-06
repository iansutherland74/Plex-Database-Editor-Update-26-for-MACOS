# Plex TV Editor with TMDB Integration

A native macOS application for editing Plex TV show metadata with integration to The Movie Database (TMDB) API.

## Features

- **TV Show Management**: Edit add dates for TV shows and episodes in your Plex library
- **TMDB Integration**: Search for shows and seasons directly from TheMovieDB.org
- **macOS Native**: Built as a proper macOS .app bundle  
- **Season Management**: Add complete seasons or manage individual episodes
- **Bulk Edits**: Apply date changes to multiple items at once
- **Automatic Backup**: Create database backups before making changes
- **Plex Service Control**: Start/stop Plex Media Server from the app

## Requirements

- macOS 10.13 or later
- Python 3.6+
- Plex Media Server installed
- TMDB API key (free at [themoviedb.org](https://www.themoviedb.org/settings/api))

## Quick Start (5 minutes)

### 1. Install the App

```bash
cd /path/to/repo
bash build_macos_app.sh
```

This will:
- Install Python dependencies (requests)
- Create the app bundle
- Generate an app icon
- Copy the app to `/Applications`
- Set up configuration file

### 2. Launch the App

**Option A: Via Spotlight**
- Press `Cmd + Space`
- Type "Plex TV Editor"
- Press Enter

**Option B: Via Finder**
- Open `/Applications`
- Double-click "Plex TV Editor.app"

**Option C: Via Terminal**
```bash
open /Applications/Plex\ TV\ Editor.app
```

### 3. Configure (First Launch Only)

On first launch, the app will check for Plex Media Server and the database file. If paths need adjusting:

1. Click **File → Settings**
2. Update paths if needed
3. Enter your TMDB API key (if not already configured)
4. Click **Save**

## Usage

### Search and Load Shows

1. Enter a show name (e.g., "Breaking Bad") in the **TMDB Search** field
2. Click **Search TMDB**
3. Select the show from the results
4. The app displays all seasons and episodes

### Edit Dates

1. **Double-click** any date in the list to edit
2. Choose a date using:
   - Text field (type custom date)
   - Quick buttons (Now, Today, Yesterday, etc.)
3. Click **SAVE CHANGES**
4. Restart Plex from the app to apply changes

### Bulk Operations

- **Load Plex Shows**: Click to see all your Plex TV shows
- **Select multiple items** and use bulk edit features
- **Create Backups**: Always create a backup before major edits

## File Structure

```
repo/
├── plex_tv_editor.py          # Main Python GUI application
├── Plex TV Editor.app/        # macOS app bundle
│   └── Contents/
│       ├── MacOS/
│       │   └── plex_tv_editor (executable wrapper)
│       ├── Resources/
│       │   └── plex_tv_editor.py
│       └── Info.plist
├── build_macos_app.sh         # Build and install script
├── create_app_icon.py         # Icon generation
└── setup_macos.py             # Setup verification
```

## Configuration File

Settings are stored in `~/.plex_tv_editor_config.json`:

```json
{
  "plex_sqlite": "/Applications/Plex Media Server.app/Contents/Resources/Support/Plex SQLite",
  "db_path": "~/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db",
  "date_format": "%Y-%m-%d %H:%M:%S",
  "tmdb_api_key": "your_api_key_here"
}
```

To reset to defaults, delete this file and restart the app.

## TMDB API Key

Get your free API key:
1. Go to [themoviedb.org/settings/api](https://www.themoviedb.org/settings/api)
2. Create an account (free)
3. Request an API key
4. Copy the key into Settings → TMDB API Key

## Troubleshooting

### "Python 3 is not installed"

Install Python 3:
```bash
# Using Homebrew
brew install python3

# Or download from python.org
```

### "Plex SQLite not found"

The app looks for Plex at its standard macOS location. If installed elsewhere:
1. Open Settings
2. Browse to find your Plex SQLite executable
3. Save configuration

### "Database file not found"

Plex database location is usually at:
```
~/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db
```

If your Plex data is stored elsewhere (external drive, cloud, etc.), update the path in Settings.

### App won't launch

Try launching from Terminal to see error messages:
```bash
/Applications/Plex\ TV\ Editor.app/Contents/MacOS/plex_tv_editor
```

Common issues:
- Missing `requests` module: `pip3 install requests`
- Plex paths incorrect: Update in Settings
- Database locked: Stop Plex first (use app's Service menu)

## Advanced

### Manual Install

If `build_macos_app.sh` doesn't work:

```bash
# Install dependencies
pip3 install requests

# Copy app to Applications
cp -r /path/to/repo/Plex\ TV\ Editor.app /Applications/

# Make executable
chmod +x "/Applications/Plex TV Editor.app/Contents/MacOS/plex_tv_editor"
```

### Running from Source

```bash
python3 /path/to/plex_tv_editor.py
```

### Building Standalone

To create a standalone executable without Python dependency, see `pyinstaller` or `py2app` documentation.

## Uninstall

```bash
rm -rf /Applications/Plex\ TV\ Editor.app
rm ~/.plex_tv_editor_config.json
```

## Development

To modify the app:

1. Edit `plex_tv_editor.py`
2. Run `build_macos_app.sh` to update the installed app
3. Or launch directly: `python3 plex_tv_editor.py`

## License

Created for managing Plex libraries with TMDB metadata.

## Support

For issues with Plex: [plex.tv](https://www.plex.tv)  
For TMDB data: [themoviedb.org](https://www.themoviedb.org)

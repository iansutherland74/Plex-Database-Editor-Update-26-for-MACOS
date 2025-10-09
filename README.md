# Plex Database Editor GUI v2.1

A graphical interface for safely editing movie "Added Date" timestamps in your Plex Media Server database.

![Version](https://img.shields.io/badge/version-2.1-blue)
![Python](https://img.shields.io/badge/python-3.6+-green)
![License](https://img.shields.io/badge/license-MIT-orange)

## 📋 Overview

This application provides a user-friendly GUI to modify the "added date" for movies in your Plex Media Server database. Perfect for organizing your library chronologically or correcting import dates.

**Features:**
- ✨ Clean, intuitive graphical interface
- 🔍 Real-time search and filtering
- 📅 Human-readable date formats with customization
- 🎯 Quick date presets (Today, Yesterday, 1 Week Ago, etc.)
- 💾 Automatic database backup functionality
- ⚡ Live Plex service status monitoring
- 🔐 Safe database operations using official Plex SQLite
- ✅ Verification of all database changes
- 📊 Handles up to 1000 movies (configurable)

## 🎬 Screenshots
<img width="938" height="715" alt="2025-10-09_10-26" src="https://github.com/user-attachments/assets/5a93b825-1ae1-4580-8154-759fd4a28fbc" />

<img width="932" height="722" alt="2025-10-09_10-27" src="https://github.com/user-attachments/assets/68a7b38b-56ef-4ca0-aa4d-76aa3860dc7e" />




### Main Window
- Browse and search through your movie library
- See current "Added Date" for each movie
- Monitor Plex service status
- Control Plex service (start/stop)

### Edit Dialog
- Large, resizable edit window
- Real-time status updates
- Quick date selection buttons
- On-screen success/error messages
- Prominent SAVE CHANGES button

## 🔧 Requirements

### System Requirements
- **OS:** Linux (tested on Ubuntu 24)
- **Python:** 3.6 or higher
- **Plex Media Server:** Installed and configured
- **Permissions:** Root/sudo access required

### Python Dependencies
- `tkinter` - GUI framework
- Standard library modules: `subprocess`, `os`, `sys`, `datetime`, `shutil`, `json`, `pathlib`

### System Tools
- Plex SQLite binary (usually at `/usr/lib/plexmediaserver/Plex SQLite`)
- Access to Plex database (usually at `/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db`)

## 📦 Installation

### 1. Install Python and Tkinter

```bash
sudo apt-get update
sudo apt-get install python3 python3-tk
```

### 2. Download the Script

```bash
# Download plex_gui.py to your preferred location
cd ~/plex-tools
wget [URL-to-plex_gui.py]
# or copy the file manually

chmod +x plex_gui.py
```

### 3. Verify Plex Paths

Check that these paths exist on your system:
```bash
# Plex SQLite binary
ls -l /usr/lib/plexmediaserver/Plex\ SQLite

# Plex database
ls -l /var/lib/plexmediaserver/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.plugins.library.db
```

If your paths are different, you can configure them in the application settings.

## 🚀 Usage

### Starting the Application

**From Terminal (Recommended - shows debug output):**
```bash
sudo python3 plex_gui.py
```

**Why sudo?** The application needs root access to:
- Read/write the Plex database
- Control the Plex service (start/stop)
- Create database backups

### Basic Workflow

1. **Launch the application**
   ```bash
   sudo python3 plex_gui.py
   ```

2. **Stop Plex Media Server**
   - Click "Stop Plex" button in the main window
   - Wait for status to show "OK: Plex is STOPPED"
   - ⚠️ **CRITICAL:** Database must not be in use during edits

3. **Find your movie**
   - Use the search box to filter movies
   - Browse through the list (shows 1000 most recent)

4. **Edit the date**
   - Double-click on any movie row
   - Edit dialog opens showing current date
   - Enter new date or use quick date buttons
   - Click **SAVE CHANGES**
   - Watch status bar for confirmation

5. **Verify the change**
   - Click "Refresh" to reload the movie list
   - Confirm new date appears correctly

6. **Restart Plex**
   - Click "Start Plex" button
   - Your changes are now active

### Quick Date Presets

The edit dialog includes convenient quick date buttons:
- **Now** - Current date and time
- **Today** - Today at midnight
- **Yesterday** - Yesterday at current time
- **1 Week Ago** - 7 days prior
- **1 Month Ago** - 30 days prior
- **1 Year Ago** - 365 days prior

### Keyboard Shortcuts

**Main Window:**
- `Ctrl+,` - Open Settings
- `Ctrl+B` - Create Backup
- `Ctrl+F` - Focus Search
- `Ctrl+R` - Refresh Movies
- `Ctrl+Q` - Quit Application

**In Dialogs:**
- `Enter` - Save/Confirm
- `Escape` - Cancel/Close

## ⚙️ Configuration

### Settings Dialog

Access via: **File → Settings** or press `Ctrl+,`

**Configurable Options:**

1. **Plex SQLite Path**
   - Default: `/usr/lib/plexmediaserver/Plex SQLite`
   - Change if your Plex installation is in a different location

2. **Database Path**
   - Default: `/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db`
   - Change if your Plex data is stored elsewhere

3. **Date Format**
   - Default: `%Y-%m-%d %H:%M:%S` (2024-10-09 14:30:45)
   - Other presets available in dropdown
   - Supports any Python strftime format

**Settings are saved to:** `~/.plex_editor_config.json`

### Date Format Options

Common formats provided:
- `%Y-%m-%d %H:%M:%S` → 2024-10-09 14:30:45
- `%d/%m/%Y %H:%M:%S` → 09/10/2024 14:30:45
- `%m/%d/%Y %H:%M:%S` → 10/09/2024 14:30:45
- `%Y-%m-%d` → 2024-10-09
- `%d/%m/%Y` → 09/10/2024
- `%m/%d/%Y` → 10/09/2024

See **Help → Date Format Help** for all format codes.

## 🛡️ Safety Features

### Automatic Plex Service Check
- Detects if Plex is running before allowing edits
- Prompts to stop Plex automatically
- Prevents database corruption from concurrent access

### Database Verification
- Every update is verified by reading back the changed value
- Confirms timestamp was actually modified
- Shows clear success/failure messages

### Backup Creation
- Manual backup via **File → Create Backup** or `Ctrl+B`
- Timestamped backup files: `com.plexapp.plugins.library.db.backup.YYYYMMDD_HHMMSS`
- Stored in same directory as original database
- **Recommended:** Create backup before making changes

### Safe SQL Operations
- Uses official Plex SQLite binary (not generic sqlite3)
- Properly handles Plex's custom database schema
- All queries are logged for debugging
- Read-only queries for verification

## 🐛 Troubleshooting

### "Permission Required" Dialog
**Problem:** Application needs sudo/root access

**Solution:**
```bash
sudo python3 plex_gui.py
```

### "Plex SQLite not found" or "Database not found"
**Problem:** Paths don't match your installation

**Solution:**
1. Open Settings (Ctrl+,)
2. Use Browse buttons to locate correct paths
3. Check Status section shows "[OK] Found"
4. Click Save

### Save Button Not Visible
**Problem:** Dialog window too small

**Solution:**
- Dialog is now 600x550 pixels by default
- It's resizable - drag the corners
- Look for gray text: "Scroll down if you don't see..."

### "Update failed" or No Changes Happening
**Check these:**

1. **Is Plex stopped?**
   ```bash
   systemctl status plexmediaserver
   # Should show "inactive (dead)"
   ```

2. **Do you have sudo?**
   ```bash
   whoami
   # Should show "root" when running with sudo
   ```

3. **Check console output**
   - Run from terminal to see debug messages
   - Look for SQL errors
   - Verify query is being executed

4. **Database locked?**
   - Make sure no other tools are accessing database
   - Stop Plex completely
   - Wait 10 seconds before editing

### X11 Rendering Errors
**Problem:** `BadLength` or similar X11 errors

**Note:** All emoji have been removed from this version to prevent X11 rendering issues. If you still encounter problems:

```bash
# Install font packages
sudo apt-get install fonts-liberation fonts-dejavu

# Verify DISPLAY
echo $DISPLAY  # Should show :0 or similar
```

### Movies Not Loading
**Problem:** Empty movie list or "Loading..." stuck

**Check:**
1. Database path is correct (Settings)
2. You have read permission to database
3. Database file is not corrupted
4. Check console for SQL errors

**Test database access:**
```bash
sudo /usr/lib/plexmediaserver/Plex\ SQLite \
  /var/lib/plexmediaserver/Library/Application\ Support/Plex\ Media\ Server/Plug-in\ Support/Databases/com.plexapp.plugins.library.db \
  "SELECT COUNT(*) FROM metadata_items WHERE guid LIKE 'plex://movie/%'"
```

## 📝 Technical Details

### How It Works

1. **Loading Movies:**
   - Queries Plex database for movies: `SELECT id, title, added_at FROM metadata_items WHERE guid LIKE 'plex://movie/%'`
   - Converts Unix epoch timestamps to human-readable format
   - Loads up to 1000 most recent movies

2. **Updating Dates:**
   - Parses human-readable date to Unix epoch timestamp
   - Executes: `UPDATE metadata_items SET added_at = [epoch] WHERE id = [movie_id]`
   - Verifies update: `SELECT added_at FROM metadata_items WHERE id = [movie_id]`
   - Reloads movie list to show changes

3. **Database Format:**
   - Plex stores dates as Unix epoch timestamps (seconds since 1970-01-01)
   - This app handles the conversion to/from human-readable formats

### Database Schema
```sql
-- Relevant table structure
metadata_items (
    id INTEGER PRIMARY KEY,
    title TEXT,
    added_at INTEGER,  -- Unix epoch timestamp
    guid TEXT,         -- Format: plex://movie/...
    ...
)
```

### File Locations

**Configuration:**
- `~/.plex_editor_config.json` - User settings

**Plex Default Paths:**
- Binary: `/usr/lib/plexmediaserver/Plex SQLite`
- Database: `/var/lib/plexmediaserver/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db`

**Backups:**
- Stored alongside database
- Format: `com.plexapp.plugins.library.db.backup.YYYYMMDD_HHMMSS`

## ⚠️ Important Notes

### Before You Start
1. **ALWAYS create a backup** before making changes
2. **ALWAYS stop Plex** before editing the database
3. **Test on a few movies first** to ensure everything works
4. Keep Plex stopped until all edits are complete

### Limitations
- Loads only 1000 most recent movies (can be changed in code)
- Only edits the "Added Date" field
- Does not modify other metadata (ratings, posters, etc.)
- Works only with movies (not TV shows, music, etc.)

### What This Does NOT Do
- ❌ Modify movie ratings
- ❌ Change posters or artwork
- ❌ Edit TV show episodes
- ❌ Modify media file paths
- ❌ Change movie titles or descriptions
- ❌ Affect your actual media files

### Data Safety
- ✅ Uses official Plex SQLite (not generic sqlite3)
- ✅ Only modifies the `added_at` field
- ✅ Verifies every change
- ✅ Supports easy backup/restore
- ✅ Logs all SQL queries for audit

## 🤝 Contributing

Contributions are welcome! Areas for improvement:
- Support for TV shows
- Batch date editing
- Date range selection
- Import/export date mappings
- Undo/redo functionality
- More date format presets

## 📄 License

This project is provided as-is for educational and personal use. 

**Use at your own risk.** Always backup your Plex database before making changes.

## 🙏 Credits

- Uses official Plex SQLite binary for safe database operations
- Built with Python's tkinter for cross-platform GUI
- Designed for Linux systems running Plex Media Server

## 📞 Support

For issues or questions:
1. Check the Troubleshooting section above
2. Run with `sudo python3 plex_gui.py` from terminal to see debug output
3. Check console output for specific error messages
4. Verify Plex is stopped before editing

## 🔄 Version History

### v2.1 (Current)
- Fixed dialog window size (600x550)
- Added on-screen status messages
- Made buttons more prominent (25 chars wide)
- Added real-time update verification
- Removed all emoji to prevent X11 errors
- Made window resizable
- Improved error handling
- Added comprehensive debug logging

### v2.0
- Complete GUI rewrite
- Configurable paths and date formats
- Added quick date presets
- Keyboard shortcuts
- Search and filter functionality
- Service control integration

### v1.0
- Initial release
- Basic command-line interface

---

**Made with ❤️ for Plex users who want more control over their library**

*Remember: Always backup before making changes!*

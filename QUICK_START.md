# Plex TV Editor - Quick Start Guide

## ✅ Installation Complete!

Your macOS app has been successfully built and installed to `/Applications/Plex TV Editor.app`

## 🚀 Launch the App

**Option 1: Spotlight Search (Easiest)**
- Press `Cmd + Space`
- Type: `Plex TV Editor`
- Press Enter

**Option 2: Finder**
- Open `/Applications`
- Double-click `Plex TV Editor.app`

**Option 3: Terminal**
```bash
open /Applications/Plex\ TV\ Editor.app
```

## ⚙️ First Launch Setup

The app is pre-configured with:
- ✅ TMDB API Key: `fd51c863ad45547eb19ba9f70f3ac4f0`
- ✅ macOS Plex paths (auto-detected)
- ✅ Database location (auto-detected)

If Plex paths need adjustment:
1. Open the app
2. Click **File → Settings**
3. Update paths if needed
4. Click **Save**

## 📝 Basic Usage

### Search for a Show
1. Enter show name (e.g., "Breaking Bad")
2. Click **Search TMDB**
3. Select the show from results
4. Seasons and episodes appear in the list

### Edit Dates
1. **Double-click** any date in the list
2. Choose a date or use quick buttons
3. Click **SAVE CHANGES**
4. Restart Plex (via app's Service menu)

### Load Your Plex Shows
- Click **Load Plex Shows** to see all your TV series

## 🔌 Enable Plex Integration (Optional)

If you want the app to control Plex service:
1. Click **Service → Check Status** to test
2. Use **Stop Plex** / **Start Plex** buttons
3. Always stop Plex before editing dates

## 📂 Configuration File

Settings are stored at: `~/.plex_tv_editor_config.json`

View/edit with:
```bash
cat ~/.plex_tv_editor_config.json
```

## 🆘 Troubleshooting

**App won't launch from Finder?**
```bash
/Applications/Plex\ TV\ Editor.app/Contents/MacOS/plex_tv_editor
```

**TMDB search not working?**
- Verify internet connection
- Check API key in Settings

**Plex database not found?**
- Update path in Settings
- Make sure Plex Media Server is installed

**Can't edit dates?**
- Make sure to Stop Plex first (Service menu)
- Create a backup before editing

## 📚 More Help

Full documentation: See `README_MACOS_APP.md` in the repo

## 🗑️ Uninstall

```bash
rm -rf /Applications/Plex\ TV\ Editor.app
rm ~/.plex_tv_editor_config.json
```

---

**You're all set!** Launch the app and start managing your Plex TV library with TMDB data.

# Plex TV Editor - macOS Apple Silicon Fix

## Your Crash Report Analysis

Your app crashed due to **Tkinter initialization failure** on Apple Silicon. The issue:

- Python 3.9 from Xcode runs under **Rosetta 2 translation** on your M1 Mac
- Tkinter's Tk framework (8.5.9) doesn't reliably initialize under translation
- **Solution**: Use a native ARM64 Python installation

---

## Quick Fix: Install Native Python

### Option 1: Homebrew (Recommended)

```bash
# Install Homebrew if needed
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Install native Python 3
brew install python3

# The app will automatically use this when you relaunch
```

### Option 2: Python Official Distribution

1. Visit [python.org](https://www.python.org/downloads/macos/)
2. Download **macOS 64-bit ARM64 installer** 
3. Run the installer
4. After installation, relaunch Plex TV Editor

### Option 3: pyenv (If you manage multiple Python versions)

```bash
brew install pyenv
pyenv install 3.12.0
pyenv global 3.12.0
```

---

## How the Fix Works

The app launcher has been updated to:

1. **First** - Try Homebrew's native Python (`/opt/homebrew/bin/python3`)
2. **Second** - Try pyenv's Python (if installed)
3. **Third** - Use system Python (`/usr/bin/python3`)
4. **Fallback** - Alert user if no suitable Python found

The launcher checks that Python runs **natively on ARM64** (not translated), and verifies Tkinter works before launching.

---

## Verification

After installing Python, check which version the app uses:

```bash
# This is what the app will automatically detect
if [ -x "/opt/homebrew/bin/python3" ]; then
    /opt/homebrew/bin/python3 -c "import platform; print('Architecture:', platform.machine())"
    # Should print: Architecture: arm64
fi
```

---

## Try Launching Again

Once Python is installed:

1. **Close** any running Plex TV Editor instances
2. **Relaunch** the app (Spotlight: Cmd+Space → "Plex TV Editor")
3. The launcher will auto-detect and use the native Python
4. App should now work

---

## Still Having Issues?

If the crash persists:

```bash
# Test if Tkinter works
python3 -c "import tkinter; print('✓ Tkinter works')"

# Check Python architecture
python3 -c "import platform; print('Python arch:', platform.machine())"

# If running under Rosetta, you'll see: x86_64 (means translation)
# If native arm64: arm64 (what we want)
```

---

## Technical Details

**Crash Location**: In your crash report:
```
Exception: EXC_CRASH (SIGABRT)
Thread: Dispatch queue: com.apple.main-thread
Stack: abort() → Tcl_Panic → TkpInit → _tkinter
Process: Python 3.9 (Translated by Rosetta 2)
```

This is a known Apple Silicon compatibility issue where system Tcl/Tk (8.5.9) doesn't work reliably with translated Python. Native Python installations include compatible Tk bindings.

---

**Updated**: 2026-03-05  
**Target**: macOS 10.13+ on Apple Silicon (M1, M1 Pro, M1 Max, M2, etc.)

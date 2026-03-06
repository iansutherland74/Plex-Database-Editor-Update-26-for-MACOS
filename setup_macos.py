#!/usr/bin/env python3
"""
Setup script for Plex TV Editor with TMDB Integration on macOS
"""

import subprocess
import sys
import os

def install_requirements():
    """Install Python dependencies"""
    print("Installing Python dependencies...")
    
    packages = ['requests']
    
    for package in packages:
        try:
            __import__(package)
            print(f"  ✓ {package} already installed")
        except ImportError:
            print(f"  Installing {package}...")
            subprocess.check_call([sys.executable, '-m', 'pip', 'install', package])
    
    print("\nDependencies installed!")

def verify_plex():
    """Verify Plex Media Server installation"""
    print("\nVerifying Plex installation...")
    
    plex_paths = [
        "/Applications/Plex Media Server.app/Contents/Resources/Support/Plex SQLite"
    ]
    
    for path in plex_paths:
        if os.path.exists(path):
            print(f"  ✓ Found Plex SQLite at {path}")
            return True
    
    print("  ! Plex Media Server not found at standard location")
    print("    You may need to configure paths in Settings")
    return False

def verify_plex_db():
    """Verify Plex database exists"""
    print("Verifying Plex database...")
    
    db_path = os.path.expanduser("~/Library/Application Support/Plex Media Server/Plug-in Support/Databases/com.plexapp.plugins.library.db")
    
    if os.path.exists(db_path):
        print(f"  ✓ Found Plex database")
        return True
    
    print("  ! Plex database not found")
    print(f"    Expected at: {db_path}")
    return False

def main():
    print("=" * 60)
    print("Plex TV Editor Setup - macOS")
    print("=" * 60)
    
    # Install dependencies
    install_requirements()
    
    # Verify environment
    verify_plex()
    verify_plex_db()
    
    print("\n" + "=" * 60)
    print("Setup complete!")
    print("\nTo launch the app, run:")
    print("  python3 plex_tv_editor.py")
    print("\nOn first launch, you'll be prompted to configure paths if needed.")
    print("=" * 60)

if __name__ == "__main__":
    main()

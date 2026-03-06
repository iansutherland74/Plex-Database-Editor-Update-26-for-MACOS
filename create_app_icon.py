#!/usr/bin/env python3
"""
Create a macOS app icon for Plex TV Editor
Generates icns file from a simple PNG
"""

import os
import subprocess
import sys

def create_icon():
    """Create app icon using built-in macOS tools"""
    
    app_path = "/Users/sutherland/repo/Plex TV Editor.app"
    resources_path = os.path.join(app_path, "Contents/Resources")
    
    # Create iconset directory
    iconset_path = os.path.join(resources_path, "AppIcon.iconset")
    os.makedirs(iconset_path, exist_ok=True)
    
    # Create a simple icon using sips (macOS built-in image processing)
    # We'll create colored squares at different sizes
    
    sizes = [
        ("icon_16x16.png", 16),
        ("icon_32x32.png", 32),
        ("icon_64x64.png", 64),
        ("icon_128x128.png", 128),
        ("icon_256x256.png", 256),
        ("icon_512x512.png", 512)
    ]
    
    # Create a simple blue/purple gradient icon
    # Using Python PIL if available, otherwise use a placeholder
    
    try:
        from PIL import Image, ImageDraw
        
        for filename, size in sizes:
            # Create image with gradient
            img = Image.new('RGB', (size, size), color=(70, 130, 180))  # Steel blue
            
            # Draw a play button or media symbol
            draw = ImageDraw.Draw(img)
            
            # Draw circle
            margin = size // 10
            draw.ellipse(
                [margin, margin, size - margin, size - margin],
                outline=(255, 255, 255),
                width=max(1, size // 32)
            )
            
            # Draw play triangle
            triangle_margin = size // 4
            points = [
                (triangle_margin, triangle_margin),
                (triangle_margin, size - triangle_margin),
                (size - triangle_margin, size // 2)
            ]
            draw.polygon(points, fill=(255, 255, 255))
            
            # Save
            filepath = os.path.join(iconset_path, filename)
            img.save(filepath)
            print(f"Created {filename}")
        
        # Convert iconset to icns
        icns_path = os.path.join(resources_path, "AppIcon.icns")
        subprocess.run([
            "iconutil",
            "-c", "icns",
            iconset_path,
            "-o", icns_path
        ], check=True)
        
        print(f"Created AppIcon.icns")
        
        # Update Info.plist to reference the icon
        import plistlib
        plist_path = os.path.join(app_path, "Contents/Info.plist")
        
        with open(plist_path, 'rb') as f:
            plist_data = plistlib.load(f)
        
        plist_data['CFBundleIconFile'] = 'AppIcon'
        
        with open(plist_path, 'wb') as f:
            plistlib.dump(plist_data, f)
        
        print("Updated Info.plist with icon reference")
        
    except ImportError:
        print("PIL not available, using placeholder icon creation...")
        # Create a simple colored square as fallback
        import subprocess
        
        # Just create a simple 256x256 icon
        size = 256
        
        # Use Python to create a simple PNG
        python_code = f"""
import struct
import zlib
import os

# Create a simple PNG image (256x256 blue square)
width = {size}
height = {size}

# PNG file signature
signature = b'\\x89PNG\\r\\n\\x1a\\n'

# IHDR chunk
ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
ihdr_crc = zlib.crc32(b'IHDR' + ihdr_data) & 0xffffffff
ihdr = struct.pack('>I', len(ihdr_data)) + b'IHDR' + ihdr_data + struct.pack('>I', ihdr_crc)

# IDAT chunk (image data - simple blue color)
raw_data = b''
for y in range(height):
    raw_data += b'\\x00'  # Filter type: None
    for x in range(width):
        raw_data += b'\\x46\\x82\\xb4'  # RGB blue color

compressed = zlib.compress(raw_data, 9)
idat_crc = zlib.crc32(b'IDAT' + compressed) & 0xffffffff
idat = struct.pack('>I', len(compressed)) + b'IDAT' + compressed + struct.pack('>I', idat_crc)

# IEND chunk
iend = struct.pack('>I', 0) + b'IEND' + struct.pack('>I', 0xae426082)

# Write PNG
png_data = signature + ihdr + idat + iend

with open('/Users/sutherland/repo/Plex TV Editor.app/Contents/Resources/AppIcon.iconset/icon_256x256.png', 'wb') as f:
    f.write(png_data)
"""
        
        subprocess.run(['python3', '-c', python_code], check=True)
        print("Created placeholder icon")

if __name__ == "__main__":
    try:
        create_icon()
        print("\nIcon creation complete!")
    except Exception as e:
        print(f"Icon creation failed: {e}")
        print("Note: Icon is optional, the app will still work fine")

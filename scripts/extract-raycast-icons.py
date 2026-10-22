#!/usr/bin/env python3
"""Extracts Raycast's icon symbols from a locally installed Raycast.app into standalone SVGs.

These icons are Raycast's own artwork: they're copied at build time from *your* Raycast
install into Jot.app for personal use, and are never committed to this repository.
Usage: extract-raycast-icons.py <output-dir>
"""
import glob, os, re, sys

FRONTEND = "/Applications/Raycast.app/Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources/frontend"
out = sys.argv[1]
sources = glob.glob(os.path.join(FRONTEND, "icons-*.js"))
if not sources:
    print("Raycast not found; Jot will fall back to SF Symbols")
    sys.exit(0)
os.makedirs(out, exist_ok=True)
count = 0
for path in sources:
    text = open(path, encoding="utf-8", errors="ignore").read()
    for name, viewbox, body in re.findall(r'<symbol id="([^"]+)" viewBox="([^"]+)">(.*?)</symbol>', text, re.S):
        body = body.replace("currentColor", "#000")
        size = viewbox.split()[2:]
        svg = f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="{viewbox}" width="{size[0]}" height="{size[1]}">{body}</svg>'
        with open(os.path.join(out, f"{name}.svg"), "w") as f:
            f.write(svg)
        count += 1
print(f"Extracted {count} Raycast icons")

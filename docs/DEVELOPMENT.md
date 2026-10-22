# Development

## Requirements

- macOS 26 or later (Jot uses Liquid Glass and TextKit 2 APIs from macOS 26).
- Xcode 26 or later with Swift 6.2 or later.
- Optional: Raycast installed in `/Applications`. The build copies Raycast's icon set from
  your own install (see below). Without it, Jot falls back to similar SF Symbols.

## Build, run and test

```sh
make test      # swift test
make app       # builds build/Jot.app (release, ad-hoc signed)
make run       # builds and opens build/Jot.app
make install   # copies Jot.app to /Applications
make clean     # removes .build and build
```

Jot is a menu-bar utility (`LSUIElement`), so it has no Dock icon. ⇧⌘N shows or hides the
window from anywhere.

After rebuilding, quit the running Jot before opening the new build: `open` only brings an
already running copy to the front.

```sh
pkill -x Jot; open build/Jot.app
```

## Raycast's icons

Jot's menus use Raycast's icon names. `scripts/extract-raycast-icons.py` reads the icon
symbols from your local Raycast.app at build time and writes them into
`Jot.app/Contents/Resources/Icons`. They are Raycast's artwork and are never committed to
this repository. `Theme/RaycastIcon.swift` maps the common ones to SF Symbols when the
extracted icons aren't there.

## Dev flags

Environment variables for testing and screenshots. Use a scratch database so your own notes
stay untouched:

```sh
JOT_DB=/tmp/jot-test.db JOT_EMPTY=1 JOT_OPEN_MENU=/ build/Jot.app/Contents/MacOS/Jot
```

| Env var | Effect |
|---|---|
| `JOT_DB=/path.db` | use a scratch database |
| `JOT_EMPTY=1` | open a new empty note |
| `JOT_TEXT_FILE=/path.txt` | open a new note with one paragraph per line |
| `JOT_JSON_FILE=/path.json` | open a new note from Tiptap JSON |
| `JOT_DEMO=1` | open the block-type showcase note |
| `JOT_OPEN_MENU=actions\|browse\|format\|/query` | open that menu after launch (`/query` types it into the note) |
| `JOT_MENU_DOWN=n` | press ↓ n times in that menu (scroll checks) |
| `JOT_HOVER=1` | show the hovered chrome (buttons, traffic lights) |
| `JOT_SCROLL=y` | scroll the note to `y` after launch |
| `JOT_FRAME=x,y,w,h` | pin the window (top-left coordinates) for screenshot comparisons |
| `JOT_TOAST=title` | show a success toast one second after launch |
| `JOT_NO_HEADER_BLUR=1` | leave out the header's progressive blur (A/B comparisons) |

## Screenshots without touching your screen

`screencapture -l <window id>` (or `-R x,y,w,h` for a window and its menus) captures Jot's
windows while you keep working. Combine it with the flags above, for example
`JOT_OPEN_MENU=/ JOT_MENU_DOWN=12`, to check a menu's state without typing into the app.

## Matching Raycast

Most values in `docs/DESIGN.md` were read from Raycast.app's shipped frontend
(`Contents/Resources/macos-app_RaycastDesktopApp.bundle/Contents/Resources/frontend`), whose
CSS and JavaScript are readable, and from the class metadata in its binary
(`otool -ov /Applications/Raycast.app/Contents/MacOS/Raycast`). When behaviour or a pixel
value is in question, check it there before changing an approach.

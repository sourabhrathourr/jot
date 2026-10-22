# Jot

**Raycast Notes, but free.** A floating notes window for macOS that looks and works like
Raycast Notes, rebuilt from scratch as a fully native app. Unlimited notes, images included,
no account, open source.

Press **⇧⌘N** anywhere (or your own shortcut), write, and press it again to get back to what
you were doing.

## Why

Raycast Notes is one of the nicest places to jot something down on a Mac: a quiet glass
window that's always one shortcut away, with just enough formatting. Jot is a love letter to
that design. It follows Raycast Notes down to the pixel and the keystroke, and runs on
AppKit and TextKit 2 instead of a web view.

## Features

- **A floating glass window** on Liquid Glass, with Raycast's material, 26pt corners, fading
  chrome and a progressive blur under the header. It grows with your note until you resize it.
- **Rich text that stays out of the way:** headings, bold, italic, underline, strikethrough,
  inline code, links, bulleted, numbered and task lists with nesting, quotes, code blocks
  and dividers.
- **Markdown as you type:** `# `, `- `, `1. `, `[] `, `> `, ` ``` `, `---`, `**bold**`,
  `*italic*`, `` `code` ``, `~~strike~~`.
- **The `/` menu:** type `/` for headings, marks, blocks and lists, filtered as you type with
  Raycast's fuzzy matching.
- **Images:** paste screenshots, drop files, drag to reorder, Quick Look with Space. Stored
  locally next to your notes.
- **Action Panel (⌘K) and Browse Notes (⌘P)**, with search, pinned notes and recently deleted
  notes.
- **Your own shortcut:** change ⇧⌘N in Settings (⌘,) to anything, including Raycast's Hyper
  Key (`✦`). It wins over apps' own shortcuts, so a browser's ⇧⌘N won't fire while Jot uses it.
- **Hide from Screen Sharing:** one toggle keeps Jot out of screen shares, recordings and
  screenshots while it stays on your screen, so it works as speaker notes on a call. Off by
  default; find it in Settings, the Action Panel (⌘K) or the View menu.
- **Find (⌘F), zoom, a format bar, copy as Markdown, HTML or plain text, export, and
  `jot://` deeplinks.**
- **Updates built in:** Jot checks for new versions once a day (or Jot → Check for Updates…).
- **Your data stays on your Mac** in a single SQLite database, in the same shape as Raycast's
  notes table.

## Install

There are no prebuilt releases yet, so build it yourself. You need **macOS 26** or later and
**Xcode 26** (Swift 6.2 or later).

```sh
git clone https://github.com/sourabhrathourr/jot.git
cd jot
make install   # builds Jot.app and copies it to /Applications
open /Applications/Jot.app
```

Jot lives in the menu bar, not the Dock, and keeps running until you quit it (⌘Q). Closing the
window just hides it, and it opens at login. Press **⇧⌘N** to show or hide it, and open
**Settings…** from the menu bar icon or with ⌘, to choose another shortcut.

> Jot's menus use Raycast's icons. If Raycast is installed, the build copies them from your
> own Raycast.app; they're never stored in this repository. Without Raycast, Jot uses
> similar SF Symbols.

## Shortcuts

| Action | Key |
|---|---|
| Show or hide Jot (anywhere) | ⇧⌘N, or your own in Settings |
| Settings | ⌘, |
| New note | ⌘N |
| Browse notes | ⌘P |
| Action panel | ⌘K |
| Formatting menu | / |
| Pin note | ⇧⌘P |
| Find | ⌘F |
| Bold / Italic / Underline | ⌘B / ⌘I / ⌘U |
| Strikethrough / Inline code / Link | ⇧⌘S / ⌘E / ⌘L |
| Heading 1 / 2 / 3 | ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
| Numbered / Bulleted / Task list | ⇧⌘7 / ⇧⌘8 / ⇧⌘9 |
| Toggle task | ⌘↩ |
| Quote / Code block | ⇧⌘B / ⌥⌘C |
| Add image | ⇧⌘I |
| Copy note as… / Export… | ⇧⌘C / ⇧⌘E |
| Zoom in / out / actual size | ⌘= / ⌘- / ⌘0 |

Hide from Screen Sharing has no shortcut: turn it on in Settings, the Action Panel (⌘K) or
View → Hide from Screen Sharing.

The full list is in [docs/DESIGN.md](docs/DESIGN.md#behaviour-and-shortcuts).

## Your data

Notes are stored in `~/Library/Application Support/Jot/jot.db`, and images in the
`Attachments` folder next to it. Deleted notes go to Recently Deleted first. Nothing leaves
your Mac.

## Documentation

- [docs/DESIGN.md](docs/DESIGN.md): how Jot matches Raycast Notes (colours, typography,
  window, menus, the slash menu, data) and how the code is organised.
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): building, testing, dev flags, screenshots for
  comparisons, and releasing (signing, notarization, the DMG and updates).
- [website/](website): the site at [getjot.vercel.app](https://getjot.vercel.app).

## Contributing

Issues and pull requests are welcome. Run `make test` before sending a change, and if it
touches how something looks, include a before and after screenshot. Jot aims to feel exactly
like Raycast Notes, so differences from Raycast count as bugs.

## Credits

Jot exists because of [Raycast](https://www.raycast.com) and its team. Raycast Notes is a
wonderful product: the design, the typography, the little details in every interaction. Jot
studies and follows it closely. Thank you, Raycast, for making something this good and for
inspiring this project. If you enjoy Jot, try Raycast; it does far more than notes.

Jot is an independent project. It is not affiliated with, endorsed by or sponsored by
Raycast Technologies. "Raycast" is a trademark of its owner. Raycast's icons are not
included in this repository.

Fonts: [Inter](https://github.com/rsms/inter) and
[JetBrains Mono](https://github.com/JetBrains/JetBrainsMono), both under the SIL Open Font
License (licenses in `Sources/JotKit/Resources/Fonts`).

## License

[MIT](LICENSE) © Sourabh Rathour

# Design notes

Jot is a native macOS 26+ rebuild of Raycast Notes (2.8.x): a floating notes panel built with
AppKit and TextKit 2, with SwiftUI only for a few lists. There is no web view, no JavaScript
and no Node.

Raycast's own stack is `NotesWindow : WebViewPanel : NSPanel` → `NSGlassEffectView` →
`WKWebView` → React + Tiptap v3. Jot keeps the native shell and replaces the web editor with
`NSTextView` on TextKit 2. The values below were read from the CSS and JavaScript shipped
inside Raycast.app, and checked against screenshots of the real app.

## Look

### Colors

| Token | Dark | Light |
|---|---|---|
| fg | `#FFFFFF` | `#000000` |
| accent (Notes = brand) | `#FF6363` | `#FF6363` |
| yellow | `#FFC531` | `#F8A300` |
| text secondary / tertiary | fg 60% / fg 40% | same |
| separator | fg 10% | same |
| border secondary (hr) | fg 20% | same |

- Text selection: accent at 40%.
- Caret, list bullets and numbers, task checkboxes, the blockquote bar and links use the accent.
- Links: accent text, a 1px underline in accent at 55%, offset 2px.
- Find matches: yellow at 40% (fg 80% text); the active match is solid yellow with black text.

### Typography (all sizes scale with zoom)

- Body: **InterVariable** (weight 400, optical size pinned at 14), 14px, line height 145%,
  features `liga calt kern ss03 ss01`. Line widths and word positions match Raycast's pixels.
  The static Inter files are about 0.4% narrower than the variable font, so the variable font
  is bundled. Tabular figures only for list numbers and the counter.
- Line boxes: TextKit 2 bottom-aligns glyphs in fixed-height lines and ignores the first
  paragraph's spacing, while CSS centres them (half-leading). Each block is shifted up by the
  baseline difference, and the first block's margin is applied through `textContainerOrigin`.
  The scroll view's clip view must not add its automatic 16pt insets.
- The first line box sits at y = 64 (52 header + 4 editor padding + 8 paragraph margin).
- Counter: graphemes of the trimmed plain text, blocks joined by a blank line (Tiptap's `getText()`).
- H1 22px/600, H2 18px/600, H3 16px/500, line height 1.25. Margins: H1 30 top / 8 bottom,
  H2 18/6, H3 18/4 (8/6/4 on top when first or after a divider).
- Paragraph spacing: 8px between top-level paragraphs.
- Inline code: JetBrains Mono at 0.835em, background fg 10%, text fg 60%, radius 0.5em,
  padding 0 0.4em.
- Code block: JetBrains Mono 13px, line height 1.5, background fg 5%, radius 12,
  padding 8/12/12, margin 12.
- Blockquote: a 2px rounded accent bar, padding-left 12.
- Divider: a 2px rounded line in fg 20%, margin 16.
- Lists: 22px indent per level; bullets `•` `◦` `▪` by depth; ordered numbers tabular and
  right-aligned.
- Task checkbox: 14×14, radius 5, 1.5px accent border; checked is an 8×8 accent square with
  radius 2.5, and checked text is fg 70%.
- Placeholder: "Write something …" in tertiary.

### Window

- A floating, titled `NSPanel` with a transparent title bar and full-size content.
- Material (measured to an RMSE of 0.03/255 against a live Raycast Notes window over a fixed
  test pattern): a behind-window `NSVisualEffectView` with material `.popover`, state
  `.active`, under a `CAGradientLayer` of the theme background at 40% (black in dark mode,
  white in light). Liquid Glass (`NSGlassEffectView`) is used for controls: the header
  capsule, the format pill, the toggle, the find bar and the menus.
- Private AppKit hooks Raycast uses, and Jot copies:
  - `NSThemeFrame._cornerRadius` → 26, so the frame's border and shadow follow the material
    (`WindowCornerRadius.swift`). The menus use the same hook with their own radius; a
    borderless window would get a dark outline around its shadow instead.
  - `NSWindow._setForceMainAppearance:` YES, so the window never dims when inactive.
  - `NSGlassEffectView._adaptiveAppearance` = 1.
- The traffic lights fade out when the pointer leaves the window.
- Header 52px: centred title, actions on the right. A progressive blur under the header
  gets stronger towards the top.
- Footer 48px: centred character counter, the glass format pill and a 32×32 glass toggle.
- Editor padding: 4px vertical, 24px horizontal.
- Hover chrome: when the pointer leaves the window, the title goes to 30% opacity, header
  actions and the footer toggle hide, and format buttons go to 30% (all 0.14s).
- The separator under the header fades in (0.14s) once the content is scrolled.
- Auto-height: the window grows and shrinks to fit the note until it's resized by hand.

## Menus

The Action Panel (⌘K), Browse Notes (⌘P) and the slash menu are rebuilt from Raycast's
`menu.namespace`, `standard-list-item`, `shortcut` and `popover` CSS. Raycast renders its
popovers in its own `PortalWindow : NSPanel`; Jot's `MenuPanel` is the same idea: a titled
panel with a hidden title bar, Liquid Glass content and a theme-frame corner radius.

- Rows are 36pt (58pt for two-line rows), radius 10, a 16pt icon and an 8pt gap; the
  selected row is fg at 10%.
- Section headers are 11px secondary text; Raycast's `wr` row layout gives 12pt above a
  header and 8pt + a faded hairline + 12pt between sections.
- Keyboard scrolling keeps 8pt between the selected row and either edge, and selecting the
  first row scrolls back to the top.
- Only an actual pointer move selects a row, not a row appearing under a still pointer.
- The Action Panel and Browse Notes open with Raycast's `popover__open` animation
  (0.25s, `cubic-bezier(.3,.7,0,1.26)`, opacity 0.6 → 1, scale 0.97 → 1) and close with
  `popover__close` (0.15s ease-out).

### Slash menu

Raycast's `im` / `rm` on its `At` suggestion plugin (a wrapper around Tiptap's suggestion
utility):

- `/` opens the menu at the start of a block, after a space or non-breaking space, or after
  a hard break. It doesn't open mid-word, in a code block or in inline code.
- The query is the text after `/` up to the caret. A leading space closes it
  (`dismissOnLeadingSpace`), and so does a run of two spaces (`allowSpaces: 1`).
- Escape closes it and keeps it closed while the match still starts at the same `/`.
- Sections: **Headings** (Heading 1–3), **Inline** (Bold, Italic, Strikethrough, Underline,
  Code), **Blocks** (Code Block, Blockquote) and **Lists** (Ordered, Bullet, Task; "todo" and
  "check" find Task List).
- With a query, the sections flatten into one ranked list using a port of Raycast's fuzzy
  matcher (`MenuSearch.swift`); with no matches the menu hides.
- Keys: ↑↓ (no wrapping), ⌥↑↓ by five, ⌘↑↓ by section, ⌘1–9 and ⌘0 choose a row, ↩ chooses
  the selected row, Tab does nothing.
- Choosing deletes `/query` and runs the command; inline marks apply to what's typed next.
- The panel is 280pt wide and at most 280pt tall, 8pt under the text and 16pt to its left so
  the icons line up with the `/`, and flips above when there's no room below. It has no
  animation, and the editor keeps focus. While it shows, the window keeps its height.

### Hide from Screen Sharing

Not in Raycast Notes; Jot's own addition. When it's on, every Jot window (the notes panel,
the menus and the link popover) gets `NSWindow.sharingType = .none`. Windows like that are
left out of ScreenCaptureKit captures (Zoom, Google Meet, Teams, QuickTime, the macOS
screenshot tools) and `screencapture`, but stay visible on your own screen. It's off by
default and stored in `UserDefaults` (`hideFromScreenSharing`). The toggle lives with the
other window settings in the Action Panel, and in the View menu with a checkmark. System
windows Jot opens (Quick Look, the save panel) are drawn by macOS and stay visible.

### Settings and the global shortcut

Not in Raycast Notes as such (Raycast sets a hotkey per command in its own Settings); Jot's
Settings window (⌘,, or Settings… in the menu bar icon) holds:

- **Show or Hide Jot**, ⇧⌘N by default. A recorder modelled on Raycast's
  `keyboard-shortcut-recorder`: click it, press keys (held modifiers show as you press them),
  ⎋ cancels, ⌫ removes the shortcut, and ↺ resets to ⇧⌘N. A shortcut needs ⌘, ⌥ or ⌃, except
  on function keys. The current shortcut is paused while recording, so pressing it records.
- It's registered with `RegisterEventHotKey`, which delivers the keys to Jot before the
  frontmost app sees them, so it wins over apps' own shortcuts. The user's choice always wins
  in Jot too: a clash with Raycast's main hotkey or an enabled macOS shortcut
  (`CopySymbolicHotKeys`) is saved anyway, with a yellow hint about where to turn the other
  one off. Only a shortcut macOS refuses outright keeps the previous one.
- **Hyper Key.** Raycast's Hyper Key setting is read from Raycast's preferences
  (`com.raycast.macos.v1` → `raycast_hyperKey_state`: `enabled`, `keyCode`, `includeShiftKey`).
  When it's on, Settings says which key it is and offers "Use ✦ N". Hyper reaches apps as
  ⌃⌥⇧⌘ (or ⌃⌥⌘ without Shift) whichever tool provides it (Raycast, Karabiner, Hyperkey), so
  those combinations are drawn as one `✦` keycap, like Raycast does.
- **Open at Login** (`SMAppService`), on by default the first time Jot runs from
  /Applications, so it's in the menu bar after a restart and the shortcut works right away.
- **Hide from Screen Sharing** (see above).

Jot stays running in the background until you quit it (⌘Q): ⌘W, Esc and the close button
only hide the notes window, like the shortcut, and Jot opts out of macOS's automatic
termination of apps with no windows open.

The shortcut is stored in `UserDefaults` as `globalHotKey` (`keyCode` and modifier flags; a
`keyCode` of -1 means no shortcut).

## Behaviour and shortcuts

| Action | Key |
|---|---|
| Show or hide Jot (global) | ⇧⌘N, configurable in Settings |
| Settings | ⌘, |
| New note / Duplicate note | ⌘N / ⌘D |
| Browse notes / Action panel | ⌘P / ⌘K |
| Go back / Go forward | ⌘[ / ⌘] |
| Pin note | ⇧⌘P |
| Copy note as… / Copy deeplink / Export… | ⇧⌘C / ⇧⌘D / ⇧⌘E |
| Delete note / Delete all notes | ⌃X / ⌃⇧X |
| Find | ⌘F |
| Bold / Italic / Underline | ⌘B / ⌘I / ⌘U |
| Strikethrough / Inline code / Link | ⇧⌘S / ⌘E / ⌘L |
| Body / Heading 1 / 2 / 3 | ⌥⌘0 / ⌥⌘1 / ⌥⌘2 / ⌥⌘3 |
| Numbered / Bulleted / Task list | ⇧⌘7 / ⇧⌘8 / ⇧⌘9 |
| Toggle task | ⌘↩ |
| Quote / Code block / Divider | ⇧⌘B / ⌥⌘C / ⇧⌘- |
| Add image | ⇧⌘I |
| Format… / Show format bar | ⇧⌘, / ⌥⌘, |
| Move list item up / down | ⌃⌘↑ / ⌃⌘↓ |
| Auto-size window | ⇧⌘/ |
| Hide from screen sharing | ⌘K or View menu (no shortcut) |
| Zoom in / out / actual size | ⌘= / ⌘- / ⌘0 |
| Line break | ⇧↩ |

Every shortcut is defined in `App/MainMenu.swift`.

Markdown input rules: `# `, `## `, `### `, `- ` / `* `, `1. `, `[] ` / `[ ] ` / `- [ ] `,
`> `, ` ``` ` (with an optional language), `---` + ↩, `**bold**`, `*italic*`, `` `code` ``,
`~~strike~~`.

## Data

Notes live in one SQLite database with the same shape as Raycast's `notes` table:

```sql
CREATE TABLE notes (
  id TEXT PRIMARY KEY,             -- ULID
  title TEXT, text TEXT NOT NULL,  -- plain text for search and the title
  raw_content TEXT,                -- ProseMirror/Tiptap-compatible JSON
  pinned REAL, caret_position INTEGER NOT NULL DEFAULT 0,
  created_at TEXT, updated_at TEXT, deleted_at TEXT, last_accessed_at TEXT
) STRICT, WITHOUT ROWID;
```

Storing Tiptap-shaped JSON keeps the door open to importing and exporting Raycast notes.

### Images

Raycast 2.8.2 ships an `image` node (block, atom, draggable; `attachmentId` / `width` /
`height`), but every way of adding one is switched off and its storage is cloud-only. Jot
implements that design locally:

- Files live in `Attachments/<ULID>.<ext>` beside the database, written once (TIFF and BMP
  become PNG), 20 MB max. Notes share files by id (duplicate, copy and paste). Notes are only
  soft-deleted, so files are never removed.
- Display size is Raycast's `min(w, 640, 480·w/h)`, capped to the text width, with 8pt
  corners, 12pt margins (24 between images) and a 2pt secondary-text outline when selected.
- The attachment only reserves space; `BlockLayoutFragment` draws the bitmap from
  `ImageCache`, which decodes off the main thread with ImageIO at the displayed pixel size
  (256px buckets).
- Paste (screenshots, image files), drop files (a 2pt accent bar between blocks), drag to
  reorder or out to Finder, the ⇧⌘I picker, Space or double-click for Quick Look, and a
  context menu and ⌘K section with Quick Look / Copy Image / Save As…. Markdown and plain
  text write `[Image]`, like Raycast.

## Architecture

```
Package.swift              SwiftPM: the JotKit library, the Jot executable and tests
Sources/Jot/main.swift     boots NSApplication
Sources/JotKit/
  App/      JotApp (app delegate, status item, global shortcut, jot:// deeplinks),
            MainMenu (every shortcut), GlobalHotKey (Carbon), Hotkey (the shortcut, its
            display and storage, Raycast's Hyper Key)
  Theme/    Theme (the tokens above), Fonts (bundled Inter + JetBrains Mono), RaycastIcon
  Model/    Blocks (the flat block model), TiptapJSON, Markdown + MarkdownImporter, HTML,
            PlainText (Raycast's text and clipboard flavours), ULID
  Store/    SQLite (a thin sqlite3 wrapper), NotesRepository, AttachmentStore
  Editor/   NoteEditor (commands, input rules, paste, Enter/Backspace/Tab semantics),
            NoteEditor+Images, NoteTextView (NSTextView on TextKit 2), Restyler and
            EditorStyle (semantic attributes → fonts and paragraph styles),
            BlockLayoutFragment (markers, code backgrounds, quote bars, dividers, images),
            DocumentCodec (attributed string ⇄ blocks), ImageBlock, ImageCache, SlashMenu
  Window/   NotesPanel, NotesWindowController, WindowCornerRadius, GlassRecipe, ScreenSharing,
            Bars (header, footer, find bar), Chrome (buttons, glass pill), Toast,
            ProgressiveBlur, CommandMenu (⌘K / ⌘P), MenuSearch, SlashMenuPanel, LinkPopover,
            SettingsWindow
Tests/JotKitTests          editor behaviour, slash menu, codecs, markdown and plain text
scripts/bundle.sh          builds Jot.app (LSUIElement) and ad-hoc signs it
scripts/extract-raycast-icons.py   copies Raycast's icons from your install at build time
```

Key design choices:

- **Semantic attributes, computed presentation.** The text storage carries meaning (block
  kind, indent, checked, marks, link). A restyler derives fonts, colours and paragraph
  styles from it after every edit, so zoom and theme changes are a single pass and the codec
  only reads semantics.
- **One paragraph is one block.** Code blocks are consecutive `code` paragraphs; the layout
  fragment rounds the first and last corners.
- **Custom TextKit 2 layout fragments** draw everything CSS draws with pseudo-elements:
  bullets, numbers, checkboxes, the quote bar, code backgrounds, dividers and images.
- **Main actor by default** (`defaultIsolation(MainActor.self)`). Image decoding and file
  writes are the only work off the main thread.

# Tackboard — Flutter notes & doodles app

A skeuomorphic note-taking app themed around a corkboard ("tackboard"). The
core metaphor is unchanged: print a receipt from a printer, write an
append-only list on it, pin it up, crumple it, throw it, or bin it. Post-it
memos (free text + doodles) are the lighter-weight counterpart.

## Stack & run

- **Flutter** app targeting **macOS, Windows, and iOS**.
- `flutter run -d macos` for local macOS development. Use the matching Flutter
  desktop/mobile target for Windows and iOS.
- Assets live in `assets/` and are registered in `pubspec.yaml`.
- The old React/Next.js/Firebase implementation is no longer the target
  architecture.

## Persistence and sync

- This is a **personal local-first system**. Do not add Firebase hosting,
  Firestore, or browser `localStorage` persistence.
- Runtime state is stored in a local **SQLite** database on each device.
- SyncThing is the intended transport between personal devices. The app should
  cooperate with SyncThing by reading and writing JSON state files in a shared
  sync directory.
- Each device exports its own JSON state file. SyncThing copies those files to
  the other devices. On refresh/startup and after local writes, the app merges
  all visible JSON state files into SQLite, then exports the device's current
  state again.
- Sync is eventually consistent and file-based. Prefer additive metadata
  (`updatedAt`, tombstones/deleted records, per-device IDs) over assumptions
  that two devices update in lockstep.
- Keep the sync folder configurable where the platform permits it. The default
  should be an app documents directory so the app works before SyncThing is
  configured.

## Data model

`Paper = Receipt | Memo`, discriminated by `kind`. Shared fields: `id, x, y, z,
pinned, crumpled, balled, ball, createdAt, updatedAt`. Receipts add list
`items` (append-only, `struck` flag; title rows may be `titleKind: list` or
`titleKind: sublist`), `draft`/`draftLevel`, `tmuxWindowId`, and `bg`+
`bgScale`/`bgX`/`bgY` (a randomized crop/zoom of crumpled1/crumpled2 so each
looks unique without distorting the grain). Memos add `color`, `size`, `text`,
`strokes` (doodles).

SQLite should keep enough metadata to merge JSON files safely. If the `Paper`
shape changes, update the normalizer/decoder and migration path so older JSON
exports and SQLite rows survive schema changes.

## Implemented interactions to preserve

- **Short click/tap** edits a paper.
- **Drag** moves a paper. While dragging on desktop, the paper should feel like
  it hangs from the pointer and swings with damped motion.
- **Drag into the top pin zone** pins the paper with a clip.
- **Long stationary press (~3s)** crumples a paper into a throwable ball that
  stays on the board and is held by the same pointer.
- A held ball follows the pointer. On release it flies with thrown momentum and
  gravity. It can be re-grabbed and re-thrown.
- Landing in the bin catch zone bins the paper and plays confetti. Leaving the
  screen bins it without confetti.
- `crumpled: true` means "in the bin"; `balled: true` means "a throwable ball
  on the board".
- Edit/focus mode centers and scales the edited paper, with a dim/blurred
  backdrop behind it. Backdrop click/tap or Escape exits.

### Receipts

Append-only "permanent ink" list editor, Courier-style monospace:

- **Enter** commits the typed text as a list item.
- **Shift+Enter** on the first row commits the typed text as the top-level list
  title without indenting following items.
- **Tab** turns the typed text into a sub-list *title* and indents following
  items; it is a no-op if there is no typed text.
- **Shift+Tab** outdents one level.
- **Backspace/Delete are disabled** entirely.
- Clicking/tapping an existing non-title item **strikes it through**
  permanently. Title rows are not directly interactive; they strike themselves
  when every non-title item in their list/sub-list is struck.

### Memos

Coloured square post-its (red/green/blue), with larger monospace text than
receipts. No lists. In edit mode: type to add text (Backspace allowed here) and
click/touch-drag to doodle with a fixed dark pen. Created from the cardboard
post-it board, which sits bottom-right just left of the printer, rises on hover,
and opens to reveal the colour picks.

### Bin

The bin peeks bottom-left, rises on hover or when a ball is in play, and opens
the paperbin_top screen. Hold a binned ball to preview/uncrumple it at original
size. Leave and Clear Trash controls are available from the bin screen.

### Printer

The receipt printer sits bottom-right with its tip showing, rises on hover, and
click/tap plays a paper-unroll animation before spawning an editable receipt.

## Current app considerations

- Target platforms are Windows, macOS, and iOS. Keep pointer, touch, keyboard,
  and file-system differences in mind.
- Desktop should expose the full tackboard experience. Narrow/mobile layouts
  should prioritize pinned receipts and red memos, matching the current shipped
  behavior.
- Use the existing raster assets rather than replacing the skeuomorphic look.

## Deferred / not yet built

- Blue post-it login/user accounts.
- Orange post-its.
- Side-screen panning.
- Real clip artwork for pinned papers (currently drawn UI).
- Doodle eraser / pen-colour picker.

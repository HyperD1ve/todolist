# Tackboard

Tackboard is a local-first Flutter notes app built around a corkboard metaphor:
print receipts, write append-only lists, pin them up, crumple them into balls,
throw them into the bin, and keep quick post-it memos with text and doodles.

The app also has an alternate tmux-style view where receipts become panes,
post-its become a scrolling alert strip, and the session has `text` and `trash`
windows.

## Platforms

- macOS
- Windows
- iOS

For local macOS development:

```sh
flutter run -d macos
```

Use the matching Flutter target for Windows or iOS.

## Persistence And Sync

- Runtime state is stored in a local SQLite database.
- SyncThing is the intended cross-device transport.
- Each device exports JSON state files into a configurable sync directory.
- On startup, refresh, and local writes, the app merges visible JSON files into
  SQLite and exports the current device state again.
- The default sync directory is inside the app documents area so the app works
  before SyncThing is configured.
- Tmux window and pane layout is stored locally in SQLite settings as
  `tmux_layout`. Receipt records also carry `tmuxWindowId`, so receipts created
  on the tackboard between tmux sessions open together in a new tmux window.

## Tackboard View

The main view is the skeuomorphic corkboard.

- Short click or tap a paper to edit it.
- Drag a paper to move it.
- Drag into the top pin zone to pin it.
- Long stationary press, about 3 seconds, crumples a paper into a throwable ball.
- Drag and release a held ball to throw it with momentum and gravity.
- A ball landing in the bin catch zone is binned and plays confetti.
- A ball leaving the screen is binned without confetti.
- Escape or backdrop click exits edit mode.
- The `tmux` button switches to the tmux-style view.

## Receipts

Receipts are append-only permanent-ink lists.

- Click the receipt printer to unroll and create a new receipt.
- Type in edit mode to build the current draft line.
- `Enter` commits the draft as a list item.
- `Shift+Enter` on the first row commits the draft as the list title.
- `Tab` commits the draft as a sub-list title and indents following items.
- `Shift+Tab` outdents one level.
- `Backspace` and `Delete` are disabled.
- Click an existing non-title item in edit mode to permanently strike it
  through. Titles strike themselves when every item in their list/sub-list is
  complete.

## Post-It Memos

Post-its are quick notes with optional doodles.

- Open the cardboard post-it board near the printer.
- Pick red, green, or blue to create a memo.
- Type free text in edit mode.
- Backspace is allowed in memos.
- Click or touch-drag in edit mode to doodle with the fixed dark pen.
- In mobile/narrow layouts, pinned receipts and red memos are prioritized.

## Bin

- The bin sits at the lower-left of the tackboard.
- It rises on hover or when a throwable ball is in play.
- Open it to view binned papers.
- Long-press a binned ball to preview the original paper.
- `Clear trash` permanently deletes binned papers.

## Tmux View

The alternate view treats the whole app as a tmux session.

- The session cannot really detach because it is the app.
- `C-b d` returns to the tackboard view.
- There are two baseline windows: `text` and `trash`.
- A pane is a view into one receipt/list.
- Pinned receipt panes stay in their normal windows and are outlined in red.
- Creating a pane creates a new empty receipt-backed list.
- Creating a window creates a new receipt-backed list in its own window.
- Receipts created on the tackboard since the last tmux session open together
  in a brand-new tmux window.
- Post-it memo text scrolls across the top as an alert ticker.
- The tmux layout is persisted in local SQLite.

### Tmux Commands

- `C-b d`: detach back to tackboard.
- `C-b w`: open the window and pane chooser.
- `C-b c`: create a new text window with a new empty list.
- `C-b %`: split the active pane left/right with a new empty list.
- `C-b "`: split the active pane top/bottom with a new empty list.
- `C-b x`: kill the active pane or window. Killed receipt panes go to trash.
- `C-b ,`: rename the current window.
- `C-b n`: next window.
- `C-b p`: previous window.
- `C-b o`: next pane.
- `C-b` plus arrow keys: move pane focus.
- `C-b Space`: clear the selected list item.
- `C-b ?`: show tmux help.

Inside a receipt pane:

- Type to append to the draft line.
- Up and Down arrows move the selected list item.
- `Enter` commits an item.
- `Tab` commits a sub-list title and indents.
- `Shift+Tab` outdents.
- `Backspace` and `Delete` are disabled, matching receipt behavior.

In the `C-b w` chooser:

- Arrow keys or `j`/`k` move selection.
- `Enter` opens the selected window or pane.
- `x` kills the selected window or pane.
- `Esc` closes the chooser.

## Assets

Raster assets live in `assets/` and are registered in `pubspec.yaml`.

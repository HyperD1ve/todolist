# Tackboard — notes & doodles app

A skeuomorphic note-taking app themed around a corkboard ("tackboard"). The
user habitually writes to-do lists on the backs of receipts, so the core
metaphor is: print a receipt from a printer, write an append-only list on it,
pin it up, crumple it, or bin it. Post-it memos (free text + doodles) are the
lighter-weight counterpart.

## Stack & run

- **Next.js 14 (pages router) + TypeScript + Tailwind**.
- `npm run dev` → http://localhost:3000. `npm run build` for prod.
- Assets live in `assets/` (source) and are copied to `public/assets/` (served).
  If you add/replace a sprite, copy it into `public/assets/` too.

## Persistence (important)

- `lib/firebase.ts` only enables Firestore if `NEXT_PUBLIC_FIREBASE_CONFIG`
  (a JSON string) is set **and** valid. Otherwise it stays disabled.
- `lib/usePapers.ts` writes to **Firestore** when enabled, else **localStorage**
  (`tackboard.papers`, migrating the old `tackboard.receipts` key). Writes are
  debounced ~500ms; adds/deletes are immediate.
- Currently **no Firebase env var is set**, so all data is local to the browser.
  A hosted build without that env var keeps each visitor's data in their own
  `localStorage` — it does **not** carry the developer's local data.
- `lib/usePapers.ts#normalize` backfills missing fields so older saved papers
  survive schema changes. Update it whenever the `Paper` shape changes.

## Data model (`lib/types.ts`)

`Paper = Receipt | Memo`, discriminated by `kind`. Shared fields: `id, x, y, z,
pinned, crumpled, ball, createdAt`. Receipts add list `items` (append-only,
`struck` flag), `draft`/`draftLevel`, and `bg`+`bgScale`/`bgX`/`bgY` (a
randomized CSS crop/zoom of crumpled1/crumpled2 so each looks unique without
distorting the grain). Memos add `color`, `size`, `text`, `strokes` (doodles).

## Interactions

Shared gesture/physics live in `lib/useDragPhysics.ts` (used by both
`Receipt` and `Memo`):

- **Short click** → edit. **Drag** → move; while dragging the paper's top-centre
  hangs from the cursor and swings as a damped pendulum (bob lags the pivot, so
  it swings opposite to cursor motion). **Drag into the top 36px** → pin (clip).
  A `e.buttons === 0` guard + `pointercancel` handler prevent the drag state from
  latching onto a hovering cursor.
- **3s stationary press** → the paper crumples into a **ball that stays on the
  board** (`balled` flag) and is grabbed by the same pointer. While held it
  follows the cursor; on release it flies with the **thrown momentum + gravity**
  (`BALL_GRAVITY`). Velocity is estimated from recent pointer samples
  (`VEL_WINDOW`). A ball can be re-grabbed and re-thrown.
  - Lands in the bin's catch zone (`binHit`, bottom-left) → `onLand(id, true)`
    → binned + **confetti** (`components/Confetti.tsx`).
  - Leaves the screen anywhere else (`offscreen`) → `onLand(id, false)` → still
    binned, no confetti.
  - `crumpled: true` means "in the bin"; `balled: true` means "a throwable ball
    on the board". The bin (`PaperBin`) rises while any ball is in play (`alert`).
  - Balls render via `components/BallOnBoard.tsx` (same root element as the
    Receipt/Memo, so pointer capture carries through the crumple→throw gesture).
- **Edit/focus mode** (`lib/focus.ts`): the edited paper translates to viewport
  centre and scales up; a blurred backdrop dims everything else. Click the
  backdrop (or Esc) to leave. Backdrop + focused paper are rendered *inside* the
  board so the blur stacks correctly (a fixed parent traps z-index).

### Receipts (`components/Receipt.tsx`)

Append-only "permanent ink" list editor, Courier New, font 19px:
- **Enter** commits the typed text as a list item.
- **Tab** turns the typed text into a sub-list *title* and indents following
  items; **no-op if there's no typed text**. **Shift+Tab** outdents one level.
- **Backspace/Delete are disabled** entirely.
- Clicking an existing item **strikes it through** (permanent, not undoable).

### Memos (`components/Memo.tsx`)

Coloured square post-its (red/green/blue), font larger than receipts (~32px).
No lists. In edit mode: **type** to add text (Backspace allowed here),
**click-drag** to doodle on a canvas overlay. Created from
`components/PostItBoard.tsx` — the cardboard sits bottom-right just left of the
printer, sits low by default, rises on hover, and opens on click to reveal the
colour picks.

### Bin (`components/PaperBin.tsx` + `components/BinScreen.tsx`)

Bin peeks bottom-left, rises on hover; click opens the paperbin_top screen.
Hold a ball to uncrumple it at its original size. Leave / Clear-trash buttons.

### Printer (`components/ReceiptPrinter.tsx`)

Bottom-right, tip showing, rises on hover. Click plays a paper-unroll animation
out of the slot, *then* spawns the editable receipt.

## Conventions

- Each paper is `position: absolute` on the board; physics rotation is written
  directly to `element.style.transform` via ref (not React state) to avoid
  per-frame re-renders. `transform` is intentionally kept out of the React
  `style` prop except in focus mode — so React never clobbers the ref-driven
  rotation. Be careful preserving this split when editing these components.
- `Receipt`/`Memo` are wrapped in `React.memo`; pass **stable** (memoized)
  callbacks from `pages/index.tsx` so trashing one paper doesn't re-render/move
  the others.

## Deferred / not yet built

- **Blue post-it = login.** Blue memos should accept only `username ENTER
  password ENTER [email ENTER]`: log in if the user exists & password matches;
  create the user if new; reject (blank the post-it) on wrong password or
  invalid email. Needs a Firebase user store. (Currently blue is just a colour.)
- **Orange post-its** (original spec listed red/orange/green/blue; current build
  ships red/green/blue per the latest instruction).
- **Side-screen panning**: hovering the left/right screen edges should pan the
  tackboard to reveal side areas for widgets (none built yet).
- **Real clip** for pinned papers (currently a CSS-drawn clip).
- Doodle eraser / pen-colour picker (pen is fixed dark for now).

export type BgVariant = "crumpled1" | "crumpled2";
export type BallVariant = "ball1" | "ball2" | "ball3";

// A single committed list item on a receipt. `level` is the indentation depth
// (0 = top-level list, 1 = first sub-list, ...). `isTitle` marks an item that
// opened a sub-list beneath it (created by pressing Tab).
export interface ListItem {
  text: string;
  level: number;
  isTitle: boolean;
  struck: boolean; // crossed off (permanent, not undoable)
}

export interface Receipt {
  id: string;
  kind: "receipt";
  bg: BgVariant;
  // A randomized crop/zoom of the bg texture so every receipt looks distinct
  // without distorting the paper grain. bgScale >= 1 (zoom), bgX/bgY are
  // background-position percentages picking which subset of the texture shows.
  bgScale: number;
  bgX: number;
  bgY: number;
  height: number; // rendered height in px
  x: number; // top-left position on the board, in px
  y: number;
  z: number; // stacking order
  pinned: boolean; // clipped to the top of the board
  balled: boolean; // crumpled into a ball that's still on the board (throwable)
  crumpled: boolean; // landed in the bin
  ball: BallVariant; // which crumpled-ball sprite to show
  items: ListItem[]; // committed list items (permanent ink)
  draft: string; // current, not-yet-committed line being typed
  draftLevel: number; // indent level applied to the next committed item
  createdAt: number;
}

export const RECEIPT_WIDTH = 230;
export const RECEIPT_MIN_HEIGHT = 320;
export const RECEIPT_MAX_HEIGHT = 560;

// ---- post-it memos ---------------------------------------------------------

export type MemoColor = "red" | "green" | "blue";

// A freehand doodle stroke (canvas coords relative to the memo's own size).
export interface Stroke {
  color: string;
  points: { x: number; y: number }[];
}

export interface Memo {
  id: string;
  kind: "memo";
  color: MemoColor;
  size: number; // square side length in px
  text: string; // typed text (no lists on memos)
  strokes: Stroke[]; // doodles
  x: number;
  y: number;
  z: number;
  pinned: boolean;
  balled: boolean;
  crumpled: boolean;
  ball: BallVariant;
  createdAt: number;
}

export type Paper = Receipt | Memo;

export const BALL_SIZE = 96;

export const MEMO_SIZE = 210;

export const MEMO_COLORS: Record<MemoColor, string> = {
  red: "#ef6f6f",
  green: "#8fd17a",
  blue: "#7db4ef",
};

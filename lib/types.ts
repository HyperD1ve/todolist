export type BgVariant = "crumpled1" | "crumpled2";
export type BallVariant = "ball1" | "ball2" | "ball3";

// A single committed list item on a receipt. `level` is the indentation depth
// (0 = top-level list, 1 = first sub-list, ...). `isTitle` marks an item that
// opened a sub-list beneath it (created by pressing Tab).
export interface ListItem {
  text: string;
  level: number;
  isTitle: boolean;
}

export interface Receipt {
  id: string;
  kind: "receipt";
  bg: BgVariant;
  height: number; // rendered height in px
  x: number; // top-left position on the board, in px
  y: number;
  z: number; // stacking order
  pinned: boolean; // clipped to the top of the board
  crumpled: boolean; // balled up and thrown into the bin
  ball: BallVariant; // which crumpled-ball sprite to show in the bin
  items: ListItem[]; // committed list items (permanent ink)
  draft: string; // current, not-yet-committed line being typed
  draftLevel: number; // indent level applied to the next committed item
  createdAt: number;
}

export const RECEIPT_WIDTH = 230;
export const RECEIPT_MIN_HEIGHT = 320;
export const RECEIPT_MAX_HEIGHT = 560;

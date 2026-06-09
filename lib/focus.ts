import React from "react";

export const FOCUS_Z = 50001; // above the blur backdrop (see index.tsx)

// When a paper is being edited we translate it from wherever it sits on the
// board to the centre of the viewport and scale it up. Returning these as part
// of the React `style` lets React own `transform` while editing; when editing
// ends and these keys disappear, React clears the transform and the physics
// loop takes the wheel again.
export function focusStyle(
  editing: boolean,
  pos: { x: number; y: number },
  width: number,
  height: number,
  scale: number
): React.CSSProperties {
  if (!editing) return {};
  const vw = typeof window !== "undefined" ? window.innerWidth : 1280;
  const vh = typeof window !== "undefined" ? window.innerHeight : 800;
  // Never zoom past what fits on screen — taller papers then scroll internally.
  const fit = Math.min((vw * 0.92) / width, (vh * 0.92) / height);
  const s = Math.min(scale, fit);
  const dx = vw / 2 - (pos.x + width / 2);
  const dy = vh / 2 - (pos.y + height / 2);
  return {
    transform: `translate(${dx}px, ${dy}px) scale(${s})`,
    transformOrigin: "center center",
    transition: "transform 0.28s cubic-bezier(0.2, 0.8, 0.25, 1)",
    zIndex: FOCUS_Z,
  };
}

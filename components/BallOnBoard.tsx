import React from "react";
import { BallVariant, BALL_SIZE } from "../lib/types";

interface Props {
  rootRef: React.RefObject<HTMLDivElement>;
  handlers: React.HTMLAttributes<HTMLDivElement>;
  pos: { x: number; y: number };
  ball: BallVariant;
  z: number;
}

// A crumpled paper ball sitting on the board, ready to be grabbed and thrown.
export default function BallOnBoard({ rootRef, handlers, pos, ball, z }: Props) {
  return (
    <div
      ref={rootRef}
      className="absolute no-select"
      style={{
        left: pos.x,
        top: pos.y,
        width: BALL_SIZE,
        height: BALL_SIZE,
        zIndex: 40000 + z, // balls fly above ordinary papers
        transformOrigin: "center center",
        touchAction: "none",
        cursor: "grab",
        filter: "drop-shadow(2px 6px 6px rgba(0,0,0,0.4))",
      }}
      {...handlers}
    >
      <img
        src={`/assets/${ball}.png`}
        alt="paper ball"
        draggable={false}
        style={{ width: "100%", height: "100%", objectFit: "contain", pointerEvents: "none" }}
      />
    </div>
  );
}

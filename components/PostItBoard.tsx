import React, { useState } from "react";
import { MemoColor, MEMO_COLORS } from "../lib/types";

const W = 240;
const H = Math.round((W * 654) / 275); // cardboard sprite aspect ratio
const COLORS: MemoColor[] = ["red", "green", "blue"];

interface Props {
  onPick: (color: MemoColor) => void;
}

export default function PostItBoard({ onPick }: Props) {
  const [hover, setHover] = useState(false);
  const [open, setOpen] = useState(false);

  // Peeks from the bottom edge; rises on hover; rises fully when opened. Sits
  // just left of the receipt printer in the bottom-right, lower by default.
  const translate = open ? "14%" : hover ? "52%" : "80%";

  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      onClick={() => setOpen((o) => !o)}
      title="Post-it board"
      className="no-select"
      style={{
        position: "fixed",
        right: 320,
        bottom: 0,
        width: W,
        height: H,
        zIndex: 4800,
        cursor: "pointer",
        transform: `translateY(${translate})`,
        transition: "transform 200ms ease-out",
        backgroundImage: "url(/assets/cardboard_bg.jpg)",
        backgroundSize: "100% 100%",
        borderRadius: 6,
        boxShadow: "0 -6px 16px rgba(0,0,0,0.4)",
      }}
    >
      {/* The colour picks, revealed once the board is open */}
      <div
        style={{
          position: "absolute",
          top: 70,
          left: 0,
          right: 0,
          display: "flex",
          flexDirection: "column",
          alignItems: "center",
          gap: 22,
          opacity: open ? 1 : 0,
          pointerEvents: open ? "auto" : "none",
          transition: "opacity 200ms ease-out",
        }}
      >
        {COLORS.map((c) => (
          <div
            key={c}
            onClick={(e) => {
              e.stopPropagation();
              onPick(c);
              setOpen(false);
            }}
            title={`New ${c} post-it`}
            style={{
              width: 96,
              height: 96,
              background: MEMO_COLORS[c],
              boxShadow: "2px 4px 8px rgba(0,0,0,0.35)",
              transform: "rotate(-2deg)",
              cursor: "pointer",
            }}
          />
        ))}
      </div>

      {!open && (
        <div
          style={{
            position: "absolute",
            top: 8,
            left: 0,
            right: 0,
            textAlign: "center",
            fontFamily: '"Courier New", monospace',
            fontSize: 12,
            color: "#5a4632",
            opacity: hover ? 0.9 : 0,
            transition: "opacity 200ms",
          }}
        >
          post-its
        </div>
      )}
    </div>
  );
}

import React, { useState } from "react";
import { Paper, RECEIPT_WIDTH, MEMO_COLORS } from "../lib/types";

interface Props {
  balls: Paper[];
  onLeave: () => void;
  onClear: () => void;
}

// Stable pseudo-random in [0,1) seeded by a string (so balls keep their spot).
function rand01(seed: string) {
  let h = 2166136261 >>> 0;
  for (let i = 0; i < seed.length; i++) {
    h ^= seed.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return (h >>> 0) / 4294967296;
}

// Scatter a ball at a random point inside the bin's circular opening, centred
// on screen. sqrt() keeps the distribution uniform across the disc.
function scatter(id: string) {
  const vmin =
    typeof window !== "undefined"
      ? Math.min(window.innerWidth, window.innerHeight)
      : 800;
  const angle = rand01(id) * Math.PI * 2;
  const radius = Math.sqrt(rand01(id + "#r")) * vmin * 0.3;
  return { dx: Math.cos(angle) * radius, dy: Math.sin(angle) * radius };
}

// The uncrumpled contents, narrowed per paper kind.
function Preview({ ball }: { ball: Paper }) {
  if (ball.kind === "receipt") {
    return (
      <div
        style={{
          position: "absolute",
          left: "50%",
          top: "50%",
          transform: "translate(-50%, -50%)",
          width: RECEIPT_WIDTH,
          height: ball.height,
          overflow: "auto",
          padding: "22px 18px",
          backgroundImage: `url(/assets/${ball.bg}.jpg)`,
          backgroundSize: `${ball.bgScale * 100}% auto`,
          backgroundPosition: `${ball.bgX}% ${ball.bgY}%`,
          backgroundRepeat: "no-repeat",
          fontFamily: '"Courier New", Courier, monospace',
          fontSize: 19,
          lineHeight: "1.5",
          color: "#222",
          boxShadow: "2px 6px 14px rgba(0,0,0,0.6)",
          zIndex: 20,
        }}
      >
        {ball.items.length === 0 ? (
          <span style={{ opacity: 0.5 }}>(blank)</span>
        ) : (
          ball.items.map((it, i) => (
            <div
              key={i}
              style={{
                marginLeft: it.level * 18,
                fontWeight: it.isTitle ? 700 : 400,
                textDecoration: [
                  it.isTitle ? "underline" : "",
                  it.struck ? "line-through" : "",
                ]
                  .filter(Boolean)
                  .join(" "),
                opacity: it.struck ? 0.55 : 1,
              }}
            >
              {it.isTitle ? it.text : `• ${it.text}`}
            </div>
          ))
        )}
      </div>
    );
  }
  // memo
  return (
    <div
      style={{
        position: "absolute",
        left: "50%",
        top: "50%",
        transform: "translate(-50%, -50%)",
        width: ball.size,
        height: ball.size,
        overflow: "hidden",
        padding: 12,
        background: MEMO_COLORS[ball.color],
        fontFamily: '"Courier New", Courier, monospace',
        fontSize: 32,
        lineHeight: 1.35,
        color: "#222",
        whiteSpace: "pre-wrap",
        wordBreak: "break-word",
        boxShadow: "2px 6px 14px rgba(0,0,0,0.6)",
        zIndex: 20,
      }}
    >
      {ball.text || <span style={{ opacity: 0.5 }}>(blank)</span>}
    </div>
  );
}

function BallView({ ball, pos }: { ball: Paper; pos: ReturnType<typeof scatter> }) {
  const [open, setOpen] = useState(false);
  return (
    <div
      className="no-select"
      style={{
        position: "absolute",
        left: "50%",
        top: "50%",
        transform: `translate(calc(-50% + ${pos.dx}px), calc(-50% + ${pos.dy}px))`,
        width: 90,
        height: 90,
        cursor: "grab",
        touchAction: "none",
      }}
      onPointerDown={(e) => {
        e.preventDefault();
        setOpen(true);
      }}
      onPointerUp={() => setOpen(false)}
      onPointerLeave={() => setOpen(false)}
      title="Hold to uncrumple"
    >
      {open ? (
        <Preview ball={ball} />
      ) : (
        <img
          src={`/assets/${ball.ball}.png`}
          alt="crumpled paper"
          draggable={false}
          style={{ width: "100%", height: "100%", objectFit: "contain" }}
        />
      )}
    </div>
  );
}

export default function BinScreen({ balls, onLeave, onClear }: Props) {
  return (
    <div
      style={{
        position: "fixed",
        inset: 0,
        zIndex: 8000,
        background: "#2b2b2b",
        backgroundImage: "url(/assets/paperbin_top.png)",
        backgroundSize: "min(90vh, 90vw) auto",
        backgroundPosition: "center",
        backgroundRepeat: "no-repeat",
      }}
    >
      {balls.map((b) => (
        <BallView key={b.id} ball={b} pos={scatter(b.id)} />
      ))}

      <div style={{ position: "fixed", top: 20, left: 20, display: "flex", gap: 12 }}>
        <button
          onClick={onLeave}
          style={{
            padding: "10px 18px",
            fontFamily: '"Courier New", monospace',
            fontWeight: 700,
            background: "#f5f5f0",
            border: "2px solid #333",
            borderRadius: 6,
            cursor: "pointer",
          }}
        >
          ← Leave
        </button>
        <button
          onClick={onClear}
          disabled={balls.length === 0}
          style={{
            padding: "10px 18px",
            fontFamily: '"Courier New", monospace',
            fontWeight: 700,
            background: balls.length === 0 ? "#999" : "#c0392b",
            color: "#fff",
            border: "2px solid #333",
            borderRadius: 6,
            cursor: balls.length === 0 ? "default" : "pointer",
          }}
        >
          Clear trash
        </button>
      </div>

      {balls.length === 0 && (
        <div
          style={{
            position: "fixed",
            top: "50%",
            left: "50%",
            transform: "translate(-50%, -50%)",
            color: "#eee",
            fontFamily: '"Courier New", monospace',
            opacity: 0.7,
          }}
        >
          The bin is empty.
        </div>
      )}
    </div>
  );
}

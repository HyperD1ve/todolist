import React, { useState } from "react";
import { Receipt } from "../lib/types";

interface Props {
  balls: Receipt[];
  onLeave: () => void;
  onClear: () => void;
}

// Deterministic-ish scatter so balls keep their spot between renders.
function scatter(i: number) {
  const cols = 4;
  const col = i % cols;
  const row = Math.floor(i / cols);
  const jitterX = ((i * 53) % 40) - 20;
  const jitterY = ((i * 31) % 36) - 18;
  return {
    left: `${18 + col * 18}%`,
    top: `${24 + row * 20}%`,
    x: jitterX,
    y: jitterY,
  };
}

function BallView({ ball, pos }: { ball: Receipt; pos: ReturnType<typeof scatter> }) {
  const [open, setOpen] = useState(false);
  return (
    <div
      className="no-select"
      style={{
        position: "absolute",
        left: pos.left,
        top: pos.top,
        transform: `translate(${pos.x}px, ${pos.y}px)`,
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
        <div
          style={{
            width: 150,
            maxHeight: 220,
            overflow: "auto",
            transform: "translate(-30px, -60px)",
            padding: "14px 12px",
            backgroundImage: `url(/assets/${ball.bg}.jpg)`,
            backgroundSize: "100% 100%",
            fontFamily: '"Courier New", Courier, monospace',
            fontSize: 11,
            color: "#222",
            boxShadow: "2px 6px 10px rgba(0,0,0,0.5)",
          }}
        >
          {ball.items.length === 0 ? (
            <span style={{ opacity: 0.5 }}>(blank)</span>
          ) : (
            ball.items.map((it, i) => (
              <div
                key={i}
                style={{
                  marginLeft: it.level * 12,
                  fontWeight: it.isTitle ? 700 : 400,
                  textDecoration: it.isTitle ? "underline" : "none",
                }}
              >
                {it.isTitle ? it.text : `• ${it.text}`}
              </div>
            ))
          )}
        </div>
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
      {balls.map((b, i) => (
        <BallView key={b.id} ball={b} pos={scatter(i)} />
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

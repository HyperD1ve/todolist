import React, { useMemo } from "react";

const COLORS = ["#ef6f6f", "#8fd17a", "#7db4ef", "#f4d35e", "#d291ff", "#ffffff"];

interface Props {
  // Burst origin in viewport px (defaults to the bin, bottom-left).
  x?: number;
  y?: number;
  count?: number;
}

// A one-shot confetti burst. Remount (change `key`) to replay.
export default function Confetti({ x = 110, y, count = 28 }: Props) {
  const bits = useMemo(() => {
    const vh = typeof window !== "undefined" ? window.innerHeight : 800;
    const oy = y ?? vh - 120;
    return Array.from({ length: count }, (_, i) => {
      const ang = (Math.PI * (0.15 + Math.random() * 0.7)); // mostly upward fan
      const dist = 80 + Math.random() * 160;
      const dx = Math.cos(ang) * dist * (Math.random() < 0.5 ? -1 : 1);
      const dy = -Math.sin(ang) * dist - Math.random() * 60;
      return {
        i,
        left: x + (Math.random() * 40 - 20),
        top: oy + (Math.random() * 30 - 15),
        dx,
        dy,
        r: Math.random() * 720 - 360,
        color: COLORS[i % COLORS.length],
        delay: Math.random() * 0.08,
      };
    });
  }, [x, y, count]);

  return (
    <div style={{ position: "fixed", inset: 0, zIndex: 60000, pointerEvents: "none" }}>
      {bits.map((b) => (
        <div
          key={b.i}
          className="confetti-bit"
          style={
            {
              left: b.left,
              top: b.top,
              background: b.color,
              animationDelay: `${b.delay}s`,
              "--dx": `${b.dx}px`,
              "--dy": `${b.dy}px`,
              "--r": `${b.r}deg`,
            } as React.CSSProperties
          }
        />
      ))}
    </div>
  );
}

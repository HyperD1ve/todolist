import React, { useState } from "react";

const W = 150;
const H = Math.round((W * 857) / 718); // sprite aspect ratio

interface Props {
  count: number; // how many balls are in the bin
  onOpen: () => void;
}

export default function PaperBin({ count, onOpen }: Props) {
  const [hover, setHover] = useState(false);

  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      onClick={onOpen}
      title="Open the bin"
      className="no-select"
      style={{
        position: "fixed",
        left: 28,
        bottom: 0,
        width: W,
        height: H,
        zIndex: 5000,
        cursor: "pointer",
        transform: `translateY(${hover ? "30%" : "55%"})`,
        transition: "transform 180ms ease-out",
      }}
    >
      <img
        src="/assets/paperbin_side.png"
        alt="paper bin"
        draggable={false}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "contain",
          filter: "drop-shadow(0 -4px 10px rgba(0,0,0,0.35))",
        }}
      />
      {count > 0 && (
        <div
          style={{
            position: "absolute",
            top: 6,
            right: 6,
            minWidth: 22,
            height: 22,
            padding: "0 6px",
            borderRadius: 11,
            background: "#c0392b",
            color: "#fff",
            fontSize: 12,
            fontWeight: 700,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          {count}
        </div>
      )}
    </div>
  );
}

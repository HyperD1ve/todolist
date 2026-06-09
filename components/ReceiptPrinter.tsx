import React, { useState } from "react";

const W = 280;
const H = Math.round((W * 461) / 541); // keep the sprite's aspect ratio

interface Props {
  onPrint: () => void;
}

export default function ReceiptPrinter({ onPrint }: Props) {
  const [hover, setHover] = useState(false);
  const [printing, setPrinting] = useState(false);

  const handleClick = () => {
    if (printing) return;
    setPrinting(true);
    onPrint();
    setTimeout(() => setPrinting(false), 600);
  };

  return (
    <div
      onMouseEnter={() => setHover(true)}
      onMouseLeave={() => setHover(false)}
      onClick={handleClick}
      title="Print a new receipt"
      className="no-select"
      style={{
        position: "fixed",
        right: 28,
        bottom: 0,
        width: W,
        height: H,
        zIndex: 5000,
        cursor: "pointer",
        // Mostly tucked below the edge; only the slotted tip pokes out. Rises
        // on hover; dips slightly on the click "print" beat.
        transform: `translateY(${hover ? (printing ? "42%" : "30%") : "62%"})`,
        transition: "transform 180ms ease-out",
      }}
    >
      <img
        src="/assets/receipt_printer.png"
        alt="receipt printer"
        draggable={false}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "contain",
          filter: "drop-shadow(0 -4px 10px rgba(0,0,0,0.35))",
        }}
      />
    </div>
  );
}

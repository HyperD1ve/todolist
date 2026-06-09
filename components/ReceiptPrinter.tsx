import React, { useState } from "react";

const W = 280;
const H = Math.round((W * 461) / 541); // keep the sprite's aspect ratio
const SLOT_FROM_TOP = 78; // approx. y of the paper slot within the sprite

interface Props {
  onPrint: () => void;
}

export default function ReceiptPrinter({ onPrint }: Props) {
  const [hover, setHover] = useState(false);
  const [emerging, setEmerging] = useState(false);

  const handleClick = () => {
    if (emerging) return;
    setEmerging(true); // play the print animation first…
  };

  const onPaperDone = () => {
    setEmerging(false);
    onPrint(); // …then the real, editable receipt appears
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
        // on hover so you can reach the slot.
        transform: `translateY(${hover || emerging ? "30%" : "62%"})`,
        transition: "transform 180ms ease-out",
      }}
    >
      {/* Blank receipt unrolling out of the slot */}
      {emerging && (
        <div
          className="paper-out"
          onAnimationEnd={onPaperDone}
          style={{
            position: "absolute",
            left: "50%",
            bottom: H - SLOT_FROM_TOP,
            transformOrigin: "bottom center",
            width: 150,
            height: 150,
            zIndex: 4,
            background:
              "repeating-linear-gradient(#fbfbf7, #fbfbf7 22px, #ececdf 23px)",
            borderRadius: "2px 2px 4px 4px",
            boxShadow: "0 -3px 8px rgba(0,0,0,0.25)",
          }}
        />
      )}

      <img
        src="/assets/receipt_printer.png"
        alt="receipt printer"
        draggable={false}
        style={{
          position: "relative",
          zIndex: 3,
          width: "100%",
          height: "100%",
          objectFit: "contain",
          filter: "drop-shadow(0 -4px 10px rgba(0,0,0,0.35))",
          pointerEvents: "none",
        }}
      />
    </div>
  );
}

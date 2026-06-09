import React, { useEffect, useRef, useState } from "react";
import { ListItem, Receipt as ReceiptT, RECEIPT_WIDTH } from "../lib/types";

const CRUMPLE_MS = 3000; // long-press duration to crumple
const DRAG_THRESHOLD = 5; // px of movement before a press becomes a drag
const PIN_ZONE = 36; // drop within this many px of the top => pin

interface Props {
  receipt: ReceiptT;
  editing: boolean;
  boardRef: React.RefObject<HTMLDivElement>;
  onStartEdit: (id: string) => void;
  onStopEdit: () => void;
  onUpdate: (id: string, patch: Partial<ReceiptT>, persist?: boolean) => void;
  onCrumple: (id: string) => void;
  bringToFront: (id: string) => number;
}

export default function Receipt({
  receipt,
  editing,
  boardRef,
  onStartEdit,
  onStopEdit,
  onUpdate,
  onCrumple,
  bringToFront,
}: Props) {
  const [falling, setFalling] = useState(false);
  const editorRef = useRef<HTMLDivElement>(null);

  // Gesture bookkeeping for the pointer interaction (click vs drag vs hold).
  const gesture = useRef({
    down: false,
    moved: false,
    startX: 0,
    startY: 0,
    originX: 0,
    originY: 0,
    pointerId: 0,
    crumbleTimer: 0 as ReturnType<typeof setTimeout> | number,
  });

  useEffect(() => {
    if (editing) editorRef.current?.focus();
  }, [editing]);

  // ---- pointer gesture handling -------------------------------------------

  const clearCrumbleTimer = () => {
    if (gesture.current.crumbleTimer) {
      clearTimeout(gesture.current.crumbleTimer as number);
      gesture.current.crumbleTimer = 0;
    }
  };

  const startCrumple = () => {
    clearCrumbleTimer();
    setFalling(true); // triggers the fall-away animation
  };

  const onPointerDown = (e: React.PointerEvent) => {
    if (editing || falling) return;
    e.preventDefault();
    const g = gesture.current;
    g.down = true;
    g.moved = false;
    g.startX = e.clientX;
    g.startY = e.clientY;
    g.originX = receipt.x;
    g.originY = receipt.y;
    g.pointerId = e.pointerId;
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    bringToFront(receipt.id);
    // Stationary long-press => crumple.
    g.crumbleTimer = setTimeout(startCrumple, CRUMPLE_MS);
  };

  const onPointerMove = (e: React.PointerEvent) => {
    const g = gesture.current;
    if (!g.down) return;
    const dx = e.clientX - g.startX;
    const dy = e.clientY - g.startY;
    if (!g.moved && Math.hypot(dx, dy) > DRAG_THRESHOLD) {
      g.moved = true;
      clearCrumbleTimer(); // movement cancels the crumple hold
    }
    if (g.moved) {
      onUpdate(
        receipt.id,
        { x: g.originX + dx, y: g.originY + dy, pinned: false },
        false
      );
    }
  };

  const onPointerUp = (e: React.PointerEvent) => {
    const g = gesture.current;
    if (!g.down) return;
    g.down = false;
    clearCrumbleTimer();
    try {
      (e.currentTarget as HTMLElement).releasePointerCapture(g.pointerId);
    } catch {}

    if (!g.moved) {
      // A short, stationary click => edit.
      onStartEdit(receipt.id);
      return;
    }

    // Was a drag — decide whether it lands in the pin zone at the top.
    const board = boardRef.current?.getBoundingClientRect();
    const dropY = g.originY + (e.clientY - g.startY);
    const dropX = g.originX + (e.clientX - g.startX);
    const pinned = dropY <= PIN_ZONE;
    onUpdate(
      receipt.id,
      {
        x: dropX,
        y: pinned ? 8 : dropY,
        pinned,
      },
      true
    );
    void board;
  };

  // ---- list editor key handling -------------------------------------------

  const handleKeyDown = (e: React.KeyboardEvent) => {
    // Ink is permanent: deletion is disabled entirely.
    if (e.key === "Backspace" || e.key === "Delete") {
      e.preventDefault();
      return;
    }

    if (e.key === "Enter") {
      e.preventDefault();
      const text = receipt.draft.trim();
      if (!text) return; // nothing to commit
      const item: ListItem = {
        text,
        level: receipt.draftLevel,
        isTitle: false,
      };
      onUpdate(receipt.id, { items: [...receipt.items, item], draft: "" });
      return;
    }

    if (e.key === "Tab") {
      e.preventDefault();
      if (e.shiftKey) {
        // Step back out one sub-list level.
        onUpdate(receipt.id, {
          draftLevel: Math.max(0, receipt.draftLevel - 1),
        });
        return;
      }
      const text = receipt.draft.trim();
      if (text) {
        // Preceding text becomes the sub-list title; following items indent.
        const title: ListItem = {
          text,
          level: receipt.draftLevel,
          isTitle: true,
        };
        onUpdate(receipt.id, {
          items: [...receipt.items, title],
          draft: "",
          draftLevel: receipt.draftLevel + 1,
        });
      } else {
        onUpdate(receipt.id, { draftLevel: receipt.draftLevel + 1 });
      }
      return;
    }

    if (e.key === "Escape") {
      e.preventDefault();
      onStopEdit();
      return;
    }

    // Printable single characters get appended to the draft line.
    if (e.key.length === 1 && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      onUpdate(receipt.id, { draft: receipt.draft + e.key });
    }
  };

  // ---- render --------------------------------------------------------------

  const onAnimEnd = () => {
    if (falling) onCrumple(receipt.id);
  };

  return (
    <div
      className={`absolute no-select ${falling ? "fall-away" : ""}`}
      style={{
        left: receipt.x,
        top: receipt.y,
        width: RECEIPT_WIDTH,
        height: receipt.height,
        zIndex: receipt.pinned ? 9000 + receipt.z : receipt.z,
        touchAction: "none",
        cursor: editing ? "text" : "grab",
        filter: "drop-shadow(2px 6px 6px rgba(0,0,0,0.35))",
      }}
      onPointerDown={onPointerDown}
      onPointerMove={onPointerMove}
      onPointerUp={onPointerUp}
      onAnimationEnd={onAnimEnd}
    >
      {/* Pin / clip when fastened to the top of the board */}
      {receipt.pinned && (
        <div
          style={{
            position: "absolute",
            top: -14,
            left: "50%",
            transform: "translateX(-50%)",
            width: 26,
            height: 34,
            borderRadius: 6,
            border: "3px solid #8a8f98",
            background:
              "linear-gradient(180deg, #d9dde3 0%, #aab0b9 60%, #c7ccd3 100%)",
            zIndex: 2,
          }}
          title="Pinned to the top"
        />
      )}

      <div
        ref={editorRef}
        tabIndex={editing ? 0 : -1}
        onKeyDown={editing ? handleKeyDown : undefined}
        style={{
          width: "100%",
          height: "100%",
          padding: "22px 18px",
          overflowY: "auto",
          outline: "none",
          backgroundImage: `url(/assets/${receipt.bg}.jpg)`,
          backgroundSize: "100% 100%",
          fontFamily: '"Courier New", Courier, monospace',
          fontSize: 13,
          lineHeight: "1.5",
          color: "#222",
          boxShadow: editing ? "inset 0 0 0 2px rgba(40,90,200,0.5)" : "none",
        }}
      >
        {receipt.items.map((it, i) => (
          <div
            key={i}
            style={{
              marginLeft: it.level * 16,
              fontWeight: it.isTitle ? 700 : 400,
              textDecoration: it.isTitle ? "underline" : "none",
              whiteSpace: "pre-wrap",
              wordBreak: "break-word",
            }}
          >
            {it.isTitle ? it.text : `• ${it.text}`}
          </div>
        ))}

        {/* The live draft line being typed (only meaningful while editing) */}
        {(editing || receipt.draft) && (
          <div
            style={{
              marginLeft: receipt.draftLevel * 16,
              whiteSpace: "pre-wrap",
              wordBreak: "break-word",
              opacity: receipt.draft || editing ? 1 : 0.4,
            }}
          >
            {receipt.draft}
            {editing && <span className="caret-blink">▌</span>}
          </div>
        )}

        {editing && receipt.items.length === 0 && !receipt.draft && (
          <div style={{ opacity: 0.45, fontSize: 11, marginTop: 6 }}>
            type… Enter = list item · Tab = sub-list · no deleting
          </div>
        )}
      </div>
    </div>
  );
}

import React, { useEffect, useRef } from "react";
import { ListItem, Receipt as ReceiptT, RECEIPT_WIDTH } from "../lib/types";
import { useDragPhysics } from "../lib/useDragPhysics";
import { focusStyle } from "../lib/focus";
import BallOnBoard from "./BallOnBoard";

const FONT_SIZE = 19; // ~50% larger than the original 13px
const FOCUS_SCALE = 1.5;

interface Props {
  receipt: ReceiptT;
  editing: boolean;
  boardRef: React.RefObject<HTMLDivElement>;
  onStartEdit: (id: string) => void;
  onStopEdit: () => void;
  onUpdate: (id: string, patch: Partial<ReceiptT>, persist?: boolean) => void;
  onBall: (id: string) => void;
  onLand: (id: string, hitBin: boolean) => void;
  bringToFront: (id: string) => number;
  mobileImportant?: boolean;
}

function Receipt({
  receipt,
  editing,
  boardRef,
  onStartEdit,
  onStopEdit,
  onUpdate,
  onBall,
  onLand,
  bringToFront,
  mobileImportant = false,
}: Props) {
  const editorRef = useRef<HTMLDivElement>(null);
  const draftInputRef = useRef<HTMLTextAreaElement>(null);

  const { pos, rootRef, dragHandlers } = useDragPhysics({
    id: receipt.id,
    width: RECEIPT_WIDTH,
    height: receipt.height,
    x: receipt.x,
    y: receipt.y,
    editing,
    balled: receipt.balled,
    boardRef,
    onUpdate,
    onBall,
    onLand,
    onStartEdit,
    bringToFront,
  });

  useEffect(() => {
    if (!editing) return;
    if (mobileImportant) {
      draftInputRef.current?.focus();
      return;
    }
    editorRef.current?.focus();
  }, [editing, mobileImportant]);

  // All hooks must run before this early return (React error #300 otherwise).
  if (receipt.balled) {
    return (
      <BallOnBoard
        rootRef={rootRef}
        handlers={dragHandlers}
        pos={pos}
        ball={receipt.ball}
        z={receipt.z}
      />
    );
  }

  // ---- list editor key handling -------------------------------------------

  const commitDraft = () => {
    const text = receipt.draft.trim();
    if (!text) return;
    const item: ListItem = {
      text,
      level: receipt.draftLevel,
      isTitle: false,
      struck: false,
    };
    onUpdate(receipt.id, { items: [...receipt.items, item], draft: "" });
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Backspace" || e.key === "Delete") {
      e.preventDefault(); // permanent ink: no deleting
      return;
    }

    if (e.key === "Enter") {
      e.preventDefault();
      commitDraft();
      return;
    }

    if (e.key === "Tab") {
      e.preventDefault();
      if (e.shiftKey) {
        onUpdate(receipt.id, {
          draftLevel: Math.max(0, receipt.draftLevel - 1),
        });
        return;
      }
      const text = receipt.draft.trim();
      if (!text) return; // no-op unless there's text to title the sub-list
      const title: ListItem = {
        text,
        level: receipt.draftLevel,
        isTitle: true,
        struck: false,
      };
      onUpdate(receipt.id, {
        items: [...receipt.items, title],
        draft: "",
        draftLevel: receipt.draftLevel + 1,
      });
      return;
    }

    if (e.key === "Escape") {
      e.preventDefault();
      onStopEdit();
      return;
    }

    if (e.key.length === 1 && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      onUpdate(receipt.id, { draft: receipt.draft + e.key });
    }
  };

  const handleMobileDraftKeyDown = (
    e: React.KeyboardEvent<HTMLTextAreaElement>
  ) => {
    if (e.key === "Backspace" || e.key === "Delete") {
      e.preventDefault();
      return;
    }
    if (e.key === "Enter") {
      e.preventDefault();
      commitDraft();
      return;
    }
    if (e.key === "Escape") {
      e.preventDefault();
      onStopEdit();
    }
  };

  const handleMobileDraftChange = (
    e: React.ChangeEvent<HTMLTextAreaElement>
  ) => {
    const next = e.currentTarget.value;
    if (next.length >= receipt.draft.length) {
      onUpdate(receipt.id, { draft: next });
    }
  };

  const strikeItem = (index: number) => {
    const item = receipt.items[index];
    if (!item || item.struck) return; // not undoable
    const items = receipt.items.map((it, i) =>
      i === index ? { ...it, struck: true } : it
    );
    onUpdate(receipt.id, { items });
  };

  const rootHandlers = mobileImportant
    ? {
        onPointerDown: !editing
          ? (e: React.PointerEvent<HTMLDivElement>) => {
              e.stopPropagation();
              onStartEdit(receipt.id);
            }
          : undefined,
      }
    : dragHandlers;

  return (
    <div
      ref={rootRef}
      className={mobileImportant ? "no-select" : "absolute no-select"}
      style={{
        position: mobileImportant ? "relative" : undefined,
        left: mobileImportant ? undefined : pos.x,
        top: mobileImportant ? undefined : pos.y,
        width: mobileImportant ? `min(100%, ${RECEIPT_WIDTH}px)` : RECEIPT_WIDTH,
        height:
          mobileImportant && editing
            ? `min(${receipt.height}px, calc(100dvh - 72px))`
            : receipt.height,
        zIndex: receipt.pinned ? 9000 + receipt.z : receipt.z,
        transformOrigin: "top center",
        touchAction: mobileImportant ? "manipulation" : "none",
        cursor: editing ? "default" : mobileImportant ? "pointer" : "grab",
        filter: "drop-shadow(2px 6px 6px rgba(0,0,0,0.35))",
        ...(!mobileImportant
          ? focusStyle(editing, pos, RECEIPT_WIDTH, receipt.height, FOCUS_SCALE)
          : {}),
      }}
      {...rootHandlers}
    >
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
          backgroundSize: `${receipt.bgScale * 100}% auto`,
          backgroundPosition: `${receipt.bgX}% ${receipt.bgY}%`,
          backgroundRepeat: "no-repeat",
          fontFamily: '"Courier New", Courier, monospace',
          fontSize: FONT_SIZE,
          lineHeight: "1.5",
          color: "#222",
          boxShadow: editing ? "inset 0 0 0 2px rgba(40,90,200,0.5)" : "none",
        }}
      >
        {receipt.items.map((it, i) => (
          <div
            key={i}
            onClick={
              editing
                ? (e) => {
                    e.stopPropagation();
                    strikeItem(i);
                  }
                : undefined
            }
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
              cursor: editing ? "pointer" : "inherit",
              whiteSpace: "pre-wrap",
              wordBreak: "break-word",
            }}
          >
            {it.isTitle ? it.text : `• ${it.text}`}
          </div>
        ))}

        {(editing || receipt.draft) && (
          <div
            style={{
              marginLeft: receipt.draftLevel * 18,
              whiteSpace: "pre-wrap",
              wordBreak: "break-word",
              opacity: receipt.draft || editing ? 1 : 0.4,
            }}
          >
            {mobileImportant && editing ? (
              <textarea
                ref={draftInputRef}
                value={receipt.draft}
                onChange={handleMobileDraftChange}
                onKeyDown={handleMobileDraftKeyDown}
                rows={1}
                autoCapitalize="sentences"
                spellCheck
                style={{
                  display: "inline-block",
                  width: "100%",
                  minHeight: FONT_SIZE * 1.6,
                  padding: 0,
                  margin: 0,
                  border: 0,
                  outline: "none",
                  resize: "none",
                  overflow: "hidden",
                  background: "transparent",
                  font: "inherit",
                  lineHeight: "inherit",
                  color: "inherit",
                  whiteSpace: "pre-wrap",
                  wordBreak: "break-word",
                }}
              />
            ) : (
              <>
                {receipt.draft}
                {editing && <span className="caret-blink">▌</span>}
              </>
            )}
          </div>
        )}

        {editing && receipt.items.length === 0 && !receipt.draft && (
          <div style={{ opacity: 0.45, fontSize: 12, marginTop: 6 }}>
            type… Enter = item · Tab = sub-list · click an item to cross it off ·
            no deleting
          </div>
        )}
      </div>
    </div>
  );
}

export default React.memo(Receipt);

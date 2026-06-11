import React, { useEffect, useRef } from "react";
import { Memo as MemoT, MEMO_COLORS } from "../lib/types";
import { useDragPhysics } from "../lib/useDragPhysics";
import { focusStyle } from "../lib/focus";
import BallOnBoard from "./BallOnBoard";

const FOCUS_SCALE = 2.1;
const MEMO_FONT = 32; // post-it text is larger than receipts (~100% bigger)
const PEN = "#2a2a2a";
const PEN_WIDTH = 3;

interface Props {
  memo: MemoT;
  editing: boolean;
  boardRef: React.RefObject<HTMLDivElement>;
  onStartEdit: (id: string) => void;
  onStopEdit: () => void;
  onUpdate: (id: string, patch: Partial<MemoT>, persist?: boolean) => void;
  onBall: (id: string) => void;
  onLand: (id: string, hitBin: boolean) => void;
  bringToFront: (id: string) => number;
  mobileImportant?: boolean;
}

function Memo({
  memo,
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
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const drawing = useRef<{ active: boolean; points: { x: number; y: number }[] }>(
    { active: false, points: [] }
  );

  const { pos, rootRef, dragHandlers } = useDragPhysics({
    id: memo.id,
    width: memo.size,
    height: memo.size,
    x: memo.x,
    y: memo.y,
    editing,
    balled: memo.balled,
    boardRef,
    onUpdate,
    onBall,
    onLand,
    onStartEdit,
    bringToFront,
  });

  useEffect(() => {
    if (editing) rootRef.current?.focus();
  }, [editing, rootRef]);

  // Redraw all committed strokes whenever they change.
  useEffect(() => {
    const c = canvasRef.current;
    if (!c) return;
    const ctx = c.getContext("2d");
    if (!ctx) return;
    ctx.clearRect(0, 0, c.width, c.height);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";
    for (const s of memo.strokes) {
      ctx.strokeStyle = s.color;
      ctx.lineWidth = PEN_WIDTH;
      ctx.beginPath();
      s.points.forEach((p, i) =>
        i === 0 ? ctx.moveTo(p.x, p.y) : ctx.lineTo(p.x, p.y)
      );
      ctx.stroke();
    }
  }, [memo.strokes, memo.size]);

  // All hooks must run before this early return (React error #300 otherwise).
  if (memo.balled) {
    return (
      <BallOnBoard
        rootRef={rootRef}
        handlers={dragHandlers}
        pos={pos}
        ball={memo.ball}
        z={memo.z}
      />
    );
  }

  // ---- drawing (only while editing) ---------------------------------------

  const toCanvas = (clientX: number, clientY: number) => {
    const c = canvasRef.current!;
    const rect = c.getBoundingClientRect();
    return {
      x: ((clientX - rect.left) * c.width) / rect.width,
      y: ((clientY - rect.top) * c.height) / rect.height,
    };
  };

  const drawDown = (e: React.PointerEvent) => {
    e.preventDefault();
    (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    drawing.current = { active: true, points: [toCanvas(e.clientX, e.clientY)] };
  };

  const drawMove = (e: React.PointerEvent) => {
    if (!drawing.current.active) return;
    const pt = toCanvas(e.clientX, e.clientY);
    const pts = drawing.current.points;
    pts.push(pt);
    const ctx = canvasRef.current?.getContext("2d");
    if (ctx && pts.length >= 2) {
      const a = pts[pts.length - 2];
      ctx.strokeStyle = PEN;
      ctx.lineWidth = PEN_WIDTH;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(pt.x, pt.y);
      ctx.stroke();
    }
  };

  const drawUp = () => {
    if (!drawing.current.active) return;
    const points = drawing.current.points;
    drawing.current = { active: false, points: [] };
    if (points.length === 0) return;
    onUpdate(memo.id, { strokes: [...memo.strokes, { color: PEN, points }] });
  };

  const handleKeyDown = (e: React.KeyboardEvent) => {
    if (e.key === "Enter") {
      e.preventDefault();
      onUpdate(memo.id, { text: memo.text + "\n" });
      return;
    }
    if (e.key === "Backspace") {
      e.preventDefault();
      onUpdate(memo.id, { text: memo.text.slice(0, -1) });
      return;
    }
    if (e.key === "Escape") {
      e.preventDefault();
      onStopEdit();
      return;
    }
    if (e.key.length === 1 && !e.metaKey && !e.ctrlKey) {
      e.preventDefault();
      onUpdate(memo.id, { text: memo.text + e.key });
    }
  };

  const editHandlers = editing
    ? {
        onPointerDown: drawDown,
        onPointerMove: drawMove,
        onPointerUp: drawUp,
        onPointerCancel: drawUp,
      }
    : dragHandlers;

  return (
    <div
      ref={rootRef}
      tabIndex={editing ? 0 : -1}
      className={mobileImportant ? "no-select" : "absolute no-select"}
      style={{
        position: mobileImportant ? "relative" : undefined,
        left: mobileImportant ? undefined : pos.x,
        top: mobileImportant ? undefined : pos.y,
        width: memo.size,
        height: memo.size,
        zIndex: memo.pinned ? 9000 + memo.z : memo.z,
        transformOrigin: "top center",
        touchAction: mobileImportant ? "auto" : "none",
        outline: "none",
        cursor: mobileImportant ? "default" : editing ? "crosshair" : "grab",
        background: MEMO_COLORS[memo.color],
        boxShadow: editing
          ? "inset 0 0 0 2px rgba(40,90,200,0.5), 2px 6px 10px rgba(0,0,0,0.3)"
          : "2px 6px 10px rgba(0,0,0,0.3)",
        ...(!mobileImportant
          ? focusStyle(editing, pos, memo.size, memo.size, FOCUS_SCALE)
          : {}),
      }}
      {...(!mobileImportant ? editHandlers : {})}
      onKeyDown={!mobileImportant && editing ? handleKeyDown : undefined}
    >
      {memo.pinned && (
        <div
          style={{
            position: "absolute",
            top: -12,
            left: "50%",
            transform: "translateX(-50%)",
            width: 22,
            height: 30,
            borderRadius: 5,
            border: "3px solid #8a8f98",
            background:
              "linear-gradient(180deg, #d9dde3 0%, #aab0b9 60%, #c7ccd3 100%)",
            zIndex: 3,
          }}
        />
      )}

      {/* typed text */}
      <div
        style={{
          position: "absolute",
          inset: 0,
          padding: 12,
          fontFamily: '"Courier New", Courier, monospace',
          fontSize: MEMO_FONT,
          lineHeight: 1.35,
          color: "#222",
          whiteSpace: "pre-wrap",
          wordBreak: "break-word",
          pointerEvents: "none",
        }}
      >
        {memo.text}
        {editing && <span className="caret-blink">▌</span>}
      </div>

      {/* doodle layer */}
      <canvas
        ref={canvasRef}
        width={memo.size}
        height={memo.size}
        style={{
          position: "absolute",
          inset: 0,
          width: "100%",
          height: "100%",
          pointerEvents: "none",
        }}
      />
    </div>
  );
}

export default React.memo(Memo);

import React, { useCallback, useRef, useState } from "react";
import Head from "next/head";
import { usePapers } from "../lib/usePapers";
import {
  BallVariant,
  BgVariant,
  MemoColor,
  Memo as MemoT,
  Receipt as ReceiptT,
  RECEIPT_MAX_HEIGHT,
  RECEIPT_MIN_HEIGHT,
  RECEIPT_WIDTH,
  MEMO_SIZE,
} from "../lib/types";
import Receipt from "../components/Receipt";
import Memo from "../components/Memo";
import ReceiptPrinter from "../components/ReceiptPrinter";
import PaperBin from "../components/PaperBin";
import PostItBoard from "../components/PostItBoard";
import BinScreen from "../components/BinScreen";
import Confetti from "../components/Confetti";
import { FOCUS_Z } from "../lib/focus";

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

function newId(): string {
  if (typeof crypto !== "undefined" && "randomUUID" in crypto) {
    return crypto.randomUUID();
  }
  return `r_${Date.now()}_${Math.floor(Math.random() * 1e6)}`;
}

export default function Home() {
  const { papers, loaded, addPaper, updatePaper, clearCrumpled } = usePapers();

  const [view, setView] = useState<"board" | "bin">("board");
  const [editingId, setEditingId] = useState<string | null>(null);
  const boardRef = useRef<HTMLDivElement>(null);
  const zCounter = useRef(1);

  const onBoard = papers.filter((p) => !p.crumpled);
  const balls = papers.filter((p) => p.crumpled);

  const maxZ = onBoard.reduce((m, p) => Math.max(m, p.z), 0);
  if (maxZ >= zCounter.current) zCounter.current = maxZ + 1;

  const bringToFront = useCallback(
    (id: string): number => {
      const z = ++zCounter.current;
      updatePaper(id, { z }, true);
      return z;
    },
    [updatePaper]
  );

  const printReceipt = () => {
    const board = boardRef.current?.getBoundingClientRect();
    const bw = board?.width ?? window.innerWidth;
    const x = Math.max(
      40,
      Math.min(bw - RECEIPT_WIDTH - 40, 120 + Math.random() * (bw - 360))
    );
    const r: ReceiptT = {
      id: newId(),
      kind: "receipt",
      bg: pick<BgVariant>(["crumpled1", "crumpled2"]),
      bgScale: 1.1 + Math.random() * 1.2,
      bgX: Math.round(Math.random() * 100),
      bgY: Math.round(Math.random() * 100),
      height:
        RECEIPT_MIN_HEIGHT +
        Math.round(Math.random() * (RECEIPT_MAX_HEIGHT - RECEIPT_MIN_HEIGHT)),
      x,
      y: 70 + Math.random() * 60,
      z: ++zCounter.current,
      pinned: false,
      balled: false,
      crumpled: false,
      ball: pick<BallVariant>(["ball1", "ball2", "ball3"]),
      items: [],
      draft: "",
      draftLevel: 0,
      createdAt: Date.now(),
    };
    addPaper(r);
    setEditingId(r.id);
  };

  const spawnMemo = (color: MemoColor) => {
    const board = boardRef.current?.getBoundingClientRect();
    const bw = board?.width ?? window.innerWidth;
    const m: MemoT = {
      id: newId(),
      kind: "memo",
      color,
      size: MEMO_SIZE,
      text: "",
      strokes: [],
      x: Math.max(40, bw / 2 - MEMO_SIZE / 2 + (Math.random() * 120 - 60)),
      y: 90 + Math.random() * 60,
      z: ++zCounter.current,
      pinned: false,
      balled: false,
      crumpled: false,
      ball: pick<BallVariant>(["ball1", "ball2", "ball3"]),
      createdAt: Date.now(),
    };
    addPaper(m);
    setEditingId(m.id);
  };

  // Long-press crumples a paper into a ball that stays on the board.
  const handleBall = useCallback(
    (id: string) => {
      setEditingId((cur) => (cur === id ? null : cur));
      updatePaper(id, { balled: true, pinned: false }, true);
    },
    [updatePaper]
  );

  // A ball came to rest (in the bin, or off-screen — either way it's binned).
  const burstId = useRef(0);
  const [burst, setBurst] = useState<number | null>(null);
  const handleLand = useCallback(
    (id: string, hitBin: boolean) => {
      updatePaper(id, { balled: false, crumpled: true }, true);
      if (hitBin) {
        burstId.current += 1;
        const k = burstId.current;
        setBurst(k);
        setTimeout(() => setBurst((b) => (b === k ? null : b)), 1300);
      }
    },
    [updatePaper]
  );

  const ballInPlay = onBoard.some((p) => p.balled);

  const startEdit = useCallback((id: string) => setEditingId(id), []);
  const stopEdit = useCallback(() => setEditingId(null), []);

  return (
    <>
      <Head>
        <title>Tackboard</title>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </Head>

      <div
        ref={boardRef}
        onPointerDown={(e) => {
          if (e.target === e.currentTarget) setEditingId(null);
        }}
        style={{
          position: "fixed",
          inset: 0,
          backgroundImage: "url(/assets/tackboard.png)",
          backgroundSize: "cover",
          backgroundPosition: "center",
          overflow: "hidden",
        }}
      >
        {onBoard.map((p) =>
          p.kind === "receipt" ? (
            <Receipt
              key={p.id}
              receipt={p}
              editing={editingId === p.id}
              boardRef={boardRef}
              onStartEdit={startEdit}
              onStopEdit={stopEdit}
              onUpdate={updatePaper}
              onBall={handleBall}
              onLand={handleLand}
              bringToFront={bringToFront}
            />
          ) : (
            <Memo
              key={p.id}
              memo={p}
              editing={editingId === p.id}
              boardRef={boardRef}
              onStartEdit={startEdit}
              onStopEdit={stopEdit}
              onUpdate={updatePaper}
              onBall={handleBall}
              onLand={handleLand}
              bringToFront={bringToFront}
            />
          )
        )}

        {/* Blur backdrop while focusing one item; click it to leave edit mode */}
        {editingId && (
          <div
            onPointerDown={stopEdit}
            style={{
              position: "absolute",
              inset: 0,
              zIndex: FOCUS_Z - 1,
              background: "rgba(20,16,10,0.35)",
              backdropFilter: "blur(6px)",
              WebkitBackdropFilter: "blur(6px)",
            }}
          />
        )}

        <ReceiptPrinter onPrint={printReceipt} />
        <PostItBoard onPick={spawnMemo} />
        <PaperBin
          count={balls.length}
          alert={ballInPlay}
          onOpen={() => setView("bin")}
        />

        {burst && <Confetti key={burst} />}

        {!loaded && (
          <div
            style={{
              position: "fixed",
              top: 12,
              left: "50%",
              transform: "translateX(-50%)",
              fontFamily: '"Courier New", monospace',
              fontSize: 12,
              color: "#5a4632",
              opacity: 0.7,
            }}
          >
            loading…
          </div>
        )}
      </div>

      {view === "bin" && (
        <BinScreen
          balls={balls}
          onLeave={() => setView("board")}
          onClear={clearCrumpled}
        />
      )}
    </>
  );
}

import React, { useRef, useState } from "react";
import Head from "next/head";
import { usePapers } from "../lib/usePapers";
import {
  BallVariant,
  BgVariant,
  Receipt as ReceiptT,
  RECEIPT_MAX_HEIGHT,
  RECEIPT_MIN_HEIGHT,
  RECEIPT_WIDTH,
} from "../lib/types";
import Receipt from "../components/Receipt";
import ReceiptPrinter from "../components/ReceiptPrinter";
import PaperBin from "../components/PaperBin";
import BinScreen from "../components/BinScreen";

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
  const {
    receipts,
    loaded,
    addReceipt,
    updateReceipt,
    removeReceipt,
    clearCrumpled,
  } = usePapers();

  const [view, setView] = useState<"board" | "bin">("board");
  const [editingId, setEditingId] = useState<string | null>(null);
  const boardRef = useRef<HTMLDivElement>(null);
  const zCounter = useRef(1);

  const onBoard = receipts.filter((r) => !r.crumpled);
  const balls = receipts.filter((r) => r.crumpled);

  // Keep the z-counter ahead of any persisted stacking values.
  const maxZ = onBoard.reduce((m, r) => Math.max(m, r.z), 0);
  if (maxZ >= zCounter.current) zCounter.current = maxZ + 1;

  const bringToFront = (id: string): number => {
    const z = ++zCounter.current;
    updateReceipt(id, { z }, true);
    return z;
  };

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
      height:
        RECEIPT_MIN_HEIGHT +
        Math.round(Math.random() * (RECEIPT_MAX_HEIGHT - RECEIPT_MIN_HEIGHT)),
      x,
      y: 70 + Math.random() * 60,
      z: ++zCounter.current,
      pinned: false,
      crumpled: false,
      ball: pick<BallVariant>(["ball1", "ball2", "ball3"]),
      items: [],
      draft: "",
      draftLevel: 0,
      createdAt: Date.now(),
    };
    addReceipt(r);
    setEditingId(r.id);
  };

  const crumple = (id: string) => {
    setEditingId((cur) => (cur === id ? null : cur));
    updateReceipt(id, { crumpled: true, pinned: false }, true);
  };

  return (
    <>
      <Head>
        <title>Tackboard</title>
        <meta name="viewport" content="width=device-width, initial-scale=1" />
      </Head>

      {/* The tackboard background fills the screen */}
      <div
        ref={boardRef}
        onPointerDown={(e) => {
          // Clicking bare board dismisses the active editor.
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
        {onBoard.map((r) => (
          <Receipt
            key={r.id}
            receipt={r}
            editing={editingId === r.id}
            boardRef={boardRef}
            onStartEdit={(id) => setEditingId(id)}
            onStopEdit={() => setEditingId(null)}
            onUpdate={updateReceipt}
            onCrumple={crumple}
            bringToFront={bringToFront}
          />
        ))}

        <ReceiptPrinter onPrint={printReceipt} />
        <PaperBin count={balls.length} onOpen={() => setView("bin")} />

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

import { useCallback, useEffect, useRef, useState } from "react";
import { db, firebaseEnabled } from "./firebase";
import {
  collection,
  deleteDoc,
  doc,
  getDocs,
  setDoc,
} from "firebase/firestore";
import { Paper, Receipt, Memo } from "./types";

const LS_KEY = "tackboard.papers";
const LS_KEY_OLD = "tackboard.receipts"; // pre-memo storage
const COLLECTION = "papers";

// ---- normalization ---------------------------------------------------------

// Fill in fields that older saved papers may be missing so they render
// correctly after a schema change.
function normalize(r: any): Paper {
  const base = {
    id: r.id,
    x: r.x ?? 60,
    y: r.y ?? 60,
    z: r.z ?? 1,
    pinned: !!r.pinned,
    balled: !!r.balled,
    crumpled: !!r.crumpled,
    ball: r.ball ?? "ball1",
    createdAt: r.createdAt ?? 0,
  };
  if (r.kind === "memo") {
    const m: Memo = {
      ...base,
      kind: "memo",
      color: r.color ?? "red",
      size: typeof r.size === "number" ? r.size : 210,
      text: r.text ?? "",
      strokes: Array.isArray(r.strokes) ? r.strokes : [],
    };
    return m;
  }
  const rec: Receipt = {
    ...base,
    kind: "receipt",
    bg: r.bg ?? "crumpled1",
    bgScale: typeof r.bgScale === "number" ? r.bgScale : 1.4,
    bgX: typeof r.bgX === "number" ? r.bgX : 50,
    bgY: typeof r.bgY === "number" ? r.bgY : 50,
    height: typeof r.height === "number" ? r.height : 400,
    items: (r.items ?? []).map((it: any) => ({
      text: it.text ?? "",
      level: it.level ?? 0,
      isTitle: !!it.isTitle,
      struck: !!it.struck,
    })),
    draft: r.draft ?? "",
    draftLevel: r.draftLevel ?? 0,
  };
  return rec;
}

// ---- backend adapters ------------------------------------------------------

async function loadAll(): Promise<Paper[]> {
  if (firebaseEnabled && db) {
    const snap = await getDocs(collection(db, COLLECTION));
    return snap.docs.map((d) => normalize(d.data()));
  }
  if (typeof window === "undefined") return [];
  try {
    const stored = window.localStorage.getItem(LS_KEY);
    const raw = stored
      ? JSON.parse(stored)
      : JSON.parse(window.localStorage.getItem(LS_KEY_OLD) || "[]"); // migrate
    return Array.isArray(raw) ? raw.map(normalize) : [];
  } catch {
    return [];
  }
}

async function saveOne(paper: Paper, all: Paper[]): Promise<void> {
  if (firebaseEnabled && db) {
    await setDoc(doc(db, COLLECTION, paper.id), paper);
    return;
  }
  if (typeof window === "undefined") return;
  window.localStorage.setItem(LS_KEY, JSON.stringify(all));
}

async function deleteOne(id: string, all: Paper[]): Promise<void> {
  if (firebaseEnabled && db) {
    await deleteDoc(doc(db, COLLECTION, id));
    return;
  }
  if (typeof window === "undefined") return;
  window.localStorage.setItem(LS_KEY, JSON.stringify(all));
}

// ---- hook ------------------------------------------------------------------

export function usePapers() {
  const [papers, setPapers] = useState<Paper[]>([]);
  const [loaded, setLoaded] = useState(false);

  const latest = useRef<Paper[]>([]);
  latest.current = papers;

  const timers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});

  useEffect(() => {
    loadAll()
      .then((rs) => setPapers(rs))
      .catch((e) => console.error("Failed to load papers", e))
      .finally(() => setLoaded(true));
  }, []);

  const schedulePersist = useCallback((id: string) => {
    clearTimeout(timers.current[id]);
    timers.current[id] = setTimeout(() => {
      const r = latest.current.find((x) => x.id === id);
      if (r) saveOne(r, latest.current).catch(console.error);
    }, 500);
  }, []);

  const addPaper = useCallback((r: Paper) => {
    setPapers((prev) => {
      const next = [...prev, r];
      latest.current = next;
      saveOne(r, next).catch(console.error);
      return next;
    });
  }, []);

  const updatePaper = useCallback(
    (id: string, patch: Partial<Receipt> | Partial<Memo>, persist = true) => {
      setPapers((prev) => {
        const next = prev.map((r) =>
          r.id === id ? ({ ...r, ...(patch as object) } as Paper) : r
        );
        latest.current = next;
        if (persist) schedulePersist(id);
        return next;
      });
    },
    [schedulePersist]
  );

  const removePaper = useCallback((id: string) => {
    setPapers((prev) => {
      const next = prev.filter((r) => r.id !== id);
      latest.current = next;
      deleteOne(id, next).catch(console.error);
      return next;
    });
  }, []);

  const clearCrumpled = useCallback(() => {
    setPapers((prev) => {
      const toRemove = prev.filter((r) => r.crumpled);
      const next = prev.filter((r) => !r.crumpled);
      latest.current = next;
      toRemove.forEach((r) => deleteOne(r.id, next).catch(console.error));
      return next;
    });
  }, []);

  return {
    papers,
    loaded,
    addPaper,
    updatePaper,
    removePaper,
    clearCrumpled,
  };
}

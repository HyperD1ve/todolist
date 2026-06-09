import { useCallback, useEffect, useRef, useState } from "react";
import { db, firebaseEnabled } from "./firebase";
import {
  collection,
  deleteDoc,
  doc,
  getDocs,
  setDoc,
} from "firebase/firestore";
import { Receipt } from "./types";

const LS_KEY = "tackboard.receipts";
const COLLECTION = "receipts";

// ---- backend adapters ------------------------------------------------------

async function loadAll(): Promise<Receipt[]> {
  if (firebaseEnabled && db) {
    const snap = await getDocs(collection(db, COLLECTION));
    return snap.docs.map((d) => d.data() as Receipt);
  }
  if (typeof window === "undefined") return [];
  try {
    return JSON.parse(window.localStorage.getItem(LS_KEY) || "[]");
  } catch {
    return [];
  }
}

async function saveOne(receipt: Receipt, all: Receipt[]): Promise<void> {
  if (firebaseEnabled && db) {
    await setDoc(doc(db, COLLECTION, receipt.id), receipt);
    return;
  }
  if (typeof window === "undefined") return;
  window.localStorage.setItem(LS_KEY, JSON.stringify(all));
}

async function deleteOne(id: string, all: Receipt[]): Promise<void> {
  if (firebaseEnabled && db) {
    await deleteDoc(doc(db, COLLECTION, id));
    return;
  }
  if (typeof window === "undefined") return;
  window.localStorage.setItem(LS_KEY, JSON.stringify(all));
}

// ---- hook ------------------------------------------------------------------

export function usePapers() {
  const [receipts, setReceipts] = useState<Receipt[]>([]);
  const [loaded, setLoaded] = useState(false);

  // Latest snapshot, so debounced writes persist the freshest data.
  const latest = useRef<Receipt[]>([]);
  latest.current = receipts;

  // Per-receipt debounce timers so rapid typing doesn't hammer the backend.
  const timers = useRef<Record<string, ReturnType<typeof setTimeout>>>({});

  useEffect(() => {
    loadAll()
      .then((rs) => setReceipts(rs))
      .catch((e) => console.error("Failed to load receipts", e))
      .finally(() => setLoaded(true));
  }, []);

  const schedulePersist = useCallback((id: string) => {
    clearTimeout(timers.current[id]);
    timers.current[id] = setTimeout(() => {
      const r = latest.current.find((x) => x.id === id);
      if (r) saveOne(r, latest.current).catch(console.error);
    }, 500);
  }, []);

  const addReceipt = useCallback(
    (r: Receipt) => {
      setReceipts((prev) => {
        const next = [...prev, r];
        latest.current = next;
        saveOne(r, next).catch(console.error);
        return next;
      });
    },
    []
  );

  const updateReceipt = useCallback(
    (id: string, patch: Partial<Receipt>, persist = true) => {
      setReceipts((prev) => {
        const next = prev.map((r) => (r.id === id ? { ...r, ...patch } : r));
        latest.current = next;
        if (persist) schedulePersist(id);
        return next;
      });
    },
    [schedulePersist]
  );

  const removeReceipt = useCallback((id: string) => {
    setReceipts((prev) => {
      const next = prev.filter((r) => r.id !== id);
      latest.current = next;
      deleteOne(id, next).catch(console.error);
      return next;
    });
  }, []);

  const clearCrumpled = useCallback(() => {
    setReceipts((prev) => {
      const toRemove = prev.filter((r) => r.crumpled);
      const next = prev.filter((r) => !r.crumpled);
      latest.current = next;
      toRemove.forEach((r) => deleteOne(r.id, next).catch(console.error));
      return next;
    });
  }, []);

  return {
    receipts,
    loaded,
    addReceipt,
    updateReceipt,
    removeReceipt,
    clearCrumpled,
  };
}

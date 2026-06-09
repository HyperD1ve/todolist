import { initializeApp, getApps, FirebaseApp } from "firebase/app";
import { Firestore, getFirestore } from "firebase/firestore";

// The config is injected at build time via NEXT_PUBLIC_FIREBASE_CONFIG (a JSON
// string). If it's missing or malformed we degrade gracefully to localStorage
// so the app still runs locally without any backend wiring.
let app: FirebaseApp | null = null;
let dbInstance: Firestore | null = null;
let enabled = false;

try {
  const raw = process.env.NEXT_PUBLIC_FIREBASE_CONFIG;
  const config = raw ? JSON.parse(raw) : null;
  if (config && config.projectId) {
    app = getApps().length ? getApps()[0] : initializeApp(config);
    dbInstance = getFirestore(app);
    enabled = true;
  }
} catch (err) {
  // Malformed config — stay disabled, fall back to localStorage.
  console.warn("Firebase config missing/invalid; using localStorage.", err);
}

export const db = dbInstance;
export const firebaseEnabled = enabled;

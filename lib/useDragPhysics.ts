import React, { useEffect, useRef, useState } from "react";
import { BALL_SIZE } from "./types";

const CRUMPLE_MS = 3000; // long-press duration to crumple into a ball
const DRAG_THRESHOLD = 5; // px of movement before a press becomes a drag
const PIN_ZONE = 36; // drop within this many px of the top => pin

// Pendulum tuning (the paper hangs from the cursor and swings).
const GRAVITY = 2600; // px/s^2 restoring strength
const DAMPING = 3.2;
const SETTLE = 0.0008;

// Thrown-ball tuning.
const BALL_GRAVITY = 3000; // px/s^2 downward
const MAX_THROW = 3200; // px/s velocity cap
const VEL_WINDOW = 90; // ms window used to estimate throw velocity

interface Opts {
  id: string;
  width: number;
  height: number;
  x: number;
  y: number;
  editing: boolean;
  balled: boolean;
  boardRef: React.RefObject<HTMLDivElement>;
  onUpdate: (id: string, patch: { x?: number; y?: number; pinned?: boolean }) => void;
  onBall: (id: string) => void;
  onLand: (id: string, hitBin: boolean) => void;
  onStartEdit: (id: string) => void;
  bringToFront: (id: string) => number;
}

function viewport() {
  return {
    w: typeof window !== "undefined" ? window.innerWidth : 1280,
    h: typeof window !== "undefined" ? window.innerHeight : 800,
  };
}

// The bin's catch area, bottom-left (mirrors PaperBin's placement; generous so
// a ball passing through the bin image reliably counts).
function binHit(cx: number, cy: number) {
  const { h } = viewport();
  return cx >= -20 && cx <= 240 && cy >= h - 200;
}

function offscreen(x: number, y: number) {
  const { w, h } = viewport();
  return y > h + 140 || x < -180 || x > w + 180;
}

export function useDragPhysics(opts: Opts) {
  const { id, width, height, x, y, editing, balled, boardRef } = opts;
  const [pos, setPos] = useState({ x, y });
  const rootRef = useRef<HTMLDivElement>(null);

  const cb = useRef(opts);
  cb.current = opts;

  const gesture = useRef({
    down: false,
    dragging: false,
    startX: 0,
    startY: 0,
    pointerId: 0,
    crumbleTimer: 0 as ReturnType<typeof setTimeout> | number,
  });

  // Pendulum integrator state.
  const phys = useRef({
    theta: 0,
    omega: 0,
    anchorX: 0,
    lastAnchorX: 0,
    vx: 0,
    lastT: 0,
    raf: 0,
    active: false,
  });

  // Thrown-ball state. x/y are the live position (the source of truth during
  // flight — we can't read it back from the async setPos updater).
  const ball = useRef({
    mode: false, // this paper is currently a ball
    held: false, // grabbed by the pointer
    x: 0,
    y: 0,
    vx: 0,
    vy: 0,
    spin: 0,
    raf: 0,
    lastT: 0,
    samples: [] as { x: number; y: number; t: number }[],
  });

  // Keep ball.mode in step with the persisted `balled` flag.
  ball.current.mode = balled;

  useEffect(() => {
    if (!gesture.current.dragging && !ball.current.held) setPos({ x, y });
  }, [x, y]);

  // While editing, the physics loop must not write transform (React owns it
  // for the focus zoom). Stop any running pendulum loop on entering edit.
  useEffect(() => {
    if (editing && phys.current.raf) {
      cancelAnimationFrame(phys.current.raf);
      phys.current.raf = 0;
      phys.current.active = false;
    }
  }, [editing]);

  useEffect(() => {
    return () => {
      if (phys.current.raf) cancelAnimationFrame(phys.current.raf);
      if (ball.current.raf) cancelAnimationFrame(ball.current.raf);
      clearCrumbleTimer();
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const setTransform = (s: string) => {
    if (rootRef.current) rootRef.current.style.transform = s;
  };

  // ---- pendulum loop -------------------------------------------------------

  const step = (t: number) => {
    const p = phys.current;
    if (cb.current.editing) {
      p.active = false;
      p.raf = 0;
      return;
    }
    const dt = p.lastT ? Math.min((t - p.lastT) / 1000, 0.04) : 0.016;
    p.lastT = t;

    const targetVx = (p.anchorX - p.lastAnchorX) / Math.max(dt, 0.001);
    p.lastAnchorX = p.anchorX;
    const ax = (targetVx - p.vx) / Math.max(dt, 0.001);
    p.vx = targetVx;

    const L = height;
    // +ax: the bob lags the pivot, so the paper swings opposite to the cursor.
    const alpha =
      -(GRAVITY / L) * Math.sin(p.theta) -
      DAMPING * p.omega +
      (ax / L) * Math.cos(p.theta);
    p.omega += alpha * dt;
    p.theta += p.omega * dt;
    setTransform(`rotate(${p.theta}rad)`);

    if (
      Math.abs(p.theta) < SETTLE &&
      Math.abs(p.omega) < SETTLE &&
      !gesture.current.dragging
    ) {
      p.theta = 0;
      p.omega = 0;
      setTransform("rotate(0rad)");
      p.active = false;
      p.raf = 0;
      return;
    }
    p.raf = requestAnimationFrame(step);
  };

  const ensureLoop = () => {
    const p = phys.current;
    if (!p.active && !cb.current.editing) {
      p.active = true;
      p.lastT = 0;
      p.raf = requestAnimationFrame(step);
    }
  };

  // ---- thrown-ball loop ----------------------------------------------------

  const ballStep = (t: number) => {
    const b = ball.current;
    const dt = b.lastT ? Math.min((t - b.lastT) / 1000, 0.04) : 0.016;
    b.lastT = t;

    b.vy += BALL_GRAVITY * dt;
    b.spin += b.vx * dt * 0.004;
    b.x += b.vx * dt;
    b.y += b.vy * dt;
    setPos({ x: b.x, y: b.y });
    setTransform(`rotate(${b.spin}rad)`);

    const cx = b.x + BALL_SIZE / 2;
    const cy = b.y + BALL_SIZE / 2;
    if (binHit(cx, cy)) {
      stopBallLoop();
      cb.current.onLand(id, true);
      return;
    }
    if (offscreen(b.x, b.y)) {
      stopBallLoop();
      cb.current.onLand(id, false);
      return;
    }
    b.raf = requestAnimationFrame(ballStep);
  };

  const stopBallLoop = () => {
    if (ball.current.raf) cancelAnimationFrame(ball.current.raf);
    ball.current.raf = 0;
  };

  const launchBall = () => {
    const b = ball.current;
    // Estimate velocity from the recent pointer samples.
    const s = b.samples;
    if (s.length >= 2) {
      const last = s[s.length - 1];
      let ref = s[0];
      for (let i = s.length - 1; i >= 0; i--) {
        if (last.t - s[i].t >= VEL_WINDOW) {
          ref = s[i];
          break;
        }
        ref = s[i];
      }
      const dt = Math.max((last.t - ref.t) / 1000, 0.001);
      b.vx = (last.x - ref.x) / dt;
      b.vy = (last.y - ref.y) / dt;
      const mag = Math.hypot(b.vx, b.vy);
      if (mag > MAX_THROW) {
        b.vx *= MAX_THROW / mag;
        b.vy *= MAX_THROW / mag;
      }
    } else {
      b.vx = 0;
      b.vy = 0;
    }
    b.held = false;
    b.lastT = 0;
    b.raf = requestAnimationFrame(ballStep);
  };

  // ---- gesture helpers -----------------------------------------------------

  function clearCrumbleTimer() {
    if (gesture.current.crumbleTimer) {
      clearTimeout(gesture.current.crumbleTimer as number);
      gesture.current.crumbleTimer = 0;
    }
  }

  const reset = () => {
    gesture.current.down = false;
    gesture.current.dragging = false;
    clearCrumbleTimer();
  };

  // Long-press fired: turn the paper into a ball, held by the current pointer.
  const becomeBall = () => {
    clearCrumbleTimer();
    if (phys.current.raf) cancelAnimationFrame(phys.current.raf);
    phys.current.active = false;
    setTransform("rotate(0rad)");
    const b = ball.current;
    b.mode = true;
    b.held = true;
    b.vx = 0;
    b.vy = 0;
    b.spin = 0;
    b.x = pos.x;
    b.y = pos.y;
    b.samples = [];
    stopBallLoop();
    cb.current.bringToFront(id);
    cb.current.onBall(id);
  };

  const sample = (clientX: number, clientY: number, t: number) => {
    const board = boardRef.current?.getBoundingClientRect();
    const px = clientX - (board?.left ?? 0) - BALL_SIZE / 2;
    const py = clientY - (board?.top ?? 0) - BALL_SIZE / 2;
    const b = ball.current;
    b.x = px;
    b.y = py;
    b.samples.push({ x: px, y: py, t });
    if (b.samples.length > 8) b.samples.shift();
    setPos({ x: px, y: py });
  };

  // ---- pointer handlers ----------------------------------------------------

  const onPointerDown = (e: React.PointerEvent) => {
    if (editing) return;
    e.preventDefault();
    const g = gesture.current;
    g.down = true;
    g.dragging = false;
    g.startX = e.clientX;
    g.startY = e.clientY;
    g.pointerId = e.pointerId;
    try {
      (e.currentTarget as HTMLElement).setPointerCapture(e.pointerId);
    } catch {}
    cb.current.bringToFront(id);

    if (ball.current.mode) {
      // Grab an existing ball to (re)throw it.
      stopBallLoop();
      ball.current.held = true;
      ball.current.samples = [];
      sample(e.clientX, e.clientY, e.timeStamp);
      return;
    }
    g.crumbleTimer = setTimeout(becomeBall, CRUMPLE_MS);
  };

  const beginDrag = (clientX: number, clientY: number) => {
    const g = gesture.current;
    g.dragging = true;
    clearCrumbleTimer();
    const board = boardRef.current?.getBoundingClientRect();
    const ax = clientX - (board?.left ?? 0);
    const ay = clientY - (board?.top ?? 0);
    setPos({ x: ax - width / 2, y: ay });
    const p = phys.current;
    p.anchorX = clientX;
    p.lastAnchorX = clientX;
    p.vx = 0;
    ensureLoop();
  };

  const onPointerMove = (e: React.PointerEvent) => {
    const g = gesture.current;
    if (!g.down) return;
    if (e.buttons === 0) {
      // Missed up/cancel — never latch onto a hovering cursor.
      reset();
      ball.current.held = false;
      try {
        (e.currentTarget as HTMLElement).releasePointerCapture(g.pointerId);
      } catch {}
      return;
    }

    if (ball.current.mode && ball.current.held) {
      sample(e.clientX, e.clientY, e.timeStamp);
      return;
    }

    const dx = e.clientX - g.startX;
    const dy = e.clientY - g.startY;
    if (!g.dragging && Math.hypot(dx, dy) > DRAG_THRESHOLD) {
      beginDrag(e.clientX, e.clientY);
    }
    if (g.dragging) {
      const board = boardRef.current?.getBoundingClientRect();
      const ax = e.clientX - (board?.left ?? 0);
      const ay = e.clientY - (board?.top ?? 0);
      setPos({ x: ax - width / 2, y: ay });
      phys.current.anchorX = e.clientX;
      ensureLoop();
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

    if (ball.current.mode) {
      if (ball.current.held) {
        sample(e.clientX, e.clientY, e.timeStamp);
        launchBall(); // gravity + thrown momentum take over
      }
      return;
    }

    if (!g.dragging) {
      cb.current.onStartEdit(id);
      return;
    }

    g.dragging = false;
    phys.current.vx = 0;
    ensureLoop();

    const board = boardRef.current?.getBoundingClientRect();
    const ay = e.clientY - (board?.top ?? 0);
    const pinned = ay <= PIN_ZONE;
    setPos((pp) => {
      const finalY = pinned ? 8 : pp.y;
      cb.current.onUpdate(id, { x: pp.x, y: finalY, pinned });
      return { x: pp.x, y: finalY };
    });
  };

  const onPointerCancel = (e: React.PointerEvent) => {
    reset();
    if (ball.current.mode && ball.current.held) launchBall();
    try {
      (e.currentTarget as HTMLElement).releasePointerCapture(e.pointerId);
    } catch {}
  };

  return {
    pos,
    setPos,
    rootRef,
    dragHandlers: { onPointerDown, onPointerMove, onPointerUp, onPointerCancel },
  };
}

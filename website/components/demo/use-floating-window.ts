"use client";

import { animate, useDragControls, useMotionValue } from "motion/react";
import { useEffect, useState } from "react";
import { useNote } from "./store";

function isTyping(target: EventTarget | null) {
  const el = target as HTMLElement | null;
  return !!el && (el.isContentEditable || el.tagName === "INPUT" || el.tagName === "TEXTAREA");
}

/**
 * The demo window's behaviour as a floating panel: shown and hidden with ⇧⌘N (where the
 * browser lets it through) or plain N, dragged by its title bar on pointer devices, and
 * recentred with a double-click.
 */
export function useFloatingWindow() {
  const { visible, setVisible } = useNote();
  const controls = useDragControls();
  const x = useMotionValue(0);
  const y = useMotionValue(0);
  const [pressed, setPressed] = useState(false);
  const [canDrag, setCanDrag] = useState(false);

  useEffect(() => {
    const query = window.matchMedia("(pointer: fine) and (min-width: 768px)");
    const update = () => setCanDrag(query.matches);
    update();
    query.addEventListener("change", update);
    return () => query.removeEventListener("change", update);
  }, []);

  const flash = () => {
    setPressed(true);
    window.setTimeout(() => setPressed(false), 160);
  };

  const toggle = () => {
    flash();
    setVisible(!visible);
  };

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key.toLowerCase() !== "n" || e.altKey || e.ctrlKey) return;
      const hotkey = e.metaKey && e.shiftKey;
      const plain = !e.metaKey && !e.shiftKey && !isTyping(e.target);
      if (!hotkey && !plain) return;
      e.preventDefault();
      flash();
      setVisible(!visible);
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [visible, setVisible]);

  const recenter = () => {
    animate(x, 0, { type: "spring", stiffness: 400, damping: 36 });
    animate(y, 0, { type: "spring", stiffness: 400, damping: 36 });
  };

  return { visible, toggle, pressed, canDrag, controls, x, y, recenter };
}

"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useState } from "react";
import { useNote } from "./store";

/** Jot's in-window toast: glass, 40pt below the top, a green dot, gone after three seconds. */
export function Toast() {
  const { toast } = useNote();
  const [expired, setExpired] = useState<number | null>(null);
  const shown = toast && toast.seq !== expired ? toast : null;

  useEffect(() => {
    if (!toast) return;
    const timer = window.setTimeout(() => setExpired(toast.seq), 3000);
    return () => window.clearTimeout(timer);
  }, [toast]);

  return (
    <div className="pointer-events-none absolute inset-x-0 top-10 z-30 flex justify-center px-14">
      <AnimatePresence>
        {shown && (
          <motion.div
            key="toast"
            role="status"
            initial={{ opacity: 0, y: -5 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, transition: { duration: 0.2, ease: "linear" } }}
            transition={{ duration: 0.3, ease: "easeOut" }}
            className="relative flex h-8 items-center gap-1.5 overflow-hidden rounded-xl border border-white/10 bg-[rgb(48_48_48/0.72)] pr-4 pl-2 font-app text-[13px] text-white shadow-[0_8px_24px_rgb(0_0_0/0.35)] backdrop-blur-xl"
          >
            <span
              aria-hidden
              className="absolute inset-0"
              style={{
                background:
                  "radial-gradient(45% 30% at 50% -10%, rgb(89 212 153 / 0.26), transparent), radial-gradient(100% 90% at 50% -15%, rgb(89 212 153 / 0.26), transparent)",
              }}
            />
            <span className="relative flex size-4 items-center justify-center">
              <span className="size-[5px] rounded-full bg-green shadow-[0_0_12px_8px_rgb(89_212_153/0.2)]" />
            </span>
            <span className="relative whitespace-nowrap">{shown.title}</span>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}

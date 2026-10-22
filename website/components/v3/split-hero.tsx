"use client";

import { AnimatePresence, motion } from "motion/react";
import { useRef } from "react";
import { JotWindow } from "../demo/jot-window";
import { useFloatingWindow } from "../demo/use-floating-window";
import { HeroCopy } from "../hero";

/**
 * `/v3`'s hero: the pitch on the left, and the `/v2` note floating beside it on the grain as
 * the hero asset. The window is the live editor: drag it around the hero, N hides it.
 */
export function SplitHero() {
  const area = useRef<HTMLElement>(null);
  const { visible, toggle, pressed, canDrag, controls, x, y, recenter } = useFloatingWindow();

  return (
    <section
      ref={area}
      aria-labelledby="hero-title"
      className="relative mx-auto grid min-h-dvh max-w-6xl items-center gap-14 px-6 pt-28 pb-16 lg:grid-cols-[1fr_minmax(0,520px)] lg:gap-16 lg:pt-24"
    >
      <HeroCopy align="start" />

      <div id="demo" className="relative flex min-h-[560px] items-center justify-center lg:min-h-[670px]">
        <AnimatePresence mode="popLayout">
          {visible ? (
            <motion.div
              key="window"
              drag={canDrag}
              dragControls={controls}
              dragListener={false}
              dragMomentum={false}
              dragConstraints={area}
              dragElastic={0.04}
              style={{ x, y }}
              initial={{ opacity: 0, scale: 0.96, filter: "blur(8px)" }}
              animate={{
                opacity: 1,
                scale: 1,
                filter: "blur(0px)",
                transition: { duration: 0.7, delay: 0.25, ease: [0.3, 0.7, 0, 1.06] },
              }}
              exit={{ opacity: 0, scale: 0.97, filter: "blur(4px)", transition: { duration: 0.16, ease: "easeIn" } }}
              className="relative z-10 w-full max-w-[520px]"
            >
              <JotWindow
                height="h-[min(78dvh,650px)]"
                onHeaderPointerDown={(e) => canDrag && controls.start(e)}
                onHeaderDoubleClick={recenter}
              />
            </motion.div>
          ) : (
            <motion.button
              key="ghost"
              type="button"
              onClick={toggle}
              initial={{ opacity: 0 }}
              animate={{ opacity: 1, transition: { delay: 0.1 } }}
              exit={{ opacity: 0 }}
              className="flex flex-col items-center gap-5 font-serif text-[18px] text-muted transition-colors hover:text-fg"
            >
              <span className="flex gap-1.5 font-sans text-[22px]">
                {["⇧", "⌘", "N"].map((k) => (
                  <kbd key={k} className="kbd" data-active={pressed}>
                    {k}
                  </kbd>
                ))}
              </span>
              <span className="italic">Tucked away. Press N to bring it back.</span>
            </motion.button>
          )}
        </AnimatePresence>
      </div>
    </section>
  );
}

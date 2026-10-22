"use client";

import { AnimatePresence, motion } from "motion/react";
import { useCallback, useEffect, useRef, useState } from "react";
import { downloadUrl, githubUrl } from "@/lib/site";
import { DownloadIcon, JotMark, SendIcon } from "../icons";
import { JotWindow } from "../demo/jot-window";
import { useNote } from "../demo/store";
import { useFloatingWindow } from "../demo/use-floating-window";

const ease = [0.23, 1, 0.32, 1] as const;

const quietLink =
  "underline decoration-white/25 underline-offset-[5px] transition-[color,text-decoration-color] duration-150 hover:text-fg hover:decoration-red";

/**
 * The whole page is one note: a Jot window on black grain, with the pitch written inside it,
 * and one clear way to get it underneath (⌘↩ anywhere on the page).
 */
export function Landing() {
  const viewport = useRef<HTMLElement>(null);
  const { visible, toggle, pressed, canDrag, controls, x, y, recenter } = useFloatingWindow();
  const { showToast } = useNote();
  const [downloading, setDownloading] = useState(false);

  const download = useCallback(() => {
    setDownloading(true);
    window.setTimeout(() => setDownloading(false), 180);
    showToast("Opening GitHub…");
    window.location.href = downloadUrl;
  }, [showToast]);

  // Phones can't install a Mac app, so the phone CTA sends the link on: the share sheet
  // (AirDrop, Messages, Mail), or a copied link where sharing isn't available.
  const [copied, setCopied] = useState(false);
  const sendToMac = useCallback(async () => {
    const url = window.location.href.split("#")[0];
    if (navigator.share) {
      try {
        await navigator.share({ title: "Jot", text: "Jot: Raycast Notes, but free. Open this on your Mac.", url });
      } catch {
        // Closing the share sheet rejects; nothing to do.
      }
      return;
    }
    try {
      await navigator.clipboard.writeText(url);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2000);
    } catch {
      // No clipboard access either; the button just does nothing.
    }
  }, []);

  // ⌘↩ downloads, wherever focus is (a code block in the note keeps it to leave the block).
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key !== "Enter" || !(e.metaKey || e.ctrlKey) || e.defaultPrevented) return;
      e.preventDefault();
      download();
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [download]);

  return (
    <main ref={viewport} className="page-v2 relative flex min-h-svh flex-col overflow-hidden sm:min-h-dvh">
      <motion.header
        initial={{ opacity: 0 }}
        animate={{ opacity: 1 }}
        transition={{ duration: 0.8, delay: 0.5, ease }}
        className="relative z-10 flex items-center justify-between px-5 pt-[max(1rem,env(safe-area-inset-top))] sm:px-7 sm:pt-5"
      >
        <a href="/" className="flex items-center gap-2 text-[15px] font-medium tracking-[-0.01em] text-fg">
          <JotMark className="size-[20px]" />
          Jot
        </a>
        <nav aria-label="Links" className="flex items-center gap-5 text-[14px] text-muted">
          <a href={githubUrl} className={quietLink}>
            GitHub
          </a>
          <a
            href={downloadUrl}
            className="inline-flex h-8 items-center rounded-full bg-white px-3.5 font-sans text-[13px] font-medium text-black transition-[transform,background-color] duration-150 hover:bg-white/90 active:scale-[0.97] max-sm:hidden"
          >
            Download
          </a>
        </nav>
      </motion.header>

      {/* Phones: the note sits on the page itself, followed directly by the Send button. */}
      <div className="flex justify-center px-6 pt-14 max-sm:flex-none sm:flex-1 sm:items-center sm:px-6 sm:py-4">
        {/* The first appearance is the CSS reveal (no waiting for JavaScript); later ones animate here. */}
        <AnimatePresence mode="popLayout" initial={false}>
          {visible ? (
            <motion.div
              key="window"
              drag={canDrag}
              dragControls={controls}
              dragListener={false}
              dragMomentum={false}
              dragConstraints={viewport}
              dragElastic={0.04}
              style={{ x, y }}
              initial={{ opacity: 0, scale: 0.96, filter: "blur(8px)" }}
              animate={{
                opacity: 1,
                scale: 1,
                filter: "blur(0px)",
                transition: { duration: 0.6, ease: [0.3, 0.7, 0, 1.06] },
                transitionEnd: { filter: "none" },
              }}
              exit={{ opacity: 0, scale: 0.97, filter: "blur(4px)", transition: { duration: 0.16, ease: "easeIn" } }}
              className="jot-window-in relative z-10 w-full max-w-[560px]"
            >
              <JotWindow
                height="sm:h-[min(76dvh,660px)]"
                bareOnMobile
                surface="border-white/[0.07] bg-[rgb(15_15_15/0.78)]"
                primaryAction={{
                  title: "Download for macOS",
                  icon: <DownloadIcon className="size-[15px] text-red" />,
                  pressed: downloading,
                  onRun: download,
                }}
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
              className="flex h-[min(76dvh,660px)] flex-col items-center justify-center gap-5 text-[14px] text-muted transition-colors hover:text-fg"
            >
              <span className="flex gap-1.5 text-[22px]">
                {["⇧", "⌘", "N"].map((k) => (
                  <kbd key={k} className="kbd" data-active={pressed}>
                    {k}
                  </kbd>
                ))}
              </span>
              <span>Tucked away. Press N to bring it back.</span>
            </motion.button>
          )}
        </AnimatePresence>

      </div>

      {/* Phones: the action closes the note as part of the page, clear of the home indicator. */}
      <div className="flex flex-col items-center px-6 pt-12 pb-[max(3rem,calc(env(safe-area-inset-bottom)+1.5rem))] sm:hidden">
        {/* Full width to line up with the text column, slim (44pt), and in Jot's glass: part of the
            page rather than a slab of white. The red send icon carries the accent. */}
        <button
          type="button"
          onClick={sendToMac}
          className="flex h-11 w-full items-center justify-center gap-2 rounded-full border border-white/[0.12] bg-white/[0.08] text-[15px] font-medium text-white/90 shadow-[inset_0_1px_0_rgb(255_255_255/0.06)] transition-[transform,background-color] duration-150 ease-out select-none active:scale-[0.98] active:bg-white/[0.12]"
        >
          <SendIcon className="size-4 text-red" />
          {copied ? "Link copied" : "Send to your Mac"}
        </button>
        <p className="mt-2.5 text-center text-[12px] text-faint">AirDrop it or text it to yourself</p>
      </div>
    </main>
  );
}

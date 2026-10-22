"use client";

import { AnimatePresence, motion } from "motion/react";
import { useRef } from "react";
import { downloadUrl, githubUrl, requirement } from "@/lib/site";
import { JotWindow } from "./demo/jot-window";
import { useFloatingWindow } from "./demo/use-floating-window";
import { CheckIcon, DownloadIcon, GitHubIcon } from "./icons";

const rise = {
  hidden: { opacity: 0, y: 14, filter: "blur(6px)" },
  shown: { opacity: 1, y: 0, filter: "blur(0px)" },
};

export function Hero() {
  const stage = useRef<HTMLDivElement>(null);
  const { visible, toggle, pressed, canDrag, controls, x, y, recenter } = useFloatingWindow();

  return (
    <section className="relative overflow-hidden pt-32 sm:pt-40" aria-labelledby="hero-title">
      <HeroCopy align="center" />

      {/* The desktop */}
      <motion.div
        initial={{ opacity: 0, y: 40 }}
        animate={{ opacity: 1, y: 0 }}
        transition={{ duration: 1, delay: 0.35, ease: [0.23, 1, 0.32, 1] }}
        className="relative mx-auto mt-20 max-w-6xl px-4 sm:px-6"
      >
        <div
          id="demo"
          ref={stage}
          className="relative flex min-h-[560px] items-center justify-center overflow-hidden rounded-[28px] border border-line bg-[#0b0b0b] px-4 py-14 sm:min-h-[620px] sm:rounded-[36px]"
        >
          <div aria-hidden className="absolute inset-0">
            <div className="blob top-[-12%] left-[6%] h-[60%] w-[46%] bg-[#ff6363] opacity-40" />
            <div className="blob right-[2%] bottom-[-18%] h-[70%] w-[50%] bg-[#7a1420] opacity-60 [animation-delay:-6s]" />
            <div className="blob top-[20%] right-[24%] h-[30%] w-[26%] bg-[#ffd1c4] opacity-[0.12] [animation-delay:-11s]" />
            <div
              className="absolute inset-0 opacity-[0.35]"
              style={{
                backgroundImage: "radial-gradient(rgb(255 255 255 / 0.07) 1px, transparent 1px)",
                backgroundSize: "22px 22px",
              }}
            />
          </div>

          <AnimatePresence mode="popLayout">
            {visible ? (
              <motion.div
                key="window"
                drag={canDrag}
                dragControls={controls}
                dragListener={false}
                dragMomentum={false}
                dragConstraints={stage}
                dragElastic={0.06}
                style={{ x, y }}
                initial={{ opacity: 0, scale: 0.96 }}
                animate={{ opacity: 1, scale: 1, transition: { duration: 0.32, ease: [0.3, 0.7, 0, 1.06] } }}
                exit={{ opacity: 0, scale: 0.97, transition: { duration: 0.16, ease: "easeIn" } }}
                className="relative z-10 w-full max-w-[520px]"
              >
                <JotWindow onHeaderPointerDown={(e) => canDrag && controls.start(e)} onHeaderDoubleClick={recenter} />
              </motion.div>
            ) : (
              <motion.button
                key="ghost"
                type="button"
                onClick={toggle}
                initial={{ opacity: 0 }}
                animate={{ opacity: 1, transition: { delay: 0.1 } }}
                exit={{ opacity: 0 }}
                className="relative z-10 flex flex-col items-center gap-4 rounded-2xl px-8 py-6 text-[14px] text-muted transition-colors hover:text-fg"
              >
                <span className="flex gap-1.5 text-[22px]">
                  {["⇧", "⌘", "N"].map((k) => (
                    <kbd key={k} className="kbd" data-active={pressed}>
                      {k}
                    </kbd>
                  ))}
                </span>
                Jot is tucked away. Press N or click to bring it back.
              </motion.button>
            )}
          </AnimatePresence>
        </div>

        <div className="mt-5 flex flex-wrap items-center justify-center gap-x-5 gap-y-3 text-[13px] text-faint">
          <button
            type="button"
            onClick={toggle}
            className="inline-flex items-center gap-2 rounded-full border border-line px-3 py-1 text-muted transition-colors duration-150 hover:border-white/20 hover:text-fg"
            aria-label={visible ? "Hide the Jot window" : "Show the Jot window"}
          >
            <span className="flex gap-1 text-[13px]">
              {["⇧", "⌘", "N"].map((k) => (
                <kbd key={k} className="kbd" data-active={pressed}>
                  {k}
                </kbd>
              ))}
            </span>
            {visible ? "Hide" : "Show"}
          </button>
          <span>
            Type <Code>#</Code>, <Code>-</Code>, <Code>[]</Code> or <Code>```</Code> and a space
          </span>
          <span>Paste or drop an image</span>
          <span className="hidden sm:inline">
            <Code>⌘K</Code> for actions
          </span>
        </div>
      </motion.div>
    </section>
  );
}

/** The pitch: eyebrow, headline, line, buttons and ticks. Centred above the demo (`/`) or
 * left-aligned beside it (`/v3`). */
export function HeroCopy({ align }: { align: "center" | "start" }) {
  const start = align === "start";
  return (
    <motion.div
      className={start ? "relative flex flex-col items-start text-left" : "relative mx-auto flex max-w-5xl flex-col items-center px-6 text-center"}
      initial="hidden"
      animate="shown"
      transition={{ staggerChildren: 0.08, delayChildren: 0.05 }}
    >
      <motion.p
        variants={rise}
        transition={{ duration: 0.6, ease: [0.23, 1, 0.32, 1] }}
        className="mb-7 inline-flex items-center gap-2 rounded-full border border-line-strong bg-white/[0.03] py-1 pr-3 pl-2 text-[13px] text-muted"
      >
        <span className="size-1.5 rounded-full bg-red shadow-[0_0_10px_rgb(255_99_99/0.8)]" />
        Free &amp; open source
      </motion.p>
  
      <motion.h1
        id="hero-title"
        variants={rise}
        transition={{ duration: 0.7, ease: [0.23, 1, 0.32, 1] }}
        className={`${start ? "text-[clamp(2.75rem,5.6vw,4.6rem)]" : "text-[clamp(2.75rem,7.4vw,5.6rem)]"} leading-[0.98] font-medium tracking-[-0.045em] text-balance text-fg`}
      >
        Raycast Notes,
        <br className={start ? "" : "hidden sm:block"} />{" "}
        <span className="font-serif text-[1.1em] font-normal tracking-[-0.02em] text-red italic">but free.</span>
      </motion.h1>
  
      <motion.p
        variants={rise}
        transition={{ duration: 0.7, ease: [0.23, 1, 0.32, 1] }}
        className="mt-7 max-w-xl text-[17px] leading-relaxed text-pretty text-muted"
      >
        The floating notes window, rebuilt as a native Mac app and given away. Unlimited notes, images
        included, no account. Press ⇧⌘N and start writing.
      </motion.p>
  
      <motion.div
        variants={rise}
        transition={{ duration: 0.7, ease: [0.23, 1, 0.32, 1] }}
        className={`mt-10 flex flex-col gap-3 sm:flex-row ${start ? "items-start" : "items-center"}`}
      >
        <a
          href={downloadUrl}
          className="group inline-flex h-11 items-center gap-2 rounded-full bg-red px-5 text-[15px] font-medium text-black shadow-[0_8px_30px_-6px_rgb(255_99_99/0.6),inset_0_1px_0_rgb(255_255_255/0.35)] transition-[transform,background-color] duration-150 hover:bg-[#ff7676] active:scale-[0.97]"
        >
          <DownloadIcon className="size-4" />
          Download for macOS
        </a>
        <a
          href={githubUrl}
          className="inline-flex h-11 items-center gap-2 rounded-full border border-line-strong px-5 text-[15px] text-fg transition-[border-color,background-color,transform] duration-150 hover:border-white/20 hover:bg-white/[0.04] active:scale-[0.97]"
        >
          <GitHubIcon className="size-4" />
          Star on GitHub
        </a>
      </motion.div>
      <motion.ul
        variants={rise}
        transition={{ duration: 0.7, ease: [0.23, 1, 0.32, 1] }}
        className={`mt-7 flex flex-wrap items-center gap-x-5 gap-y-2 text-[13px] text-muted ${start ? "" : "justify-center"}`}
        aria-label="What you get"
      >
        {["Unlimited notes", "Images included", "No account", "Open source"].map((item) => (
          <li key={item} className="flex items-center gap-1.5">
            <CheckIcon className="size-3.5 text-red" />
            {item}
          </li>
        ))}
      </motion.ul>
      <motion.p variants={rise} className="mt-3 text-[12px] text-faint">
        {requirement}
      </motion.p>
    </motion.div>
  );
}

function Code({ children }: { children: React.ReactNode }) {
  return <code className="rounded-md border border-line bg-white/[0.03] px-1.5 py-0.5 font-mono text-[12px] text-muted">{children}</code>;
}

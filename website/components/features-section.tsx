"use client";

import { motion } from "motion/react";
import type { MouseEvent, ReactNode } from "react";
import { SectionHeading, Serif } from "./section-heading";

const chips = (items: string[]) => (
  <div className="mt-6 flex flex-wrap gap-2">
    {items.map((t) => (
      <span key={t} className="rounded-full border border-line-strong px-2.5 py-1 font-mono text-[11.5px] text-muted">
        {t}
      </span>
    ))}
  </div>
);

const features: { title: string; body: string; extra?: ReactNode; wide?: boolean }[] = [
  {
    title: "Unlimited notes",
    body: "Write as many as you like. There's no cap to bump into and nothing to upgrade.",
  },
  {
    title: "Images included",
    body: "Paste a screenshot, drop in a photo, drag it where it belongs. Press Space to open it in Quick Look.",
    extra: chips(["⌘V to paste", "Drag and drop", "Quick Look", "Up to 20 MB"]),
    wide: true,
  },
  {
    title: "Built with AppKit",
    body: "No Electron, no web view. Text runs on TextKit 2, the chrome is Liquid Glass, and every pixel is drawn by macOS itself.",
    extra: chips(["Swift 6", "AppKit", "TextKit 2", "Liquid Glass", "SQLite"]),
    wide: true,
  },
  {
    title: "Open source",
    body: "Read the code, fork it, send a pull request. No license keys, no trial, no Pro tier.",
  },
  {
    title: "Yours, on your Mac",
    body: "Notes and images live in a folder on your Mac. No account to make, nothing to sign into.",
  },
  {
    title: "Copy it anywhere",
    body: "Copy or export a note, or just the selection, as Markdown, HTML or plain text.",
  },
  {
    title: "Pin, browse, recover",
    body: "Pin the notes that matter, browse them all with ⌘P, and bring back anything from Recently Deleted.",
  },
  {
    title: "Always on top",
    body: "A floating panel that stays above your work and follows you to whichever Space you're in.",
  },
  {
    title: "Grows with your note",
    body: "The window sizes itself to what you've written. Double-click the title bar to snap back after a resize.",
  },
  {
    title: "Find and replace",
    body: "⌘F searches the note as you type, with replace and replace-all one keystroke away.",
  },
];

/** A card with a soft red light that follows the pointer. */
function Card({ children, wide, index }: { children: ReactNode; wide?: boolean; index: number }) {
  const onMove = (e: MouseEvent<HTMLDivElement>) => {
    const box = e.currentTarget.getBoundingClientRect();
    e.currentTarget.style.setProperty("--x", `${e.clientX - box.left}px`);
    e.currentTarget.style.setProperty("--y", `${e.clientY - box.top}px`);
  };
  return (
    <motion.div
      initial={{ opacity: 0, y: 12 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: "-60px" }}
      transition={{ duration: 0.6, delay: (index % 3) * 0.06, ease: [0.23, 1, 0.32, 1] }}
      onMouseMove={onMove}
      className={`group relative overflow-hidden rounded-3xl border border-line bg-raised p-7 sm:p-8 ${wide ? "md:col-span-2" : ""}`}
    >
      <div
        aria-hidden
        className="pointer-events-none absolute inset-0 opacity-0 transition-opacity duration-300 group-hover:opacity-100"
        style={{ background: "radial-gradient(360px circle at var(--x, 50%) var(--y, 50%), rgb(255 99 99 / 0.09), transparent 60%)" }}
      />
      <div className="relative">{children}</div>
    </motion.div>
  );
}

export function FeaturesSection() {
  return (
    <section id="free" className="mx-auto max-w-5xl scroll-mt-24 px-6 py-24 sm:py-32">
      <SectionHeading
        eyebrow="Free"
        title={
          <>
            Everything&apos;s included. <Serif>Forever.</Serif>
          </>
        }
      >
        No paywall, no note limit, no subscription. Jot is a real Mac app, not a website in a frame, and every
        line of it is open for you to read.
      </SectionHeading>

      <div className="mt-14 grid gap-3 md:grid-cols-3">
        {features.map((f, i) => (
          <Card key={f.title} wide={f.wide} index={i}>
            <h3 className="text-[17px] font-medium tracking-[-0.01em]">{f.title}</h3>
            <p className="mt-2.5 max-w-md text-[15px] leading-relaxed text-muted">{f.body}</p>
            {f.extra}
          </Card>
        ))}
      </div>
    </section>
  );
}

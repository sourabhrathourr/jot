"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useRef, useState } from "react";
import { SectionHeading, Serif } from "./section-heading";

type Shortcut = { label: string; keys: string[] };

const shortcuts: Shortcut[] = [
  { label: "Show or hide Jot", keys: ["⇧", "⌘", "N"] },
  { label: "Action Panel", keys: ["⌘", "K"] },
  { label: "Browse Notes", keys: ["⌘", "P"] },
  { label: "New Note", keys: ["⌘", "N"] },
  { label: "Pin Note", keys: ["⇧", "⌘", "P"] },
  { label: "Duplicate Note", keys: ["⌘", "D"] },
  { label: "Copy Note As…", keys: ["⇧", "⌘", "C"] },
  { label: "Export…", keys: ["⇧", "⌘", "E"] },
  { label: "Find", keys: ["⌘", "F"] },
  { label: "Go Back", keys: ["⌘", "["] },
  { label: "Go Forward", keys: ["⌘", "]"] },
  { label: "Zoom In", keys: ["⌘", "="] },
  { label: "Zoom Out", keys: ["⌘", "-"] },
  { label: "Toggle Format Bar", keys: ["⌥", "⌘", ","] },
  { label: "Exit Code Block", keys: ["⌘", "↩"] },
  { label: "Delete Note", keys: ["⌃", "X"] },
];

const codeKeys: Record<string, string> = {
  BracketLeft: "[",
  BracketRight: "]",
  Equal: "=",
  Minus: "-",
  Comma: ",",
  Enter: "↩",
};

/** The pressed combination in Jot's notation, modifiers in macOS order (⌃ ⌥ ⇧ ⌘). */
function combo(e: KeyboardEvent): string[] {
  const keys: string[] = [];
  if (e.ctrlKey) keys.push("⌃");
  if (e.altKey) keys.push("⌥");
  if (e.shiftKey) keys.push("⇧");
  if (e.metaKey) keys.push("⌘");
  const key = codeKeys[e.code] ?? (e.code.startsWith("Key") ? e.code.slice(3) : e.code.startsWith("Digit") ? e.code.slice(5) : null);
  if (key) keys.push(key);
  return keys;
}

const order = ["⌃", "⌥", "⇧", "⌘"];
/** Modifiers in macOS order, then the key. */
const rank = (key: string) => (order.includes(key) ? order.indexOf(key) : order.length);
const sameCombo = (a: string[], b: string[]) =>
  a.length === b.length && [...a].sort((x, y) => rank(x) - rank(y)).join() === b.join();

export function ShortcutsSection() {
  const [held, setHeld] = useState<string[]>([]);
  const [hit, setHit] = useState<{ index: number; seq: number } | null>(null);
  const [echo, setEcho] = useState<{ keys: string[]; label: string | null; seq: number } | null>(null);
  const seq = useRef(0);

  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      const keys = combo(e);
      setHeld(keys);
      const hasKey = keys.some((k) => !order.includes(k));
      const hasModifier = keys.some((k) => order.includes(k));
      if (!hasKey || !hasModifier) return;
      const index = shortcuts.findIndex((s) => sameCombo(keys, s.keys));
      seq.current += 1;
      setEcho({ keys, label: index >= 0 ? shortcuts[index].label : null, seq: seq.current });
      if (index >= 0) setHit({ index, seq: seq.current });
    };
    const up = (e: KeyboardEvent) => setHeld(combo(e).filter((k) => order.includes(k)));
    const clear = () => setHeld([]);
    window.addEventListener("keydown", down);
    window.addEventListener("keyup", up);
    window.addEventListener("blur", clear);
    return () => {
      window.removeEventListener("keydown", down);
      window.removeEventListener("keyup", up);
      window.removeEventListener("blur", clear);
    };
  }, []);

  useEffect(() => {
    if (!hit) return;
    const timer = window.setTimeout(() => setHit((h) => (h?.seq === hit.seq ? null : h)), 1200);
    return () => window.clearTimeout(timer);
  }, [hit]);

  return (
    <section id="shortcuts" className="mx-auto max-w-5xl scroll-mt-24 px-6 py-24 sm:py-32">
      <div className="flex flex-col gap-10 lg:flex-row lg:items-end lg:justify-between">
        <SectionHeading
          eyebrow="Shortcuts"
          title={
            <>
              Hands stay on <Serif>the keys</Serif>.
            </>
          }
        >
          Everything in Jot has a shortcut. Press any of them right here and watch the list light up.
        </SectionHeading>

        <div className="flex h-14 min-w-[280px] items-center justify-center rounded-2xl border border-line bg-raised px-5" aria-live="polite">
          <AnimatePresence mode="wait" initial={false}>
            {echo ? (
              <motion.div
                key={echo.seq}
                initial={{ opacity: 0, y: 6 }}
                animate={{ opacity: 1, y: 0 }}
                exit={{ opacity: 0, y: -6 }}
                transition={{ duration: 0.18 }}
                className="flex items-center gap-3 text-[14px]"
              >
                <span className="flex gap-1 text-[15px]">
                  {echo.keys.map((k) => (
                    <kbd key={k} className="kbd" data-active>
                      {k}
                    </kbd>
                  ))}
                </span>
                <span className={echo.label ? "text-fg" : "text-faint"}>{echo.label ?? "Not a Jot shortcut"}</span>
              </motion.div>
            ) : (
              <motion.p key="idle" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} className="text-[14px] text-faint">
                Press a shortcut…
              </motion.p>
            )}
          </AnimatePresence>
        </div>
      </div>

      <ul className="mt-14 grid gap-x-10 border-t border-line sm:grid-cols-2">
        {shortcuts.map((s, i) => {
          const active = hit?.index === i;
          return (
            <li
              key={s.label}
              className={`relative flex items-center justify-between border-b border-line py-3.5 text-[15px] transition-colors duration-200 ${
                active ? "text-fg" : "text-muted"
              }`}
            >
              <motion.span
                aria-hidden
                className="absolute inset-y-1 -left-3 w-[2px] rounded-full bg-red"
                initial={false}
                animate={{ opacity: active ? 1 : 0, scaleY: active ? 1 : 0.4 }}
                transition={{ duration: 0.2 }}
              />
              {s.label}
              <span className="flex gap-1 text-[14px]">
                {s.keys.map((k) => (
                  <kbd key={k} className="kbd" data-active={active || (held.includes(k) && order.includes(k))}>
                    {k}
                  </kbd>
                ))}
              </span>
            </li>
          );
        })}
      </ul>
    </section>
  );
}

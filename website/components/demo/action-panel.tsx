"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useMemo, useRef, useState, type ComponentType, type SVGProps } from "react";
import { markdown, plainText } from "@/lib/note";
import { CopyIcon, MarkdownIcon, PinIcon, PlusIcon, ResetIcon, SearchIcon } from "../icons";
import { Keycaps } from "../keycap";
import { useNote } from "./store";

type Action = {
  id: string;
  title: string;
  section: string;
  icon: ComponentType<SVGProps<SVGSVGElement>>;
  keys?: string[];
  run: () => void;
};

/** Jot's ⌘K Action Panel: 320pt wide, 100pt below the window top, filterable, keyboard-driven. */
export function ActionPanel() {
  const { panelOpen } = useNote();
  return <AnimatePresence>{panelOpen && <Panel key="panel" />}</AnimatePresence>;
}

/** Mounted fresh on every open, so the search starts empty with the first action selected. */
function Panel() {
  const note = useNote();
  const { setPanel } = note;
  const [query, setQuery] = useState("");
  const [selected, setSelected] = useState(0);
  const input = useRef<HTMLInputElement>(null);

  const copy = async (text: string, title: string) => {
    try {
      await navigator.clipboard.writeText(text);
      note.showToast(title);
    } catch {
      note.showToast("Couldn't copy");
    }
  };

  const actions: Action[] = useMemo(
    () => [
      {
        id: "pin",
        title: note.pinned ? "Unpin Note" : "Pin Note",
        section: "Note",
        icon: PinIcon,
        keys: ["⇧", "⌘", "P"],
        run: note.togglePin,
      },
      {
        id: "new",
        title: "New Note",
        section: "Note",
        icon: PlusIcon,
        keys: ["⌘", "N"],
        run: note.newNote,
      },
      {
        id: "sample",
        title: "Restore Sample Note",
        section: "Note",
        icon: ResetIcon,
        run: () => note.reset(),
      },
      {
        id: "markdown",
        title: "Copy as Markdown",
        section: "Copy",
        icon: MarkdownIcon,
        keys: ["⇧", "⌘", "C"],
        run: () => copy(markdown(note.blocks), "Copied as Markdown"),
      },
      {
        id: "plain",
        title: "Copy as Plain Text",
        section: "Copy",
        icon: CopyIcon,
        run: () => copy(plainText(note.blocks), "Copied as Plain Text"),
      },
    ],
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [note.pinned, note.blocks],
  );

  const filtered = actions.filter((a) => a.title.toLowerCase().includes(query.trim().toLowerCase()));

  useEffect(() => {
    const frame = requestAnimationFrame(() => input.current?.focus());
    return () => cancelAnimationFrame(frame);
  }, []);

  const run = (action: Action | undefined) => {
    if (!action) return;
    setPanel(false);
    action.run();
  };

  let lastSection = "";

  return (
        <>
          <motion.button
            key="scrim"
            type="button"
            aria-label="Close actions"
            tabIndex={-1}
            className="absolute inset-0 z-20 cursor-default rounded-[inherit]"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={() => setPanel(false)}
          />
          <motion.div
            key="panel"
            role="dialog"
            aria-label="Actions"
            initial={{ opacity: 0, scale: 0.96, y: -6 }}
            animate={{ opacity: 1, scale: 1, y: 0, transition: { duration: 0.25, ease: [0.3, 0.7, 0, 1.26] } }}
            exit={{ opacity: 0, scale: 0.98, transition: { duration: 0.15 } }}
            className="absolute top-[100px] left-1/2 z-30 w-[min(320px,calc(100%-32px))] -translate-x-1/2 origin-top overflow-hidden rounded-2xl border border-white/10 bg-[rgb(36_36_36/0.82)] font-app shadow-[0_24px_60px_rgb(0_0_0/0.55)] backdrop-blur-2xl"
            onKeyDown={(e) => {
              if (e.key === "Escape") {
                e.preventDefault();
                e.stopPropagation();
                setPanel(false);
              } else if (e.key === "ArrowDown") {
                e.preventDefault();
                setSelected((s) => Math.min(filtered.length - 1, s + 1));
              } else if (e.key === "ArrowUp") {
                e.preventDefault();
                setSelected((s) => Math.max(0, s - 1));
              } else if (e.key === "Enter") {
                e.preventDefault();
                run(filtered[selected]);
              }
            }}
          >
            <label className="flex h-10 items-center gap-2 border-b border-white/[0.08] px-4">
              <SearchIcon className="size-[14px] text-white/40" />
              <input
                ref={input}
                value={query}
                onChange={(e) => {
                  setQuery(e.target.value);
                  setSelected(0);
                }}
                placeholder="Search for actions…"
                aria-label="Search for actions"
                className="h-full w-full bg-transparent text-[13px] text-white outline-none placeholder:text-white/35"
              />
            </label>
            <div className="max-h-[300px] overflow-y-auto p-2" role="listbox">
              {filtered.length === 0 && <p className="px-2 py-6 text-center text-[13px] text-white/40">No actions</p>}
              {filtered.map((action, i) => {
                const header = action.section !== lastSection ? action.section : null;
                lastSection = action.section;
                const Icon = action.icon;
                return (
                  <div key={action.id}>
                    {header && (
                      <p className={`px-2 pb-1 text-[11px] font-medium text-white/40 ${i === 0 ? "pt-0.5" : "pt-2"}`}>{header}</p>
                    )}
                    <button
                      type="button"
                      role="option"
                      aria-selected={i === selected}
                      onMouseMove={() => setSelected(i)}
                      onClick={() => run(action)}
                      className={`flex h-9 w-full items-center gap-2 rounded-[10px] px-2 text-left text-[13px] text-white transition-colors duration-100 ${
                        i === selected ? "bg-white/10" : ""
                      }`}
                    >
                      <Icon className="size-4 text-white/80" />
                      <span className="flex-1">{action.title}</span>
                      {action.keys && <Keycaps keys={action.keys} />}
                    </button>
                  </div>
                );
              })}
            </div>
          </motion.div>
        </>
  );
}

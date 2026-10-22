"use client";

import { useEffect, useRef, type PointerEvent, type ReactNode } from "react";
import { counts, title } from "@/lib/note";
import { CommandIcon, PinIcon, PlusIcon } from "../icons";
import { Keycaps } from "../keycap";
import { ActionPanel } from "./action-panel";
import { Editor } from "./editor";
import { useNote } from "./store";
import { Toast } from "./toast";

type Props = {
  /** The window's height (Tailwind classes); 440pt by default. */
  height?: string;
  /** The glass fill (Tailwind classes). */
  surface?: string;
  onHeaderPointerDown?: (event: PointerEvent<HTMLDivElement>) => void;
  onHeaderDoubleClick?: () => void;
  /** On phones, drop the frame: no title bar, glass or footer, just the note on the page. */
  bareOnMobile?: boolean;
  /** Turns the footer into a Raycast-style action bar with this as its ⌘↩ primary action. */
  primaryAction?: { title: string; icon?: ReactNode; pressed?: boolean; onRun: () => void };
};

/**
 * Jot's scroll-area "chrome" fade: content fades under the header (84pt, down to 15% halfway)
 * and the footer (76pt, down to 25%), ramping in as there is more to scroll that way.
 */
function applyEdgeFade(el: HTMLElement) {
  const max = el.scrollHeight - el.clientHeight;
  const top = max > 1 ? Math.min(1, el.scrollTop / 84) : 0;
  const bottom = max > 1 ? Math.min(1, (max - el.scrollTop) / 76) : 0;
  const a = (v: number) => `rgb(0 0 0 / ${v.toFixed(3)})`;
  const mask = `linear-gradient(to bottom, ${a(1 - top)} 0px, ${a(1 - 0.85 * top)} ${42 * top}px, black 84px, black calc(100% - 76px), ${a(1 - 0.75 * bottom)} calc(100% - ${38 * bottom}px), ${a(1 - bottom)} 100%)`;
  el.style.maskImage = mask;
  el.style.webkitMaskImage = mask;
}

/**
 * A working replica of the Jot window: Liquid Glass chrome, a 52pt header with the title
 * centred between the traffic lights and a glass button group, the editor, and the counter
 * (or, with a primary action, an action bar).
 */
export function JotWindow({
  height = "h-[440px]",
  surface = "border-white/[0.09] bg-[rgb(26_26_26/0.62)]",
  onHeaderPointerDown,
  onHeaderDoubleClick,
  primaryAction,
  bareOnMobile = false,
}: Props) {
  const note = useNote();
  const scroller = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = scroller.current;
    if (!el) return;
    const update = () => applyEdgeFade(el);
    update();
    const observer = new ResizeObserver(update);
    observer.observe(el);
    if (el.firstElementChild) observer.observe(el.firstElementChild);
    el.addEventListener("scroll", update, { passive: true });
    return () => {
      observer.disconnect();
      el.removeEventListener("scroll", update);
    };
  }, []);
  const { characters, words } = counts(note.blocks);
  const counter =
    note.counter === "characters"
      ? `${characters} ${characters === 1 ? "character" : "characters"}`
      : `${words} ${words === 1 ? "word" : "words"}`;

  return (
    <div
      className={`group/window relative flex ${height} w-full flex-col overflow-hidden rounded-[26px] border ${surface} shadow-[0_40px_120px_-20px_rgb(0_0_0/0.8),0_0_0_0.5px_rgb(0_0_0/0.6)] backdrop-blur-[40px] backdrop-saturate-150 ${
        bareOnMobile
          ? "max-sm:h-auto max-sm:overflow-visible max-sm:rounded-none max-sm:border-0 max-sm:bg-transparent max-sm:shadow-none max-sm:backdrop-blur-none max-sm:backdrop-saturate-100"
          : ""
      }`}
      role="application"
      aria-label="Jot note window"
    >
      {/* Header */}
      <div
        className={`relative z-10 grid h-[52px] shrink-0 cursor-grab touch-none grid-cols-[1fr_auto] items-center gap-4 px-2 select-none active:cursor-grabbing sm:grid-cols-[92px_1fr_92px] ${bareOnMobile ? "max-sm:hidden" : ""}`}
        onPointerDown={(e) => {
          if ((e.target as HTMLElement).closest("button")) return;
          onHeaderPointerDown?.(e);
        }}
        onDoubleClick={(e) => {
          if ((e.target as HTMLElement).closest("button")) return;
          onHeaderDoubleClick?.();
        }}
      >
        <div className="hidden items-center gap-2 pl-3 opacity-0 transition-opacity duration-150 group-hover/window:opacity-100 sm:flex">
          <TrafficLight className="bg-[#ff5f57]" label="Hide window" onClick={() => note.setVisible(false)} />
          <TrafficLight className="bg-[#febc2e]" label="Hide window" onClick={() => note.setVisible(false)} />
          <TrafficLight className="bg-[#28c840]" label="Zoom" />
        </div>
        <p className="truncate pl-3 text-left font-app text-[13px] text-white/60 transition-opacity duration-150 group-hover/window:opacity-100 sm:pl-0 sm:text-center sm:opacity-60">
          {title(note.blocks)}
        </p>
        <div className="flex h-9 items-center justify-self-end rounded-full border border-white/[0.08] bg-white/[0.06] p-1 opacity-100 shadow-[inset_0_1px_0_rgb(255_255_255/0.06)] transition-opacity duration-150 sm:opacity-0 sm:group-hover/window:opacity-100">
          <ChromeButton label="Actions (⌘K)" onClick={() => note.setPanel(true)}>
            <CommandIcon className="size-[15px]" />
          </ChromeButton>
          <ChromeButton label={note.pinned ? "Unpin note (⇧⌘P)" : "Pin note (⇧⌘P)"} onClick={note.togglePin} active={note.pinned}>
            <PinIcon className="size-[15px]" />
          </ChromeButton>
          <ChromeButton label="New note (⌘N)" onClick={note.newNote}>
            <PlusIcon className="size-[15px]" />
          </ChromeButton>
        </div>
      </div>

      {/* A soft blur under the title bar, strongest at the top (Jot's progressive header blur). */}
      <div
        aria-hidden
        className={`pointer-events-none absolute inset-x-0 top-0 z-[5] h-[52px] backdrop-blur-[3px] ${bareOnMobile ? "max-sm:hidden" : ""}`}
        style={{ maskImage: "linear-gradient(to bottom, black 20%, transparent)" }}
      />

      {/* Editor, fading under the chrome like Jot's scroll edges */}
      <div
        ref={scroller}
        data-note-scroller
        className={`relative -mt-[52px] min-h-0 flex-1 overflow-y-auto overscroll-contain px-5 pt-[60px] pb-14 [scroll-padding-block:72px_64px] [scrollbar-width:none] sm:px-6 ${
          bareOnMobile ? "max-sm:mt-0 max-sm:overflow-visible max-sm:p-0" : ""
        }`}
      >
        <Editor />
      </div>

      {/* Footer: the counter, or an action bar around it */}
      {primaryAction ? (
        <div className={`absolute inset-x-0 bottom-0 z-10 flex h-12 items-center justify-between border-t border-white/[0.06] bg-[rgb(18_18_18/0.6)] pr-2 pl-3 font-app backdrop-blur-xl ${bareOnMobile ? "max-sm:hidden" : ""}`}>
          <button
            type="button"
            onClick={note.toggleCounter}
            className="rounded-md px-2 py-1 text-[13px] text-white/40 tabular-nums transition-colors duration-150 hover:text-white/70"
            aria-label={`${counter}, switch counter`}
          >
            {counter}
          </button>
          {/* Raycast's primary action: the keycaps inset 6pt from the top, bottom and right edge. */}
          <button
            type="button"
            onClick={primaryAction.onRun}
            data-pressed={primaryAction.pressed}
            className="flex h-8 items-center gap-2 rounded-lg pr-1.5 pl-2.5 text-[13px] text-white transition-[background-color,transform] duration-150 hover:bg-white/[0.07] active:scale-[0.98] data-[pressed=true]:bg-white/10"
          >
            {primaryAction.icon}
            <span className="ml-0.5">{primaryAction.title}</span>
            {/* No keyboard on a touch screen, so no shortcut to show. */}
            <span className="[@media(pointer:coarse)]:hidden">
              <Keycaps keys={["⌘", "↩"]} active={primaryAction.pressed} />
            </span>
          </button>
        </div>
      ) : (
        <div className="pointer-events-none absolute inset-x-0 bottom-0 flex h-12 items-center justify-center">
          <button
            type="button"
            onClick={note.toggleCounter}
            className="pointer-events-auto rounded-md px-2 py-1 font-app text-[13px] text-white/40 tabular-nums transition-colors duration-150 hover:text-white/70"
            aria-label={`${counter}, switch counter`}
          >
            {counter}
          </button>
        </div>
      )}

      <Toast />
      <ActionPanel />
    </div>
  );
}

function TrafficLight({ className, label, onClick }: { className: string; label: string; onClick?: () => void }) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      className={`size-3 rounded-full shadow-[inset_0_0_0_0.5px_rgb(0_0_0/0.25)] ${className}`}
    />
  );
}

function ChromeButton({
  label,
  onClick,
  active,
  children,
}: {
  label: string;
  onClick: () => void;
  active?: boolean;
  children: ReactNode;
}) {
  return (
    <button
      type="button"
      title={label}
      aria-label={label}
      aria-pressed={active}
      onClick={onClick}
      className={`flex size-7 items-center justify-center rounded-full transition-[background-color,color,transform] duration-150 hover:bg-white/[0.07] active:scale-95 active:bg-white/10 ${
        active ? "text-red" : "text-white/85"
      }`}
    >
      {children}
    </button>
  );
}

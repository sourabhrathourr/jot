"use client";

import { AnimatePresence, motion } from "motion/react";
import { useEffect, useLayoutEffect, useRef, useState, useSyncExternalStore, type ClipboardEvent, type CSSProperties, type DragEvent, type KeyboardEvent } from "react";
import { createPortal } from "react-dom";
import { block, imageSize, isList, prefixRules, type Block, type BlockKind } from "@/lib/note";
import { useNote } from "./store";

// MARK: Caret helpers

function caretOffset(el: HTMLElement): number {
  const selection = window.getSelection();
  if (!selection || selection.rangeCount === 0) return 0;
  const range = selection.getRangeAt(0);
  if (!el.contains(range.endContainer)) return 0;
  const before = range.cloneRange();
  before.selectNodeContents(el);
  before.setEnd(range.endContainer, range.endOffset);
  return before.toString().length;
}

function placeCaret(el: HTMLElement, offset: number) {
  const selection = window.getSelection();
  if (!selection) return;
  const range = document.createRange();
  let remaining = offset;
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  let node = walker.nextNode();
  while (node) {
    const length = node.textContent?.length ?? 0;
    if (remaining <= length) {
      range.setStart(node, remaining);
      range.collapse(true);
      selection.removeAllRanges();
      selection.addRange(range);
      return;
    }
    remaining -= length;
    node = walker.nextNode();
  }
  range.selectNodeContents(el);
  range.collapse(false);
  selection.removeAllRanges();
  selection.addRange(range);
}

/** Whether the caret sits on the first (or last) visual line of the element. */
function caretOnEdgeLine(el: HTMLElement, edge: "top" | "bottom"): boolean {
  const selection = window.getSelection();
  if (!el.textContent || !selection || selection.rangeCount === 0) return true;
  const rects = selection.getRangeAt(0).getClientRects();
  const rect = rects[0];
  if (!rect) return true;
  const box = el.getBoundingClientRect();
  const lineHeight = parseFloat(getComputedStyle(el).lineHeight) || 24;
  return edge === "top" ? rect.top - box.top < lineHeight * 0.75 : box.bottom - rect.bottom < lineHeight * 0.75;
}

const fence = /^(?:```|~~~)[a-z+#-]*$/;

/** Image files from a paste or drop, measured, as image blocks (object URLs stay in this tab). */
function imageBlocks(files: File[]): Promise<Block[]> {
  const images = files.filter((file) => file.type.startsWith("image/"));
  return Promise.all(
    images.map(
      (file) =>
        new Promise<Block | null>((resolve) => {
          const src = URL.createObjectURL(file);
          const img = new Image();
          img.onload = () => resolve({ ...block("image"), image: { src, width: img.naturalWidth, height: img.naturalHeight } });
          img.onerror = () => resolve(null);
          img.src = src;
        }),
    ),
  ).then((blocks) => blocks.filter((b): b is Block => b !== null));
}

// MARK: Editor

export function Editor() {
  const note = useNote();
  const { blocks, focus, edit } = note;
  const refs = useRef(new Map<string, HTMLElement>());
  const [preview, setPreview] = useState<Block | null>(null);
  // The note's lines blur in one after another when the window first appears.
  const [revealing, setRevealing] = useState(true);
  useEffect(() => {
    const timer = window.setTimeout(() => setRevealing(false), 1800);
    return () => window.clearTimeout(timer);
  }, []);

  // Apply caret requests from edits (split, merge, input rules, the cheat sheet).
  useLayoutEffect(() => {
    if (!focus) return;
    const el = refs.current.get(focus.id);
    if (!el) return;
    el.focus({ preventScroll: true });
    if (el.isContentEditable) placeCaret(el, focus.offset);
    // Keep the caret's block clear of the header and footer fades, inside the note only.
    const scroller = el.closest<HTMLElement>("[data-note-scroller]");
    if (scroller) {
      const box = el.getBoundingClientRect();
      const view = scroller.getBoundingClientRect();
      if (box.bottom > view.bottom - 64) scroller.scrollTop += box.bottom - (view.bottom - 64);
      else if (box.top < view.top + 72) scroller.scrollTop -= view.top + 72 - box.top;
    }
  }, [focus]);

  const replace = (index: number, next: Block[], focusAt?: { id: string; offset: number }) => {
    const copy = [...blocks];
    copy.splice(index, 1, ...next);
    edit(copy, focusAt);
  };

  const setKind = (index: number, kind: BlockKind, text: string, offset = 0) => {
    const current = blocks[index];
    replace(index, [{ ...current, kind, text, checked: kind === "task" ? false : undefined }], { id: current.id, offset });
  };

  /** ⌘K, ⇧⌘P and Esc work from any block. */
  const handleWindowKeys = (event: KeyboardEvent<HTMLElement>) => {
    const meta = event.metaKey || event.ctrlKey;
    if (meta && event.key.toLowerCase() === "k") {
      event.preventDefault();
      note.setPanel(true);
      return true;
    }
    if (meta && event.shiftKey && event.key.toLowerCase() === "p") {
      event.preventDefault();
      note.togglePin();
      return true;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      event.currentTarget.blur();
      note.setVisible(false);
      return true;
    }
    return false;
  };

  /** Puts the caret at the end of the block before `index` (or selects it, if it's an image). */
  const focusNeighbour = (copy: Block[], index: number, forward: boolean) => {
    const target = forward ? copy[index] : copy[index - 1];
    if (!target) return edit(copy);
    edit(copy, { id: target.id, offset: forward ? 0 : target.text.length });
  };

  /** A selected image, like Jot's: Space previews it, Enter adds a line, Backspace removes it. */
  const onImageKeyDown = (event: KeyboardEvent<HTMLElement>, index: number) => {
    if (handleWindowKeys(event)) return;
    const current = blocks[index];
    if (event.key === " ") {
      event.preventDefault();
      setPreview(current);
    } else if (event.key === "Backspace" || event.key === "Delete") {
      event.preventDefault();
      const copy = blocks.filter((_, i) => i !== index);
      focusNeighbour(copy, index, index === 0);
    } else if (event.key === "Enter") {
      event.preventDefault();
      const added = block("p");
      const copy = [...blocks];
      copy.splice(index + 1, 0, added);
      edit(copy, { id: added.id, offset: 0 });
    } else if (event.key === "ArrowUp" || event.key === "ArrowLeft") {
      event.preventDefault();
      focusNeighbour(blocks, index, false);
    } else if (event.key === "ArrowDown" || event.key === "ArrowRight") {
      event.preventDefault();
      focusNeighbour(blocks, index + 1, true);
    } else if (event.key.length === 1 && !event.metaKey && !event.ctrlKey) {
      // Typing over a selected image replaces it with text.
      event.preventDefault();
      const added = block("p", event.key);
      replace(index, [added], { id: added.id, offset: 1 });
    }
  };

  /** Inserts image blocks after `index` (replacing it if it's an empty paragraph), with a line below. */
  const insertImages = async (files: File[], index: number) => {
    const images = await imageBlocks(files);
    if (!images.length) return false;
    const current = blocks[index];
    const after = block("p");
    const copy = [...blocks];
    if (current?.kind === "p" && !current.text) copy.splice(index, 1, ...images, after);
    else copy.splice(index + 1, 0, ...images, after);
    note.setVisible(true);
    edit(copy, { id: after.id, offset: 0 });
    return true;
  };

  const onDrop = (event: DragEvent<HTMLDivElement>) => {
    const files = [...event.dataTransfer.files];
    if (!files.some((f) => f.type.startsWith("image/"))) return;
    event.preventDefault();
    const target = (event.target as HTMLElement).closest<HTMLElement>("[data-index]");
    void insertImages(files, target ? Number(target.dataset.index) : blocks.length - 1);
  };

  const onKeyDown = (event: KeyboardEvent<HTMLDivElement>, index: number) => {
    const current = blocks[index];
    const el = event.currentTarget;
    const meta = event.metaKey || event.ctrlKey;
    if (handleWindowKeys(event)) return;

    const offset = caretOffset(el);
    const text = el.textContent ?? "";
    const before = text.slice(0, offset);
    const after = text.slice(offset);

    if (event.key === "Enter") {
      // ⌘↩ outside a code block belongs to the page (on /v2 it downloads Jot).
      if (meta && current.kind !== "code") return;
      event.preventDefault();
      if (event.nativeEvent.isComposing) return;
      // Shift-Enter and ⌘-Enter leave a code block, like Jot.
      if (current.kind === "code" && (event.shiftKey || meta)) {
        let end = index;
        while (blocks[end + 1]?.kind === "code") end++;
        const added = block("p");
        const copy = [...blocks];
        copy.splice(end + 1, 0, added);
        edit(copy, { id: added.id, offset: 0 });
        return;
      }
      if (current.kind === "p" && fence.test(before)) {
        setKind(index, "code", after);
        return;
      }
      if ((isList(current.kind) || current.kind === "quote") && !text) {
        setKind(index, "p", "");
        return;
      }
      const nextKind: BlockKind = isList(current.kind) || current.kind === "code" || current.kind === "quote" ? current.kind : "p";
      const added = block(nextKind, after, nextKind === "task" ? false : undefined);
      replace(index, [{ ...current, text: before }, added], { id: added.id, offset: 0 });
      return;
    }

    if (event.key === " " && current.kind === "p" && offset === before.length) {
      const rule = prefixRules[before] ?? (/^\d+\.$/.test(before) ? "ordered" : fence.test(before) ? "code" : undefined);
      if (rule) {
        event.preventDefault();
        setKind(index, rule, after);
        return;
      }
    }

    if (event.key === "Backspace" && offset === 0 && window.getSelection()?.isCollapsed) {
      const previous = blocks[index - 1];
      // After an image, Backspace selects it first (and an empty line goes away), like Jot.
      if (previous?.kind === "image") {
        event.preventDefault();
        const copy = text ? blocks : blocks.filter((_, i) => i !== index);
        edit(copy, { id: previous.id, offset: 0 });
        return;
      }
      if (current.kind === "code" && previous?.kind === "code") {
        event.preventDefault();
        const copy = [...blocks];
        copy.splice(index - 1, 2, { ...previous, text: previous.text + text });
        edit(copy, { id: previous.id, offset: previous.text.length });
        return;
      }
      if (current.kind !== "p") {
        event.preventDefault();
        setKind(index, "p", text);
        return;
      }
      if (!previous) return;
      event.preventDefault();
      const copy = [...blocks];
      if (previous.kind === "rule") {
        copy.splice(index - 1, 1);
        edit(copy, { id: current.id, offset: 0 });
        return;
      }
      copy.splice(index - 1, 2, { ...previous, text: previous.text + text });
      edit(copy, { id: previous.id, offset: previous.text.length });
      return;
    }

    if (event.key === "Tab" && current.kind === "code") {
      event.preventDefault();
      document.execCommand("insertText", false, "\t");
      return;
    }

    if (event.key === "ArrowUp" || event.key === "ArrowDown") {
      const up = event.key === "ArrowUp";
      if (!caretOnEdgeLine(el, up ? "top" : "bottom")) return;
      let target = index + (up ? -1 : 1);
      while (blocks[target]?.kind === "rule") target += up ? -1 : 1;
      const next = blocks[target];
      if (!next) return;
      event.preventDefault();
      edit(blocks, { id: next.id, offset: Math.min(offset, next.text.length) });
    }
  };

  const onInput = (index: number, el: HTMLDivElement) => {
    const current = blocks[index];
    const text = (el.textContent ?? "").replace(/\n/g, "");
    if (current.kind === "p" && text === "---") {
      const after = block("p");
      replace(index, [{ ...current, kind: "rule", text: "" }, after], { id: after.id, offset: 0 });
      return;
    }
    const copy = [...blocks];
    copy[index] = { ...current, text };
    edit(copy);
  };

  /** Pasted text goes in as plain lines: the first joins the caret's block, the rest follow it. */
  const onPaste = (event: ClipboardEvent<HTMLDivElement>, index: number) => {
    event.preventDefault();
    const files = [...event.clipboardData.files];
    if (files.some((f) => f.type.startsWith("image/"))) {
      void insertImages(files, index);
      return;
    }
    const lines = event.clipboardData.getData("text/plain").replace(/\r\n?/g, "\n").split("\n");
    const el = event.currentTarget;
    if (lines.length === 1) {
      document.execCommand("insertText", false, lines[0]);
      return;
    }
    const current = blocks[index];
    const offset = caretOffset(el);
    const text = el.textContent ?? "";
    const kind: BlockKind = current.kind === "code" ? "code" : "p";
    const rest = lines.slice(1).map((line, i, all) => block(kind, i === all.length - 1 ? line + text.slice(offset) : line));
    const last = rest[rest.length - 1];
    replace(index, [{ ...current, text: text.slice(0, offset) + lines[0] }, ...rest], {
      id: last.id,
      offset: lines[lines.length - 1].length,
    });
  };

  return (
    <div
      className="font-app text-[15px] leading-[1.6] text-white/90 [text-wrap:pretty]"
      data-revealing={revealing}
      onDragOver={(e) => {
        if (e.dataTransfer.types.includes("Files")) e.preventDefault();
      }}
      onDrop={onDrop}
    >
      {blocks.map((b, index) => (
        <div key={b.id} data-line style={{ "--i": index } as CSSProperties}>
        {b.kind === "image" && b.image ? (
          <ImageBlock
            key={b.id}
            block={b}
            index={index}
            first={index === 0}
            afterImage={blocks[index - 1]?.kind === "image"}
            register={(el) => {
              if (el) refs.current.set(b.id, el);
              else refs.current.delete(b.id);
            }}
            onKeyDown={(e) => onImageKeyDown(e, index)}
            onPreview={() => setPreview(b)}
          />
        ) : (
        <BlockView
          key={b.id}
          block={b}
          index={index}
          blocks={blocks}
          register={(el) => {
            if (el) refs.current.set(b.id, el);
            else refs.current.delete(b.id);
          }}
          onKeyDown={(e) => onKeyDown(e, index)}
          onInput={(el) => onInput(index, el)}
          onPaste={(e) => onPaste(e, index)}
          onToggle={() => replace(index, [{ ...b, checked: !b.checked }])}
          placeholder={blocks.length <= 2 && index === 0 && !b.text ? "Write something …" : placeholderFor(b.kind)}
        />
        )}
        </div>
      ))}
      <ImagePreview block={preview} onClose={() => setPreview(null)} />
    </div>
  );
}

// MARK: Images

/** The sample note's picture: soft light in Jot's reds, drawn rather than shipped as a photo. */
const sampleArt =
  "radial-gradient(55% 90% at 18% 30%, #ff6363 0%, transparent 62%), radial-gradient(45% 80% at 82% 75%, #8c1a28 0%, transparent 65%), radial-gradient(35% 60% at 62% 18%, rgb(255 209 196 / 0.55) 0%, transparent 60%), linear-gradient(135deg, #2a1012, #120809)";

function ImageBlock({
  block: b,
  index,
  first,
  afterImage,
  register,
  onKeyDown,
  onPreview,
}: {
  block: Block;
  index: number;
  first: boolean;
  afterImage: boolean;
  register: (el: HTMLElement | null) => void;
  onKeyDown: (event: KeyboardEvent<HTMLElement>) => void;
  onPreview: () => void;
}) {
  const image = b.image!;
  const { width } = imageSize(image, 640);
  return (
    <figure
      ref={register}
      data-index={index}
      tabIndex={0}
      role="img"
      aria-label="Note image. Space to preview."
      title="Double-click or press Space to preview"
      onKeyDown={onKeyDown}
      onDoubleClick={onPreview}
      data-kind="image"
      className={`relative overflow-hidden rounded-lg outline-offset-0 focus:outline-2 focus:outline-white/60 ${first ? "" : afterImage ? "mt-6" : "mt-3"} mb-3`}
      style={{ width: `min(100%, ${width}px)`, aspectRatio: `${image.width} / ${image.height}` }}
    >
      {image.src ? (
        // eslint-disable-next-line @next/next/no-img-element -- a local object URL, not an optimisable asset
        <img src={image.src} alt="" draggable={false} className="absolute inset-0 size-full object-contain" />
      ) : (
        <div className="absolute inset-0" style={{ background: sampleArt }} />
      )}
    </figure>
  );
}

/** Quick Look, in the browser: the image grows out of the note; Space, Esc or a click closes it. */
function ImagePreview({ block: b, onClose }: { block: Block | null; onClose: () => void }) {
  useEffect(() => {
    if (!b) return;
    const onKey = (e: globalThis.KeyboardEvent) => {
      if (e.key === " " || e.key === "Escape") {
        e.preventDefault();
        e.stopPropagation();
        onClose();
      }
    };
    window.addEventListener("keydown", onKey, true);
    return () => window.removeEventListener("keydown", onKey, true);
  }, [b, onClose]);

  if (typeof document === "undefined") return null;
  return createPortal(
    <AnimatePresence>
      {b?.image && (
        <motion.div
          key="preview"
          role="dialog"
          aria-label="Image preview"
          className="fixed inset-0 z-[100] flex items-center justify-center bg-black/70 p-[6vmin] backdrop-blur-md"
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          exit={{ opacity: 0, transition: { duration: 0.15 } }}
          onClick={onClose}
        >
          <motion.div
            initial={{ scale: 0.92, opacity: 0 }}
            animate={{ scale: 1, opacity: 1, transition: { duration: 0.3, ease: [0.3, 0.7, 0, 1.06] } }}
            exit={{ scale: 0.96, opacity: 0, transition: { duration: 0.15 } }}
            className="max-h-full max-w-full overflow-hidden rounded-xl shadow-[0_40px_120px_rgb(0_0_0/0.6)]"
            style={{ aspectRatio: `${b.image.width} / ${b.image.height}`, width: `min(100%, ${b.image.width}px, calc(88vh * ${b.image.width / b.image.height}))` }}
          >
            {b.image.src ? (
              // eslint-disable-next-line @next/next/no-img-element -- a local object URL
              <img src={b.image.src} alt="" className="size-full object-contain" />
            ) : (
              <div className="size-full" style={{ background: sampleArt }} />
            )}
          </motion.div>
        </motion.div>
      )}
    </AnimatePresence>,
    document.body,
  );
}

const kindNames: Record<BlockKind, string> = {
  p: "Text",
  h1: "Heading 1",
  h2: "Heading 2",
  h3: "Heading 3",
  bullet: "Bullet",
  ordered: "Numbered item",
  task: "Task",
  quote: "Quote",
  code: "Code",
  rule: "Divider",
  image: "Image",
};

function placeholderFor(kind: BlockKind) {
  switch (kind) {
    case "h1":
      return "Heading 1";
    case "h2":
      return "Heading 2";
    case "h3":
      return "Heading 3";
    case "quote":
      return "Quote";
    default:
      return "";
  }
}

// MARK: Blocks

type BlockViewProps = {
  block: Block;
  index: number;
  blocks: Block[];
  register: (el: HTMLDivElement | null) => void;
  onKeyDown: (event: KeyboardEvent<HTMLDivElement>) => void;
  onInput: (el: HTMLDivElement) => void;
  onPaste: (event: ClipboardEvent<HTMLDivElement>) => void;
  onToggle: () => void;
  placeholder: string;
};

/** Touch screens (phones, tablets): the note is for reading there. Editable text would open the
 * keyboard and zoom the page on a stray tap, so blocks aren't editable on them. */
const coarsePointer = "(pointer: coarse)";
function useTouchScreen() {
  return useSyncExternalStore(
    (onChange) => {
      const query = window.matchMedia(coarsePointer);
      query.addEventListener("change", onChange);
      return () => query.removeEventListener("change", onChange);
    },
    () => window.matchMedia(coarsePointer).matches,
    () => false,
  );
}

function BlockView({ block: b, index, blocks, register, onKeyDown, onInput, onPaste, onToggle, placeholder }: BlockViewProps) {
  const ref = useRef<HTMLDivElement | null>(null);
  // Rendered once so the server sends the note already written; React never updates it again
  // (the DOM owns the text while typing), and a remounted box is corrected in its ref.
  const [initialText] = useState(b.text);
  const touchScreen = useTouchScreen();

  // The DOM owns the text while typing; only external changes are written back.
  useLayoutEffect(() => {
    const el = ref.current;
    if (el && el.textContent !== b.text) el.textContent = b.text;
  }, [b.text]);

  if (b.kind === "rule") {
    return <div role="separator" className="my-4 h-[2px] rounded-full bg-white/12" />;
  }

  const previous = blocks[index - 1];
  const next = blocks[index + 1];
  const editable = (
    <div
      ref={(el) => {
        ref.current = el;
        if (el && el.textContent !== b.text) el.textContent = b.text;
        register(el);
      }}
      contentEditable={touchScreen ? undefined : "plaintext-only"}
      aria-readonly={touchScreen || undefined}
      suppressContentEditableWarning
      spellCheck={false}
      role="textbox"
      aria-label={kindNames[b.kind]}
      data-placeholder={placeholder}
      data-index={index}
      data-kind={b.kind}
      onKeyDown={onKeyDown}
      onInput={(e) => onInput(e.currentTarget)}
      onPaste={onPaste}
      className={`note-block min-w-0 flex-1 ${textClass(b)}`}
    >
      {initialText}
    </div>
  );

  switch (b.kind) {
    case "bullet":
    case "ordered":
    case "task": {
      let number = 1;
      for (let i = index - 1; i >= 0 && blocks[i].kind === "ordered"; i--) number++;
      return (
        <div className={`flex items-start gap-2 ${isList(previous?.kind ?? "p") ? "mt-1" : "mt-2"}`}>
          <span className="flex h-[24px] w-[14px] shrink-0 items-center justify-center text-white/40" aria-hidden={b.kind !== "task"}>
            {b.kind === "bullet" && <span className="size-[5px] rounded-full bg-white/45" />}
            {b.kind === "ordered" && <span className="text-[14px] tabular-nums">{number}.</span>}
            {b.kind === "task" && (
              // Jot's checkbox (Raycast's): a 14pt, 1.5pt red ring with 5pt corners; checked, the
              // ring drops to 70% and an 8pt red square fills the middle. Sits on the text baseline.
              <button
                type="button"
                onClick={onToggle}
                aria-label={b.checked ? "Mark as not done" : "Mark as done"}
                aria-pressed={!!b.checked}
                className={`relative mt-px flex size-[14px] items-center justify-center rounded-[5px] border-[1.5px] transition-[border-color,transform] duration-150 active:scale-90 ${
                  b.checked ? "border-red/70" : "border-red"
                }`}
              >
                <span
                  className={`size-[8px] rounded-[2.5px] bg-red/70 transition-[transform,opacity] duration-150 ease-out ${
                    b.checked ? "scale-100 opacity-100" : "scale-50 opacity-0"
                  }`}
                />
              </button>
            )}
          </span>
          {editable}
        </div>
      );
    }
    case "quote":
      return (
        <div className={`flex ${previous?.kind === "quote" ? "" : "mt-2"}`}>
          <span className="mr-3 w-[2px] shrink-0 rounded-full bg-red" aria-hidden />
          {editable}
        </div>
      );
    case "code": {
      const first = previous?.kind !== "code";
      const last = next?.kind !== "code";
      return (
        <div
          className={`flex bg-white/[0.05] px-3 ${first ? "mt-3 rounded-t-xl pt-2" : ""} ${last ? "mb-3 rounded-b-xl pb-3" : ""}`}
        >
          {editable}
        </div>
      );
    }
    default:
      return <div className={`flex ${marginFor(b.kind, index)}`}>{editable}</div>;
  }
}

function marginFor(kind: BlockKind, index: number) {
  if (index === 0) return "";
  switch (kind) {
    case "h1":
      return "mt-6";
    case "h2":
    case "h3":
      return "mt-4";
    default:
      return "mt-2";
  }
}

function textClass(b: Block) {
  switch (b.kind) {
    case "h1":
      return "text-[22px] leading-[1.35] font-semibold tracking-[-0.01em] text-white";
    case "h2":
      return "text-[18px] leading-[1.4] font-semibold text-white";
    case "h3":
      return "text-[16px] leading-[1.45] font-semibold text-white";
    case "task":
      return b.checked ? "text-white/70" : "";
    case "quote":
      return "text-white/75";
    case "code":
      return "font-mono text-[13px] leading-[1.5] text-white/80 [tab-size:2]";
    default:
      return "";
  }
}

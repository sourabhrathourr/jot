"use client";

import { createContext, useCallback, useContext, useMemo, useReducer, type ReactNode } from "react";
import { block, landingNote, pitchNote, sampleNote, type Block, type BlockKind } from "@/lib/note";

type Focus = { id: string; offset: number; seq: number };

type State = {
  blocks: Block[];
  /** A caret placement the editor should apply on its next render. */
  focus: Focus | null;
  visible: boolean;
  pinned: boolean;
  panelOpen: boolean;
  toast: { title: string; seq: number } | null;
  counter: "characters" | "words";
};

type Action =
  | { type: "edit"; blocks: Block[]; focus?: { id: string; offset: number } }
  | { type: "visible"; value: boolean }
  | { type: "pin" }
  | { type: "panel"; open: boolean }
  | { type: "toast"; title: string }
  | { type: "counter" }
  | { type: "reset"; blocks: Block[] };

let seq = 0;

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case "edit":
      return { ...state, blocks: action.blocks, focus: action.focus ? { ...action.focus, seq: ++seq } : state.focus };
    case "visible":
      return { ...state, visible: action.value, panelOpen: action.value ? state.panelOpen : false };
    case "pin":
      return { ...state, pinned: !state.pinned, toast: { title: state.pinned ? "Unpinned Note" : "Pinned Note", seq: ++seq } };
    case "panel":
      return { ...state, panelOpen: action.open };
    case "toast":
      return { ...state, toast: { title: action.title, seq: ++seq } };
    case "counter":
      return { ...state, counter: state.counter === "characters" ? "words" : "characters" };
    case "reset":
      return { ...state, blocks: action.blocks, focus: null };
  }
}

type Note = State & {
  edit: (blocks: Block[], focus?: { id: string; offset: number }) => void;
  setVisible: (value: boolean) => void;
  togglePin: () => void;
  setPanel: (open: boolean) => void;
  showToast: (title: string) => void;
  toggleCounter: () => void;
  reset: (blocks?: Block[]) => void;
  /** An empty note with the caret in it. */
  newNote: () => void;
  /** Adds an example block at the end of the note (from the cheat sheet) and shows the window. */
  tryBlock: (kind: BlockKind, text: string) => void;
};

const NoteContext = createContext<Note | null>(null);

const notes = { sample: sampleNote, landing: landingNote, pitch: pitchNote };

/** `note` picks the starting note (and what "Restore" brings back). A name, not a function, so
 * server components can choose it. */
export function NoteProvider({ children, note = "sample" }: { children: ReactNode; note?: keyof typeof notes }) {
  const initial = notes[note];
  const [state, dispatch] = useReducer(reducer, undefined, () => ({
    blocks: initial(),
    focus: null,
    visible: true,
    pinned: false,
    panelOpen: false,
    toast: null,
    counter: "characters" as const,
  }));

  const edit = useCallback(
    (blocks: Block[], focus?: { id: string; offset: number }) => dispatch({ type: "edit", blocks, focus }),
    [],
  );
  const setVisible = useCallback((value: boolean) => dispatch({ type: "visible", value }), []);
  const togglePin = useCallback(() => dispatch({ type: "pin" }), []);
  const setPanel = useCallback((open: boolean) => dispatch({ type: "panel", open }), []);
  const showToast = useCallback((title: string) => dispatch({ type: "toast", title }), []);
  const toggleCounter = useCallback(() => dispatch({ type: "counter" }), []);
  const reset = useCallback((blocks?: Block[]) => dispatch({ type: "reset", blocks: blocks ?? initial() }), [initial]);

  const newNote = useCallback(() => {
    const first = block("p");
    dispatch({ type: "edit", blocks: [first], focus: { id: first.id, offset: 0 } });
  }, []);

  const tryBlock = useCallback(
    (kind: BlockKind, text: string) => {
      const kept = [...state.blocks];
      while (kept.length && kept[kept.length - 1].kind === "p" && !kept[kept.length - 1].text) kept.pop();
      const added = block(kind, text);
      const blocks = [...kept, added, block("p")];
      const target = kind === "rule" ? blocks[blocks.length - 1] : added;
      dispatch({ type: "visible", value: true });
      dispatch({ type: "edit", blocks, focus: { id: target.id, offset: target.text.length } });
    },
    [state.blocks],
  );

  const value = useMemo<Note>(
    () => ({ ...state, edit, setVisible, togglePin, setPanel, showToast, toggleCounter, reset, newNote, tryBlock }),
    [state, edit, setVisible, togglePin, setPanel, showToast, toggleCounter, reset, newNote, tryBlock],
  );
  return <NoteContext value={value}>{children}</NoteContext>;
}

export function useNote() {
  const note = useContext(NoteContext);
  if (!note) throw new Error("useNote needs a NoteProvider");
  return note;
}

/** The demo note: a flat list of blocks, the same shape Jot keeps natively. */
export type BlockKind = "p" | "h1" | "h2" | "h3" | "bullet" | "ordered" | "task" | "quote" | "code" | "rule" | "image";

export type Block = {
  id: string;
  kind: BlockKind;
  text: string;
  checked?: boolean;
  /** An image block: its pixel size, and a URL (pasted/dropped images) or none (the sample art). */
  image?: { src?: string; width: number; height: number };
};

let counter = 0;
/** Ids only need to be unique within the page (and reading the clock would block prerendering). */
export const newId = () => `b${(counter++).toString(36)}`;

export const block = (kind: BlockKind, text = "", checked?: boolean): Block => ({ id: newId(), kind, text, checked });

export const sampleNote = (): Block[] => [
  block("h1", "Weekend plan"),
  block("p", "Everything to get done before Monday."),
  block("task", "Ship the landing page", true),
  block("task", "Book the climbing gym"),
  { ...block("image"), image: { width: 1200, height: 560 } },
  block("bullet", "Groceries: oranges, oat milk, coffee"),
  block("code", "let today = Date()"),
  block("code", "print(today)"),
  block("p", ""),
];

/** The /v2 page: the pitch, written as a note you can edit. */
export const landingNote = (): Block[] => [
  block("h1", "Raycast Notes, but free."),
  block("p", "Jot is a floating notes window for your Mac. It's native, it's open source, and it's yours."),
  block("task", "Unlimited notes", true),
  block("task", "Images included", true),
  block("task", "No account, no subscription", true),
  block("task", "Open source", true),
  { ...block("image"), image: { width: 1200, height: 420 } },
  block("h3", "Try it, right here"),
  block("bullet", "Type # and a space for a heading, - for a list, [] for a task"),
  block("bullet", "Paste or drop an image, then press Space to preview it"),
  block("bullet", "⌘K for actions, Esc to hide, N to bring it back"),
  block("p", ""),
];

/** v2's note: the original landing note's layout. Lines run most of the window's width and
 * stay close in length, so the note reads full and even rather than stepping down. */
export const pitchNote = (): Block[] => [
  block("h1", "Raycast Notes, but free."),
  block("p", "Fast, fully native notes for your Mac, always one shortcut away."),
  block("task", "Opens instantly, keeps up with every keystroke", true),
  block("task", "Invisible when you share your screen on calls", true),
  block("task", "Unlimited notes, with your images right inside", true),
  block("task", "Free and open source, with no account to make", true),
  { ...block("image"), image: { width: 1200, height: 420 } },
  block("h3", "Try it, right here"),
  block("bullet", "Type # and a space for a heading, - for a list, [] for a task"),
  block("bullet", "⌘K for actions, Esc to hide it, N to bring it back"),
  block("bullet", "Paste or drop an image, then press Space to preview it"),
  block("p", ""),
];

export const isList = (kind: BlockKind) => kind === "bullet" || kind === "ordered" || kind === "task";

/** Block input rules, fired when a space is typed after the prefix. */
export const prefixRules: Record<string, BlockKind> = {
  "#": "h1",
  "##": "h2",
  "###": "h3",
  "-": "bullet",
  "*": "bullet",
  "+": "bullet",
  "1.": "ordered",
  "[]": "task",
  "[ ]": "task",
  ">": "quote",
  "```": "code",
};

/** Jot's image sizing: `min(width, 640, 480 × aspect)`, never wider than the text. */
export function imageSize(image: { width: number; height: number }, available: number) {
  const aspect = image.width / image.height;
  const width = Math.round(Math.min(image.width, 640, 480 * aspect, available));
  return { width, height: Math.round(width / aspect) };
}

/** The note's text, the way Jot stores and counts it. */
export function plainText(blocks: Block[]): string {
  const chunks: string[] = [];
  let list: string[] = [];
  const flush = () => {
    if (list.length) chunks.push(list.join("\n"));
    list = [];
  };
  for (const b of blocks) {
    if (isList(b.kind)) {
      if (b.text) list.push(b.text);
      continue;
    }
    flush();
    if (b.kind === "image") chunks.push("[Image]");
    else if (b.kind !== "rule" && b.text) chunks.push(b.text);
  }
  flush();
  return chunks.join("\n\n");
}

export function markdown(blocks: Block[]): string {
  const out: string[] = [];
  let n = 0;
  blocks.forEach((b, i) => {
    const prev = blocks[i - 1];
    if (b.kind !== "ordered") n = 0;
    const tight = prev && ((isList(prev.kind) && isList(b.kind)) || (prev.kind === "quote" && b.kind === "quote"));
    if (prev && !tight) out.push("");
    switch (b.kind) {
      case "h1":
        return out.push(`# ${b.text}`);
      case "h2":
        return out.push(`## ${b.text}`);
      case "h3":
        return out.push(`### ${b.text}`);
      case "bullet":
        return out.push(`- ${b.text}`);
      case "ordered":
        return out.push(`${++n}. ${b.text}`);
      case "task":
        return out.push(`- [${b.checked ? "x" : " "}] ${b.text}`);
      case "quote":
        return out.push(`> ${b.text}`);
      case "code":
        return out.push("```\n" + b.text + "\n```");
      case "rule":
        return out.push("---");
      case "image":
        return out.push("[Image]");
      default:
        return out.push(b.text);
    }
  });
  return out.join("\n").trim();
}

const graphemes = typeof Intl !== "undefined" && "Segmenter" in Intl ? new Intl.Segmenter(undefined, { granularity: "grapheme" }) : null;
const words = typeof Intl !== "undefined" && "Segmenter" in Intl ? new Intl.Segmenter(undefined, { granularity: "word" }) : null;

export function counts(blocks: Block[]) {
  const text = plainText(blocks).trim();
  if (!text) return { characters: 0, words: 0 };
  return {
    characters: graphemes ? [...graphemes.segment(text)].length : text.length,
    words: words ? [...words.segment(text)].filter((s) => s.isWordLike).length : text.split(/\s+/).length,
  };
}

/** The window title: the first non-empty line, like Jot. */
export function title(blocks: Block[]): string {
  const line = plainText(blocks).split("\n").find((l) => l.trim());
  return line?.trim() || "Untitled";
}

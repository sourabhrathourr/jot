import type { IconProps } from "@phosphor-icons/react";
import { ArrowElbowDownLeft, ArrowFatUp, CaretUp, Command, Option } from "@phosphor-icons/react/ssr";

/** Modifier glyphs as Phosphor icons: the font's symbols are too small and sit off-centre at 11px. */
const glyphs: Record<string, React.ComponentType<IconProps>> = {
  "⌘": Command,
  "↩": ArrowElbowDownLeft,
  "⇧": ArrowFatUp,
  "⌥": Option,
  "⌃": CaretUp,
};

const names: Record<string, string> = { "⌘": "Command", "↩": "Return", "⇧": "Shift", "⌥": "Option", "⌃": "Control" };

/**
 * A 20pt keycap: a faint top-lit fill, a hairline border and a darker bottom edge, with the
 * glyph optically centred. `active` lights it in the accent (a shortcut being pressed).
 */
export function Keycap({ k, active }: { k: string; active?: boolean }) {
  const Glyph = glyphs[k];
  return (
    <kbd
      data-active={active}
      aria-label={names[k] ?? k}
      className="inline-flex size-5 items-center justify-center rounded-[5px] border border-white/[0.13] bg-gradient-to-b from-white/[0.08] to-white/[0.03] font-app text-[11px] leading-none font-medium text-white/65 shadow-[inset_0_-1px_0_rgb(0_0_0/0.35),0_1px_0_rgb(255_255_255/0.03)] transition-colors duration-150 data-[active=true]:border-red/70 data-[active=true]:from-red/25 data-[active=true]:to-red/10 data-[active=true]:text-white"
    >
      {Glyph ? <Glyph weight="bold" aria-hidden className="size-[11px]" /> : <span className="-translate-y-[0.5px]">{k}</span>}
    </kbd>
  );
}

export function Keycaps({ keys, active }: { keys: string[]; active?: boolean }) {
  return (
    <span className="inline-flex items-center gap-[3px]">
      {keys.map((k) => (
        <Keycap key={k} k={k} active={active} />
      ))}
    </span>
  );
}

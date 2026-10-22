import {
  ArrowCounterClockwise,
  ArrowRight,
  Check,
  Command,
  Copy,
  DownloadSimple,
  GithubLogo,
  MagnifyingGlass,
  MarkdownLogo,
  PaperPlaneTilt,
  Plus,
  PushPin,
  TextAlignLeft,
} from "@phosphor-icons/react/ssr";
import type { IconProps } from "@phosphor-icons/react";
import type { SVGProps } from "react";

/** Phosphor (the set the portfolio uses), at its regular weight unless a caller asks otherwise. */
const icon = (Glyph: React.ComponentType<IconProps>, weight: IconProps["weight"] = "regular") =>
  function PhosphorIcon(props: IconProps) {
    return <Glyph weight={weight} aria-hidden {...props} />;
  };

export const CommandIcon = icon(Command);
export const PinIcon = icon(PushPin);
export const PlusIcon = icon(Plus);
export const CopyIcon = icon(Copy);
export const TextIcon = icon(TextAlignLeft);
export const ResetIcon = icon(ArrowCounterClockwise);
export const MarkdownIcon = icon(MarkdownLogo);
export const SearchIcon = icon(MagnifyingGlass);
export const ArrowIcon = icon(ArrowRight);
export const DownloadIcon = icon(DownloadSimple, "bold");
export const GitHubIcon = icon(GithubLogo, "fill");
export const CheckIcon = icon(Check, "bold");
export const SendIcon = icon(PaperPlaneTilt, "bold");

/** Jot's mark: a dark glass tile with two lines of writing and a red caret, mid-thought. */
export const JotMark = (p: SVGProps<SVGSVGElement>) => (
  <svg viewBox="0 0 24 24" fill="none" aria-hidden {...p}>
    <defs>
      <linearGradient id="jot-mark-tile" x1="12" y1="1" x2="12" y2="23" gradientUnits="userSpaceOnUse">
        <stop stopColor="#2c2c2e" />
        <stop offset="1" stopColor="#141415" />
      </linearGradient>
    </defs>
    <rect x="1" y="1" width="22" height="22" rx="6.5" fill="url(#jot-mark-tile)" />
    <rect x="1.5" y="1.5" width="21" height="21" rx="6" stroke="white" strokeOpacity="0.14" />
    <path d="M6.75 9.25h10.5" stroke="white" strokeOpacity="0.92" strokeWidth="1.8" strokeLinecap="round" />
    <path d="M6.75 14.5h5.25" stroke="white" strokeOpacity="0.5" strokeWidth="1.8" strokeLinecap="round" />
  </svg>
);

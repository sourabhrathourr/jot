import type { ReactNode } from "react";

export function SectionHeading({ eyebrow, title, children }: { eyebrow: string; title: ReactNode; children?: ReactNode }) {
  return (
    <div className="max-w-2xl">
      <p className="mb-4 font-mono text-[12px] tracking-[0.14em] text-red uppercase">{eyebrow}</p>
      <h2 className="text-[clamp(2rem,4.4vw,3.25rem)] leading-[1.04] font-medium tracking-[-0.04em] text-balance">{title}</h2>
      {children && <p className="mt-5 text-[16px] leading-relaxed text-pretty text-muted">{children}</p>}
    </div>
  );
}

export function Serif({ children }: { children: ReactNode }) {
  return <span className="font-serif text-[1.08em] font-normal tracking-[-0.01em] italic">{children}</span>;
}

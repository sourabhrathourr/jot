"use client";

import { motion } from "motion/react";
import type { ReactNode } from "react";
import type { BlockKind } from "@/lib/note";
import { useNote } from "./demo/store";
import { ArrowIcon } from "./icons";
import { SectionHeading, Serif } from "./section-heading";

type Rule = { syntax: string; name: string; kind: BlockKind; example: string; preview: ReactNode };

const rules: Rule[] = [
  { syntax: "#", name: "Heading", kind: "h1", example: "A big idea", preview: <span className="text-[19px] font-semibold text-white">A big idea</span> },
  { syntax: "##", name: "Subheading", kind: "h2", example: "A smaller one", preview: <span className="text-[16px] font-semibold text-white">A smaller one</span> },
  {
    syntax: "-",
    name: "Bullet list",
    kind: "bullet",
    example: "Something to remember",
    preview: (
      <span className="flex items-center gap-2.5">
        <span className="size-[5px] rounded-full bg-white/45" />
        Something to remember
      </span>
    ),
  },
  {
    syntax: "1.",
    name: "Numbered list",
    kind: "ordered",
    example: "First, the coffee",
    preview: (
      <span className="flex items-center gap-2">
        <span className="text-white/40 tabular-nums">1.</span>First, the coffee
      </span>
    ),
  },
  {
    syntax: "[]",
    name: "Task",
    kind: "task",
    example: "Something to do",
    preview: (
      <span className="flex items-center gap-2.5">
        <span className="size-[14px] rounded-[4px] border border-white/30" />
        Something to do
      </span>
    ),
  },
  {
    syntax: ">",
    name: "Quote",
    kind: "quote",
    example: "Words worth keeping",
    preview: (
      <span className="flex items-stretch gap-3 text-white/75">
        <span className="w-[2px] rounded-full bg-red" />
        Words worth keeping
      </span>
    ),
  },
  {
    syntax: "```",
    name: "Code block",
    kind: "code",
    example: "let jot = true",
    preview: <span className="rounded-lg bg-white/[0.06] px-2.5 py-1 font-mono text-[12.5px] text-white/80">let jot = true</span>,
  },
  {
    syntax: "---",
    name: "Divider",
    kind: "rule",
    example: "",
    preview: <span className="block h-[2px] w-40 rounded-full bg-white/15" />,
  },
];

export function MarkdownSection() {
  const { tryBlock } = useNote();

  const tryRule = (rule: Rule) => {
    tryBlock(rule.kind, rule.example);
    document.getElementById("demo")?.scrollIntoView({ behavior: "smooth", block: "center" });
  };

  return (
    <section id="markdown" className="mx-auto max-w-5xl scroll-mt-24 px-6 py-24 sm:py-32">
      <div className="grid gap-14 lg:grid-cols-[0.9fr_1.1fr] lg:gap-20">
        <div className="lg:sticky lg:top-32 lg:self-start">
          <SectionHeading
            eyebrow="Markdown"
            title={
              <>
                Formatting that <Serif>just happens</Serif>.
              </>
            }
          >
            Type the shortcut you already know and Jot turns it into the real thing. No toolbar hunting, no
            preview pane. Press Try on any row to write it into the note above.
          </SectionHeading>
        </div>

        <ul className="divide-y divide-line border-y border-line">
          {rules.map((rule, i) => (
            <motion.li
              key={rule.syntax}
              initial={{ opacity: 0, y: 8 }}
              whileInView={{ opacity: 1, y: 0 }}
              viewport={{ once: true, margin: "-40px" }}
              transition={{ duration: 0.5, delay: i * 0.04, ease: [0.23, 1, 0.32, 1] }}
              className="group grid grid-cols-[64px_1fr_auto] items-center gap-4 py-4 sm:grid-cols-[88px_1fr_auto]"
            >
              <code className="font-mono text-[15px] whitespace-nowrap text-red">
                {rule.syntax}
                {rule.kind !== "rule" && <span className="text-faint">␣</span>}
              </code>
              <div className="min-w-0">
                <p className="mb-1.5 text-[12px] text-faint">{rule.name}</p>
                <div className="truncate font-app text-[14px] text-white/85">{rule.preview}</div>
              </div>
              <button
                type="button"
                onClick={() => tryRule(rule)}
                className="inline-flex h-8 items-center gap-1.5 rounded-full border border-line-strong px-3 text-[13px] text-muted transition-[color,border-color,background-color,transform] duration-150 group-hover:border-red/40 group-hover:text-fg hover:bg-red/10 active:scale-95"
                aria-label={`Try ${rule.name} in the note`}
              >
                Try
                <ArrowIcon className="size-3.5 -rotate-90" />
              </button>
            </motion.li>
          ))}
        </ul>
      </div>
    </section>
  );
}

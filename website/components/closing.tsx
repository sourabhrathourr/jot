import { downloadUrl, githubUrl, requirement } from "@/lib/site";
import { DownloadIcon, GitHubIcon, JotMark } from "./icons";

export function Closing() {
  return (
    <>
      <section id="download" className="relative mx-auto max-w-5xl scroll-mt-24 overflow-hidden px-6 pt-24 pb-32 text-center sm:pt-32 sm:pb-40">
        <h2 className="relative font-serif text-[clamp(3.5rem,11vw,8.5rem)] leading-[0.9] tracking-[-0.03em] italic">
          Write it <span className="text-red">down.</span>
        </h2>
        <p className="relative mx-auto mt-6 max-w-md text-[16px] leading-relaxed text-muted">
          Before the thought is gone. Jot is one keystroke away, free, and yours to keep.
        </p>
        <div className="relative mt-10 flex flex-col items-center gap-3">
          <div className="flex flex-col items-center gap-3 sm:flex-row">
            <a
              href={downloadUrl}
              className="inline-flex h-12 items-center gap-2 rounded-full bg-red px-6 text-[15px] font-medium text-black shadow-[0_10px_40px_-8px_rgb(255_99_99/0.7),inset_0_1px_0_rgb(255_255_255/0.35)] transition-[transform,background-color] duration-150 hover:bg-[#ff7676] active:scale-[0.97]"
            >
              <DownloadIcon className="size-4" />
              Download for macOS
            </a>
            <a
              href={githubUrl}
              className="inline-flex h-12 items-center gap-2 rounded-full border border-line-strong px-6 text-[15px] text-fg transition-[border-color,background-color,transform] duration-150 hover:border-white/20 hover:bg-white/[0.04] active:scale-[0.97]"
            >
              <GitHubIcon className="size-4" />
              View the source
            </a>
          </div>
          <p className="text-[12px] text-faint">{requirement}</p>
        </div>
      </section>

      <footer className="border-t border-line">
        <div className="mx-auto flex max-w-5xl flex-col gap-6 px-6 py-10 text-[13px] text-faint sm:flex-row sm:items-start sm:justify-between">
          <div className="flex flex-col gap-2">
            <span className="flex items-center gap-2 text-muted">
              <JotMark className="size-4" />
              Jot
            </span>
            <span>Free and open source. Made with AppKit, on a Mac.</span>
          </div>
          <p className="max-w-sm leading-relaxed sm:text-right">
            Inspired by{" "}
            <a href="https://www.raycast.com" className="text-muted underline decoration-white/20 underline-offset-4 transition-colors hover:text-fg hover:decoration-white/50">
              Raycast Notes
            </a>
            , which showed how good a quick notes window can feel. Thank you to the Raycast team. Jot is an independent
            project and isn&apos;t affiliated with or endorsed by Raycast.
          </p>
        </div>
      </footer>
    </>
  );
}

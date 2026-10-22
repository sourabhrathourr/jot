import { downloadUrl, githubUrl } from "@/lib/site";
import { GitHubIcon, JotMark } from "./icons";

export function Nav() {
  return (
    <header className="fixed inset-x-0 top-0 z-50">
      <div className="mx-4 mt-3 flex h-12 max-w-5xl items-center justify-between rounded-full border border-line bg-[rgb(0_0_0/0.55)] px-2 pl-4 backdrop-blur-xl sm:mx-6 lg:mx-auto">
        <a href="#top" className="flex items-center gap-2 text-[15px] font-semibold tracking-[-0.01em]">
          <JotMark className="size-[22px]" />
          Jot
        </a>
        <nav aria-label="Primary" className="hidden items-center gap-1 text-[14px] text-muted sm:flex">
          {[
            ["Markdown", "#markdown"],
            ["Free", "#free"],
            ["Shortcuts", "#shortcuts"],
          ].map(([label, href]) => (
            <a key={href} href={href} className="rounded-full px-3 py-1.5 transition-colors duration-150 hover:bg-white/[0.05] hover:text-fg">
              {label}
            </a>
          ))}
        </nav>
        <div className="flex items-center gap-1">
          <a
            href={githubUrl}
            aria-label="Jot on GitHub"
            className="flex size-8 items-center justify-center rounded-full text-muted transition-colors duration-150 hover:bg-white/[0.05] hover:text-fg"
          >
            <GitHubIcon className="size-[17px]" />
          </a>
          <a
            href={downloadUrl}
            className="inline-flex h-8 items-center rounded-full bg-white px-3.5 text-[13px] font-medium text-black transition-[transform,background-color] duration-150 hover:bg-white/90 active:scale-[0.97]"
          >
            Download
          </a>
        </div>
      </div>
    </header>
  );
}

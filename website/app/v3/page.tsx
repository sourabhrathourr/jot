import type { Metadata } from "next";
import { Closing } from "@/components/closing";
import { NoteProvider } from "@/components/demo/store";
import { FeaturesSection } from "@/components/features-section";
import { MarkdownSection } from "@/components/markdown-section";
import { Nav } from "@/components/nav";
import { ShortcutsSection } from "@/components/shortcuts-section";
import { SplitHero } from "@/components/v3/split-hero";

export const metadata: Metadata = {
  title: "Jot — Raycast Notes, but free",
  description: "A free and open-source notes window for macOS. Unlimited notes, images included, no account.",
};

/** The full landing page, with the `/v2` note as the hero asset beside the pitch. */
export default function V3() {
  return (
    <NoteProvider note="landing">
      <div id="top">
        <Nav />
        <main>
          <SplitHero />
          <MarkdownSection />
          <FeaturesSection />
          <ShortcutsSection />
          <Closing />
        </main>
      </div>
    </NoteProvider>
  );
}

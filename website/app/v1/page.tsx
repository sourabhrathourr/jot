import { Closing } from "@/components/closing";
import { Hero } from "@/components/hero";
import { MarkdownSection } from "@/components/markdown-section";
import { FeaturesSection } from "@/components/features-section";
import { Nav } from "@/components/nav";
import { ShortcutsSection } from "@/components/shortcuts-section";

export default function Home() {
  return (
    <div id="top">
      <Nav />
      <main>
        <Hero />
        <MarkdownSection />
        <FeaturesSection />
        <ShortcutsSection />
        <Closing />
      </main>
    </div>
  );
}

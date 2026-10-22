import type { Metadata } from "next";
import { NoteProvider } from "@/components/demo/store";
import { Landing } from "@/components/v2/landing";

export const metadata: Metadata = {
  title: "Jot · Raycast Notes, but free",
  description:
    "A free, open-source and fully native notes window for macOS. Unlimited notes, images included, invisible in screen shares, no account.",
};

/** The home page is v2: the page is a note. (v1 lives at /v1, v3 at /v3.) */
export default function Home() {
  return (
    <NoteProvider note="pitch">
      <Landing />
    </NoteProvider>
  );
}

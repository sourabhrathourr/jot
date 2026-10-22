"use client";

import { MotionConfig } from "motion/react";
import type { ReactNode } from "react";
import { NoteProvider } from "@/components/demo/store";

export function Providers({ children }: { children: ReactNode }) {
  return (
    <MotionConfig reducedMotion="user">
      <NoteProvider>{children}</NoteProvider>
    </MotionConfig>
  );
}

import type { Metadata, Viewport } from "next";
import { Geist, Instrument_Serif, Inter, JetBrains_Mono } from "next/font/google";
import { Grain } from "@/components/grain";
import { Providers } from "@/components/providers";
import "./globals.css";

const geist = Geist({ variable: "--font-geist", subsets: ["latin"] });

const instrument = Instrument_Serif({
  variable: "--font-instrument",
  subsets: ["latin"],
  weight: "400",
  style: ["normal", "italic"],
});

const jetbrains = JetBrains_Mono({ variable: "--font-jetbrains", subsets: ["latin"] });

/** The demo window is set in Inter, like the app itself. */
const inter = Inter({ variable: "--font-inter", subsets: ["latin"] });

export const metadata: Metadata = {
  metadataBase: new URL("https://getjot.vercel.app"),
  title: "Jot · Raycast Notes, but free",
  // The image comes from app/opengraph-image.tsx; X uses it as a large card.
  twitter: { card: "summary_large_image" },
  description:
    "A free and open-source notes window for macOS, inspired by Raycast Notes. Unlimited notes, images included, no account. Opens with ⇧⌘N.",
};

export const viewport: Viewport = {
  themeColor: "#000000",
  colorScheme: "dark",
  // Paint under the notch and home indicator; the page pads itself with the safe-area insets.
  viewportFit: "cover",
};

export default function RootLayout({ children }: LayoutProps<"/">) {
  return (
    <html
      lang="en"
      className={`${geist.variable} ${instrument.variable} ${jetbrains.variable} ${inter.variable} antialiased`}
    >
      <body className="min-h-dvh">
        <Providers>{children}</Providers>
        <Grain />
      </body>
    </html>
  );
}

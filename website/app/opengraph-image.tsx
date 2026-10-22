import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const alt = "Jot: Raycast Notes, but free. Fast, fully native notes for your Mac.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const red = "#ff6363";

/** The Jot mark, flat: a dark tile with two lines. */
const mark = `data:image/svg+xml;base64,${Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"><rect x="1" y="1" width="22" height="22" rx="6.5" fill="#222224"/><rect x="1.5" y="1.5" width="21" height="21" rx="6" stroke="#fff" stroke-opacity=".14"/><path d="M6.75 9.25h10.5" stroke="#fff" stroke-opacity=".92" stroke-width="1.8" stroke-linecap="round"/><path d="M6.75 14.5h5.25" stroke="#fff" stroke-opacity=".5" stroke-width="1.8" stroke-linecap="round"/></svg>`,
).toString("base64")}`;

const features = ["Opens instantly", "Invisible in screen shares", "Unlimited notes and images", "Free and open source"];

/** Jot's checked task: a red ring with a softer red square inside. */
function Check() {
  return (
    <div
      style={{
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
        width: 22,
        height: 22,
        borderRadius: 7,
        border: `2px solid ${red}`,
        marginRight: 16,
      }}
    >
      <div style={{ width: 11, height: 11, borderRadius: 3.5, background: "rgba(255, 99, 99, 0.75)" }} />
    </div>
  );
}

/**
 * The link preview: the product as the picture. A Jot window on flat near-black, cropped by the
 * bottom edge like a product shot, holding the same note as the website. No gradients, no glows.
 */
export default async function OpenGraphImage() {
  const font = (weight: number) => readFile(join(process.cwd(), `assets/fonts/Inter-${weight}.ttf`));
  const [regular, medium, semibold] = await Promise.all([font(400), font(500), font(600)]);

  return new ImageResponse(
    (
      <div
        style={{
          display: "flex",
          flexDirection: "column",
          width: "100%",
          height: "100%",
          background: "#0b0b0b",
          fontFamily: "Inter",
          padding: "0 120px",
        }}
      >
        {/* The brand, aligned with the window's edge */}
        <div style={{ display: "flex", alignItems: "center", height: 156 }}>
          <img src={mark} width={38} height={38} alt="" />
          <div style={{ marginLeft: 13, fontSize: 27, fontWeight: 600, color: "#ededed", letterSpacing: -0.4 }}>Jot</div>
        </div>

        {/* The window */}
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            height: 600,
            borderRadius: 26,
            background: "#161616",
            border: "1px solid rgba(255, 255, 255, 0.08)",
          }}
        >
          <div style={{ display: "flex", position: "relative", alignItems: "center", justifyContent: "center", height: 58 }}>
            <div style={{ display: "flex", position: "absolute", left: 22, top: 22 }}>
              {["#ff5f57", "#febc2e", "#28c840"].map((color) => (
                <div key={color} style={{ width: 13, height: 13, borderRadius: 9999, background: color, marginRight: 8 }} />
              ))}
            </div>
            <div style={{ fontSize: 16, color: "#6f6f6f" }}>Raycast Notes, but free.</div>
          </div>

          <div style={{ display: "flex", flexDirection: "column", padding: "40px 64px 0" }}>
            <div style={{ fontSize: 64, fontWeight: 600, color: "#ffffff", letterSpacing: -2, lineHeight: 1.1 }}>
              Raycast Notes, but free.
            </div>
            <div style={{ marginTop: 20, fontSize: 27, fontWeight: 400, color: "#8b8b8b", letterSpacing: -0.2 }}>
              Fast, fully native notes for your Mac, always one shortcut away.
            </div>
            <div style={{ display: "flex", flexWrap: "wrap", marginTop: 44, width: 860 }}>
              {features.map((feature) => (
                <div key={feature} style={{ display: "flex", alignItems: "center", width: 430, marginBottom: 26 }}>
                  <Check />
                  <div style={{ fontSize: 24, fontWeight: 500, color: "rgba(255, 255, 255, 0.82)" }}>{feature}</div>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    ),
    {
      ...size,
      fonts: [
        { name: "Inter", data: regular, weight: 400, style: "normal" },
        { name: "Inter", data: medium, weight: 500, style: "normal" },
        { name: "Inter", data: semibold, weight: 600, style: "normal" },
      ],
    },
  );
}

import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { ImageResponse } from "next/og";

export const alt = "Jot: Raycast Notes, but free. Fast, fully native notes for your Mac.";
export const size = { width: 1200, height: 630 };
export const contentType = "image/png";

const red = "#ff6363";

/** The Jot mark: a dark tile with two lines, like the favicon. */
const mark = `data:image/svg+xml;base64,${Buffer.from(
  `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="none"><defs><linearGradient id="g" x1="12" y1="1" x2="12" y2="23" gradientUnits="userSpaceOnUse"><stop stop-color="#2c2c2e"/><stop offset="1" stop-color="#141415"/></linearGradient></defs><rect x="1" y="1" width="22" height="22" rx="6.5" fill="url(#g)"/><rect x="1.5" y="1.5" width="21" height="21" rx="6" stroke="#fff" stroke-opacity=".14"/><path d="M6.75 9.25h10.5" stroke="#fff" stroke-opacity=".92" stroke-width="1.8" stroke-linecap="round"/><path d="M6.75 14.5h5.25" stroke="#fff" stroke-opacity=".5" stroke-width="1.8" stroke-linecap="round"/></svg>`,
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
 * The link preview: the pitch on the left, a Jot window drifting in from the right with the
 * note's checklist, on the site's near-black with a soft red glow behind the window.
 */
export default async function OpenGraphImage() {
  const font = (weight: number) => readFile(join(process.cwd(), `assets/fonts/Inter-${weight}.ttf`));
  const [regular, medium, semibold] = await Promise.all([font(400), font(500), font(600)]);

  return new ImageResponse(
    (
      <div
        style={{
          display: "flex",
          position: "relative",
          width: "100%",
          height: "100%",
          background: "#0a0a0a",
          fontFamily: "Inter",
          color: "#ededed",
          overflow: "hidden",
        }}
      >
        {/* Light: a red glow under the window, a faint lift top left. */}
        <div
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            width: 1200,
            height: 630,
            backgroundImage:
              "radial-gradient(circle at 82% 58%, rgba(255, 99, 99, 0.3) 0%, rgba(255, 99, 99, 0.1) 30%, rgba(255, 99, 99, 0) 55%)",
          }}
        />
        <div
          style={{
            position: "absolute",
            left: 0,
            top: 0,
            width: 1200,
            height: 630,
            backgroundImage: "radial-gradient(circle at 8% 0%, rgba(255, 255, 255, 0.07) 0%, rgba(255, 255, 255, 0) 45%)",
          }}
        />

        {/* The pitch */}
        <div style={{ display: "flex", flexDirection: "column", padding: "72px 0 64px 80px", width: 640 }}>
          <div style={{ display: "flex", alignItems: "center" }}>
            <img src={mark} width={44} height={44} alt="" />
            <div style={{ marginLeft: 14, fontSize: 30, fontWeight: 600, letterSpacing: -0.5 }}>Jot</div>
          </div>

          <div
            style={{
              display: "flex",
              flexDirection: "column",
              marginTop: 96,
              fontSize: 76,
              fontWeight: 600,
              lineHeight: 1.04,
              letterSpacing: -3,
              color: "#ffffff",
            }}
          >
            <div>Raycast Notes,</div>
            <div>but free.</div>
          </div>

          <div style={{ marginTop: 28, fontSize: 28, fontWeight: 400, lineHeight: 1.4, color: "#8b8b8b", letterSpacing: -0.2 }}>
            Fast, fully native notes for your Mac.
          </div>

          <div style={{ display: "flex", marginTop: "auto", fontSize: 20, fontWeight: 500, color: "#5f5f5f" }}>
            sourabh.lol/jot
          </div>
        </div>

        {/* The window */}
        <div
          style={{
            position: "absolute",
            left: 700,
            top: 118,
            width: 600,
            height: 400,
            display: "flex",
            flexDirection: "column",
            borderRadius: 28,
            background: "rgba(22, 22, 22, 0.94)",
            border: "1px solid rgba(255, 255, 255, 0.09)",
            boxShadow: "0 40px 120px rgba(0, 0, 0, 0.7)",
          }}
        >
          <div style={{ display: "flex", position: "relative", alignItems: "center", justifyContent: "center", height: 56 }}>
            <div style={{ display: "flex", position: "absolute", left: 22, top: 21 }}>
              {["#ff5f57", "#febc2e", "#28c840"].map((color) => (
                <div key={color} style={{ width: 13, height: 13, borderRadius: 9999, background: color, marginRight: 8, opacity: 0.9 }} />
              ))}
            </div>
            <div style={{ fontSize: 16, color: "#7a7a7a" }}>Why Jot</div>
          </div>

          <div style={{ display: "flex", flexDirection: "column", padding: "18px 40px 0" }}>
            <div style={{ fontSize: 30, fontWeight: 600, color: "#ffffff", letterSpacing: -0.6 }}>Why Jot</div>
            <div style={{ display: "flex", flexDirection: "column", marginTop: 22 }}>
              {features.map((feature) => (
                <div key={feature} style={{ display: "flex", alignItems: "center", marginBottom: 20 }}>
                  <Check />
                  <div style={{ fontSize: 23, color: "rgba(255, 255, 255, 0.78)" }}>{feature}</div>
                </div>
              ))}
            </div>
          </div>

          <div
            style={{
              display: "flex",
              alignItems: "center",
              marginTop: "auto",
              height: 52,
              padding: "0 22px",
              borderTop: "1px solid rgba(255, 255, 255, 0.06)",
              fontSize: 15,
              color: "#5f5f5f",
            }}
          >
            98 characters
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

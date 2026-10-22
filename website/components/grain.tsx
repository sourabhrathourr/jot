/** Film grain over the whole page, the way ped.ro does it: desaturated fractal noise in a fixed SVG. */
export function Grain() {
  return (
    <svg className="grain-overlay" aria-hidden>
      <filter id="grain-noise">
        <feTurbulence type="fractalNoise" baseFrequency=".8" numOctaves={4} stitchTiles="stitch" />
        <feColorMatrix type="saturate" values="0" />
      </filter>
      <rect width="100%" height="100%" filter="url(#grain-noise)" />
    </svg>
  );
}

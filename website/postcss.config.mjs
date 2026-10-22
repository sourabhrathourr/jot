// Tailwind CSS v4 through PostCSS, which Turbopack runs natively and tracks per file.
// (The `@tailwindcss/turbopack` loader cached its compiler by file mtime, so under Turbopack
// it often built from the previous version of globals.css and served stale styles.)
const config = {
  plugins: {
    "@tailwindcss/postcss": {},
  },
};

export default config;

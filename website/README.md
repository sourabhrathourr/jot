# Jot website

The site at **https://getjot.vercel.app**: Next.js 16 (App Router, Cache Components), Tailwind CSS
v4 through PostCSS, Motion and Phosphor icons.

The home page is a note in a working Jot window (`components/v2`, `components/demo`). You can type
Markdown in it on a Mac. On phones it drops the window and reads as a page, with a "Send to your
Mac" share button. `/v1` and `/v3` are earlier designs.

```sh
pnpm install
pnpm dev                 # or: hun run jot-website
pnpm build
```

- `app/opengraph-image.tsx` renders the 1200×630 link preview with Inter from `assets/fonts`.
- `lib/site.ts` holds the download and GitHub links.
- Deploys go to the Vercel project `getjot` (`npx vercel deploy --prod` from this folder).

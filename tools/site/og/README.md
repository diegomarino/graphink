# Social preview composer

`og-1200x630.html` and `og-1200x1200.html` lay out the landing page's `og:image` files from `site/assets`; `og.js` renders them with headless Chromium at 1× as JPEG q 90 into `site/assets/img/og-image-*.jpg`.
Needs Node and Playwright with Chromium: `npm install -g playwright && npx playwright install chromium`.
From the repository root: `NODE_PATH="$(npm root -g)" node tools/site/og/og.js` (pass a directory to write elsewhere).
Re-run it when the hero tagline, the lockup or the window screenshot changes, then check both images stay under ~300 KB.

// Renders the landing page's social preview images from the two composer pages
// next to this file into site/assets/img (or the directory given as argument).
const path = require('path');
const { pathToFileURL } = require('url');
const { chromium } = require('playwright');

const here = __dirname;
const out = path.resolve(process.argv[2] || path.join(here, '../../../site/assets/img'));

(async () => {
  const browser = await chromium.launch();
  for (const [w, h] of [[1200, 630], [1200, 1200]]) {
    const ctx = await browser.newContext({ viewport: { width: w, height: h }, deviceScaleFactor: 1, colorScheme: 'light' });
    const page = await ctx.newPage();
    await page.goto(pathToFileURL(path.join(here, `og-${w}x${h}.html`)).href, { waitUntil: 'networkidle' });
    await page.waitForTimeout(300);
    const file = path.join(out, `og-image-${w}x${h}.jpg`);
    await page.screenshot({ path: file, type: 'jpeg', quality: 90 });
    console.log(file);
    await ctx.close();
  }
  await browser.close();
})();

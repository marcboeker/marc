// Writes PNG stills at the given times, to check frames. Usage: node stills.mjs <dir> <wide|square> t1 t2 ...
import { chromium } from '/opt/homebrew/lib/node_modules/@playwright/cli/node_modules/playwright-core/index.mjs';
const [dir, layout, ...times] = process.argv.slice(2);
const square = layout === 'square';
const browser = await chromium.launch({ executablePath: process.env.CHROME ?? `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell` });
const page = await browser.newPage({ viewport: square ? { width: 1080, height: 1080 } : { width: 1920, height: 1080 } });
const url = new URL('index.html', import.meta.url);
if (square) url.search = '?square';
await page.goto(url.href);
for (const t of times) {
  await page.evaluate(t => window.render(t), Number(t));
  await page.screenshot({ path: `${dir}/${layout}-${t}.png` });
}
await browser.close();

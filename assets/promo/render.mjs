// Renders index.html frame by frame and pipes the PNGs into ffmpeg.
// Usage: node render.mjs <out.mp4> [wide|square|flat] [fps]   (flat: wide without the background glow, for the GIF)
import { chromium } from '/opt/homebrew/lib/node_modules/@playwright/cli/node_modules/playwright-core/index.mjs';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const [out, layout = 'wide', fps = '60'] = process.argv.slice(2);
const square = layout === 'square';
const [w, h] = square ? [1080, 1080] : [1920, 1080];

const browser = await chromium.launch({ executablePath: process.env.CHROME ?? `${process.env.HOME}/Library/Caches/ms-playwright/chromium_headless_shell-1243/chrome-headless-shell-mac-arm64/chrome-headless-shell` });
const page = await browser.newPage({ viewport: { width: w, height: h }, deviceScaleFactor: 1 });
const url = new URL('index.html', import.meta.url);
if (layout !== 'wide') url.search = '?' + layout;
await page.goto(url.href);
await page.evaluate(() => document.fonts.ready);
const duration = await page.evaluate(() => DURATION);

const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', fps, '-i', '-',
  '-c:v', 'libx264', '-preset', 'slow', '-crf', '16', '-pix_fmt', 'yuv420p', '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
const frames = duration * Number(fps);
for (let i = 0; i < frames; i++) {
  await page.evaluate(t => window.render(t), i / Number(fps));
  const png = await page.screenshot({ type: 'png' });
  if (!ff.stdin.write(png)) await new Promise(r => ff.stdin.once('drain', r));
}
ff.stdin.end();
await new Promise(r => ff.on('close', r));
await browser.close();

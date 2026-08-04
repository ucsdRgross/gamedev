// Screenshot a page in headless Edge over CDP, after running a snippet of JS in it.
//
//   node designloop/tools/shot.mjs <url> <out.png> [width] [height] ["js to run first"]
//
// Why this exists: CLAUDE.md rule 4 says visuals are verified by LOOKING at them, and in this
// environment the Browser pane is often not displayed, so its screenshot tool cannot composite a
// frame. `msedge --screenshot` alone only ever shows a page's initial state — useless for a canvas
// whose interesting states are behind a click. Driving Edge over the DevTools protocol runs the
// clicks first. Node's built-in WebSocket does the talking, so this stays dependency-free like the
// rest of the tool.
//
// It earned its keep immediately: the cross-chart links (GAP-002) looked correct in every count
// and every test, and the screenshot of the COLLAPSED canvas is what showed them lying flat
// through the boxes they crossed.
//
//   node designloop/tools/shot.mjs "http://localhost:5273/web/canvas.html?key=designloop/designloop" \
//     out.png 1900 1000 "document.getElementById('collapse-all').click(); 'ok'"
//
// The JS snippet's value is printed, so it doubles as a way to read the page back.
import { spawn } from 'node:child_process';
import { writeFile, mkdtemp } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [url, out, w = '1900', h = '1200', pre = ''] = process.argv.slice(2);
const EDGE = 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe';
const port = 9222 + Math.floor(Math.random() * 500);
const profile = await mkdtemp(join(tmpdir(), 'cdp-'));

const edge = spawn(EDGE, [
  '--headless=new', '--disable-gpu', '--hide-scrollbars', `--remote-debugging-port=${port}`,
  `--user-data-dir=${profile}`, `--window-size=${w},${h}`, 'about:blank',
], { stdio: 'ignore' });

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
let target = null;
for (let i = 0; i < 60 && !target; i++) {
  await sleep(250);
  try {
    const list = await fetch(`http://127.0.0.1:${port}/json/list`).then((r) => r.json());
    target = list.find((t) => t.type === 'page');
  } catch { /* not up yet */ }
}
if (!target) { edge.kill(); throw new Error('no CDP target'); }

const ws = new WebSocket(target.webSocketDebuggerUrl);
await new Promise((res, rej) => { ws.onopen = res; ws.onerror = rej; });
let id = 0;
const pending = new Map();
ws.onmessage = (e) => {
  const msg = JSON.parse(e.data);
  if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg.result); pending.delete(msg.id); }
};
const send = (method, params = {}) => new Promise((res) => {
  const n = ++id;
  pending.set(n, res);
  ws.send(JSON.stringify({ id: n, method, params }));
});

await send('Page.enable');
await send('Page.navigate', { url });
await sleep(2500);
if (pre) {
  const r = await send('Runtime.evaluate', { expression: pre, awaitPromise: true, returnByValue: true });
  console.log('pre:', JSON.stringify(r.result?.value ?? r.exceptionDetails?.text ?? null));
  await sleep(1200);
}
const shot = await send('Page.captureScreenshot', { format: 'png' });
await writeFile(out, Buffer.from(shot.data, 'base64'));
console.log('wrote', out);
ws.close();
edge.kill();
process.exit(0);

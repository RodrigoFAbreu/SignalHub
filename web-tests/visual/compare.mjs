// Renders each drawing of the users' web page (docs/design/users/source/Web - *.dc.html) and the
// page itself at the drawing's size, and writes drawing | page | difference side by side into
// web-tests/.visual/ (not in git). See docs/development.md, "Comparing the page with its drawings".
//
//   SIGNALHUB_URL=http://localhost:8080 ADMIN_TOKEN=... node visual/compare.mjs [frame ids...]
//
// It needs an EMPTY database (see world.mjs) and `python3 -m http.server` in the drawings folder,
// which this script starts itself.

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { chromium } from "@playwright/test";
import { BASE } from "../support/server.mjs";
import { adminFrames } from "./admin-frames.mjs";
import { answerFrames } from "./answer-frames.mjs";
import { frames as webFrames } from "./frames.mjs";
import { seedWorld } from "./world.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const out = resolve(here, "..", ".visual");
const drawings = resolve(here, "..", "..", "docs", "design", "users", "source");
const port = Number(process.env.DRAWINGS_PORT ?? 8765);
const only = process.argv.slice(2).filter((argument) => !argument.startsWith("--"));
// The users' page's frames, then the admin page's (admin-frames.mjs: ids that start with the family's
// letters, such as SI1 or DV2, never clash with the web page's 6a, 7b). A frame of the admin page
// asks for no world (`world: false`): it is rendered from the drawings' sample data, mocked.
const frames = [...webFrames, ...adminFrames, ...answerFrames];

mkdirSync(out, { recursive: true });

const server = spawn("python3", ["-m", "http.server", String(port), "--bind", "127.0.0.1"], { cwd: drawings, stdio: "ignore" });
const stop = () => server.kill();
process.on("exit", stop);
await new Promise((done) => setTimeout(done, 800));

const executablePath = process.env.PLAYWRIGHT_CHROMIUM_EXECUTABLE || undefined;
const browser = await chromium.launch({ executablePath });
// The sample world is made once and kept (with its keys, in the ignored output folder) so a
// second run does not need an empty database. --fresh makes it again.
const worldFile = join(out, "world.json");
let world = {};
const needsWorld = frames.some((frame) => (!only.length || only.includes(frame.id)) && frame.world !== false);
if (needsWorld) {
  if (!process.argv.includes("--fresh") && existsSync(worldFile)) {
    world = JSON.parse(readFileSync(worldFile, "utf8"));
  } else {
    world = await seedWorld();
    writeFileSync(worldFile, JSON.stringify(world, null, 2));
  }
}

const sheets = new Map();
async function drawingPage(file) {
  if (!sheets.has(file)) {
    const page = await browser.newPage({ viewport: { width: 1400, height: 900 } });
    await page.goto(`http://127.0.0.1:${port}/${encodeURIComponent(file)}.dc.html`);
    await page.waitForSelector(".dv-opt");
    await page.evaluate(() => document.fonts.ready);
    await page.waitForTimeout(600);
    sheets.set(file, page);
  }
  return sheets.get(file);
}

// The drawing's frame: its inner size, and the height of the fake browser bar the page lacks.
async function drawingFrame(frame) {
  const page = await drawingPage(frame.file);
  const locator = page.locator(`[id='${frame.option}'] ${frame.drawingSelector ?? ":is(.br, .ph)"}`).nth(frame.index ?? 0);
  await locator.scrollIntoViewIfNeeded();
  if (frame.drawingSelector) {
    // A piece of the drawing (a dialog, a pane): its own picture, at its own size.
    const box = await locator.boundingBox();
    return { image: await locator.screenshot(), width: Math.round(box.width), height: Math.round(box.height) };
  }
  const info = await locator.evaluate((node) => {
    const chrome = node.querySelector(":scope > .chrome, :scope > .phchrome, :scope > .mchrome");
    const box = node.getBoundingClientRect();
    // Document coordinates, so a full-page screenshot can be clipped to the frame.
    return { chrome: chrome ? chrome.getBoundingClientRect().height : 0, width: node.clientWidth, height: node.clientHeight, x: box.x + window.scrollX + node.clientLeft, y: box.y + window.scrollY + node.clientTop };
  });
  const height = info.height - info.chrome;
  const image = await page.screenshot({ clip: { x: info.x, y: info.y + info.chrome, width: info.width, height }, fullPage: true });
  return { image, width: info.width, height };
}

async function render(frame, size) {
  const context = await browser.newContext({ viewport: { width: size.width, height: size.height }, colorScheme: frame.scheme ?? "dark", deviceScaleFactor: 1, ...(frame.contextOptions ?? {}) });
  const session = frame.persona ? world.sessions[frame.persona] : null;
  if (session) await context.addCookies([{ name: "__Host-signalhub_session", value: session.value, domain: new URL(BASE).hostname, path: "/", httpOnly: true, secure: true, sameSite: "Strict" }]);
  const page = await context.newPage();
  const errors = [];
  page.on("pageerror", (error) => errors.push(String(error)));
  await frame.setup(page, world, context);
  await page.evaluate(() => document.fonts.ready);
  await page.waitForTimeout(frame.settle ?? 400);
  const image = frame.shot ? await frame.shot(page) : await page.screenshot();
  await context.close();
  return { image, errors };
}

async function sideBySide(drawing, mine, name) {
  const page = await browser.newPage({ viewport: { width: 3000, height: 1400 } });
  const url = (buffer) => `data:image/png;base64,${buffer.toString("base64")}`;
  const html = `<style>body{margin:0;background:#444;display:flex;gap:12px;padding:12px;align-items:flex-start;font:12px sans-serif;color:#fff}figure{margin:0}img{display:block}.diff{position:relative;isolation:isolate;background:#000}.diff img+img{position:absolute;inset:0;mix-blend-mode:difference}</style>
  <figure><figcaption>drawing</figcaption><img src="${url(drawing)}"></figure>
  <figure><figcaption>page</figcaption><img src="${url(mine)}"></figure>
  <figure><figcaption>difference</figcaption><div class="diff"><img src="${url(drawing)}"><img src="${url(mine)}"></div></figure>`;
  await page.setContent(html);
  await page.waitForLoadState("load");
  const body = await page.locator("body").boundingBox();
  await page.screenshot({ path: join(out, `${name}.png`), clip: { x: 0, y: 0, width: Math.ceil(body.width), height: Math.ceil(body.height) } });
  await page.close();
}

let failures = 0;
for (const frame of frames) {
  if (only.length && !only.includes(frame.id)) continue;
  try {
    const drawing = await drawingFrame(frame);
    const size = frame.size ?? { width: drawing.width, height: drawing.height };
    const mine = await render(frame, size);
    await sideBySide(drawing.image, mine.image, frame.id);
    console.log(`${frame.id.padEnd(8)} ${size.width}x${size.height}${mine.errors.length ? `  script errors: ${mine.errors.join("; ")}` : ""}`);
    if (mine.errors.length) failures += 1;
  } catch (error) {
    failures += 1;
    const where = String(error.stack ?? "").split("\n").find((line) => /frames\.mjs|compare\.mjs/.test(line)) ?? "";
    console.log(`${frame.id.padEnd(8)} FAILED: ${String(error).split("\n")[0]} ${where.trim()}`);
  }
}
await browser.close();
stop();
process.exit(failures ? 1 : 0);

import { createServer } from "node:http";
import { BASE, browserSession, createPerson, useSession } from "../support/server.mjs";
import { expect, test } from "../support/page.mjs";

// Every file the page is made of: the page, then what it references, then what those import.
async function pageFiles() {
  const seen = new Set();
  const queue = ["/app/"];
  while (queue.length) {
    const path = queue.pop();
    if (seen.has(path)) continue;
    seen.add(path);
    const text = await (await fetch(`${BASE}${path}`)).text();
    const base = new URL(path, "http://x");
    const found = [];
    if (path.endsWith("/") || path.endsWith(".html")) {
      for (const match of text.matchAll(/(?:src|href)="([^"#]+)"/g)) found.push(match[1]);
    } else if (path.endsWith(".js") || path.endsWith(".mjs")) {
      for (const match of text.matchAll(/(?:from|import)\s*\(?\s*"(\.[^"]+)"/g)) found.push(match[1]);
    } else if (path.endsWith(".css")) {
      for (const match of text.matchAll(/url\(([^)]+)\)/g)) found.push(match[1].replace(/['"]/g, ""));
    }
    for (const reference of found) {
      if (/^[a-z]+:/i.test(reference)) continue;
      queue.push(new URL(reference, `http://x${base.pathname}`).pathname);
    }
  }
  return [...seen];
}

test("every file of the page is served with the strict policy, no framing, no referrer and revalidation", async () => {
  const files = await pageFiles();
  // The page, its stylesheet, its fonts, its icon and every module.
  expect(files.length).toBeGreaterThan(20);
  expect(files).toEqual(expect.arrayContaining(["/app/", "/app/app.css", "/app/js/main.js", "/app/vendor/qrcode.mjs", "/app/fonts/fonts.css", "/app/icon.svg"]));
  for (const path of files) {
    const response = await fetch(`${BASE}${path}`);
    expect(response.status, path).toBe(200);
    const csp = response.headers.get("content-security-policy");
    expect(csp, path).toContain("default-src 'none'");
    expect(csp, path).toContain("script-src 'self'");
    expect(csp, path).toContain("style-src 'self'");
    expect(csp, path).toContain("connect-src 'self'");
    expect(csp, path).toContain("frame-ancestors 'none'");
    expect(csp, path).toContain("form-action 'none'");
    expect(csp, path).toContain("base-uri 'none'");
    expect(csp, path).toContain("object-src 'none'");
    expect(csp, path).not.toMatch(/unsafe-inline|unsafe-eval|https?:/);
    expect(response.headers.get("x-frame-options"), path).toBe("DENY");
    expect(response.headers.get("referrer-policy"), path).toBe("no-referrer");
    expect(response.headers.get("cache-control"), path).toBe("no-cache");
    expect(response.headers.get("x-content-type-options"), path).toBe("nosniff");
  }
});

test("the page has no inline script, event handler or style attribute", async () => {
  for (const path of await pageFiles()) {
    if (!path.endsWith("/") && !path.endsWith(".html")) continue;
    const html = await (await fetch(`${BASE}${path}`)).text();
    expect(html).not.toMatch(/<script(?![^>]*\bsrc=)/);
    expect(html).not.toMatch(/\son[a-z]+\s*=/i);
    expect(html).not.toMatch(/\sstyle\s*=/i);
  }
});

test("the page's code never builds markup from a value", async () => {
  for (const path of (await pageFiles()).filter((file) => file.startsWith("/app/js/"))) {
    const code = await (await fetch(`${BASE}${path}`)).text();
    expect(code, path).not.toMatch(/innerHTML|outerHTML|insertAdjacentHTML|document\.write|\beval\(|new Function|setAttribute\(\s*["']style["']/);
  }
});

test("a page on another origin cannot show the page in a frame", async ({ page, watch }) => {
  watch.ignoreViolations = true;
  const outer = createServer((request, response) => {
    response.setHeader("Content-Type", "text/html");
    response.end(`<!doctype html><body><iframe id="f" src="${BASE}/app/" width="800" height="600"></iframe></body>`);
  });
  await new Promise((resolve) => outer.listen(0, "127.0.0.1", resolve));
  try {
    watch.allowedOrigins.push(`http://127.0.0.1:${outer.address().port}`);
    await page.goto(`http://127.0.0.1:${outer.address().port}/`);
    await page.waitForTimeout(1500);
    for (const frame of page.frames()) {
      if (frame === page.mainFrame()) continue;
      const text = await frame.locator("body").innerText().catch(() => "");
      expect(text).not.toContain("SignalHub");
      expect(frame.url()).not.toMatch(/\/app\/$/);
    }
    // And the page itself loaded nothing from the framed address.
    expect(await page.locator("iframe").count()).toBe(1);
  } finally {
    outer.close();
  }
  watch.errors.length = 0;
});

test("the page makes no request to any other origin on any screen", async ({ context, page, watch }) => {
  const person = await createPerson("ADMIN");
  await useSession(context, await browserSession(person));
  for (const hash of ["#inbox", "#producers", "#producers/new", "#people", "#settings", "#settings/devices"]) {
    await page.goto(`/app/${hash}`);
    await page.waitForLoadState("networkidle");
  }
  const origin = new URL(BASE).origin;
  for (const url of watch.requests) {
    if (/^(data|blob):/.test(url)) continue;
    expect(new URL(url).origin, url).toBe(origin);
  }
  expect(watch.requests.length).toBeGreaterThan(20);
});

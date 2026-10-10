// The sample people, producers and events of the drawings (docs/design/users/source/Web - *.dc.html),
// made on a running SignalHub through the operator's token, so the page can be rendered with the
// drawings' content. It needs an EMPTY database: the names are the drawings' own (Rodrigo, Ana, ...)
// and a user's name is unique on a server. Never run it against a server that holds real data.

import { BASE, operator, publish } from "../support/server.mjs";

const FIREFOX_LINUX = "Mozilla/5.0 (X11; Linux x86_64; rv:130.0) Gecko/20100101 Firefox/130.0";
const CHROME_WINDOWS = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36";
const SAFARI_MAC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15";

async function json(method, path, { body, bearer, headers } = {}) {
  const response = await fetch(`${BASE}${path}`, {
    method,
    headers: { Accept: "application/json", ...(body ? { "Content-Type": "application/json" } : {}), ...(bearer ? { Authorization: `Bearer ${bearer}` } : {}), ...headers },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  if (!response.ok && response.status !== 204) throw new Error(`${method} ${path} -> ${response.status} ${text.slice(0, 200)}`);
  return { status: response.status, json: text ? JSON.parse(text) : null, response };
}

async function user(name, role) {
  return (await operator("POST", "/api/v1/admin/users", { name, role })).id;
}

async function device(userId, name) {
  const made = await operator("POST", "/api/v1/admin/clients", { name, userId });
  return { id: made.client.id, key: made.clientKey, name };
}

/** Signs a browser in the way a phone and a page do, and returns its cookie value. */
export async function browserSession(phone, userAgent) {
  const started = await json("POST", "/api/v1/web/sign-ins", { headers: { "User-Agent": userAgent } });
  const sign = started.json;
  const found = await json("POST", "/api/v1/client/web-sign-ins/lookup", { bearer: phone.key, body: { code: sign.code } });
  await json("POST", `/api/v1/client/web-sign-ins/${found.json.id}/approve`, { bearer: phone.key });
  const polled = await json("GET", `/api/v1/web/sign-ins/${sign.id}`, { bearer: sign.pollSecret });
  const cookie = polled.response.headers.getSetCookie().find((line) => line.startsWith("__Host-signalhub_session="));
  return { value: cookie.slice("__Host-signalhub_session=".length, cookie.indexOf(";")), id: (await json("GET", "/api/v1/web/session", { headers: { Cookie: cookie.split(";")[0] } })).json.client.id };
}

export async function seedWorld() {
  const world = { people: {}, producers: {}, events: {} };
  const ids = { rodrigo: await user("Rodrigo", "ADMIN"), ana: await user("Ana", "MOD"), joao: await user("João", "BASIC"), marta: await user("Marta", "BASIC"), rui: await user("Rui", "BASIC") };
  const rodrigo = { ...(await device(ids.rodrigo, "Rodrigo - Pixel 9")), id: ids.rodrigo, name: "Rodrigo", role: "ADMIN" };
  const ana = { ...(await device(ids.ana, "Ana - Pixel")), id: ids.ana, name: "Ana", role: "MOD" };
  const anaTablet = await device(ids.ana, "Ana - Tablet");
  const joao = { ...(await device(ids.joao, "João - phone")), id: ids.joao, name: "João", role: "BASIC" };
  const rui = { ...(await device(ids.rui, "Rui - iPhone")), id: ids.rui, name: "Rui", role: "BASIC" };
  world.people = { rodrigo, ana, joao, rui, marta: { id: ids.marta, name: "Marta", role: "BASIC" } };
  await operator("POST", `/api/v1/admin/clients/${anaTablet.id}/revoke`);

  const producer = async (owner, name, visibility) => {
    const made = await operator("POST", "/api/v1/admin/producers", { name, visibility, ownerId: owner.id });
    world.producers[name] = { id: made.producer.id, apiKey: made.apiKey, keyId: made.keyId, name };
    return world.producers[name];
  };
  const ci = await producer(rodrigo, "ci-pipeline", "PUBLIC");
  const homelab = await producer(rodrigo, "homelab-monitor", "PRIVATE");
  await producer(rodrigo, "weather-station", "PRIVATE");
  const anaReports = await producer(ana, "ana-reports", "PUBLIC");
  const family = await producer(ana, "family-calendar", "PRIVATE");
  await producer(joao, "weather-alerts", "PUBLIC");
  await producer(joao, "price-watch", "PUBLIC");
  const backup = await producer(joao, "backup-jobs", "PUBLIC");
  await operator("POST", `/api/v1/admin/producers/${ci.id}/keys`);
  await operator("POST", `/api/v1/admin/producers/${homelab.id}/keys`);
  // Who may see homelab-monitor, and Rodrigo's subscriptions beyond his own producers.
  await json("PUT", `/api/v1/client/producers/${homelab.id}/allowed-users/${ids.ana}`, { bearer: rodrigo.key });
  await json("PUT", `/api/v1/client/producers/${homelab.id}/allowed-users/${ids.marta}`, { bearer: rodrigo.key });
  await json("PUT", `/api/v1/client/producers/${family.id}/allowed-users/${ids.rodrigo}`, { bearer: ana.key });
  for (const target of [anaReports, family, backup]) await json("PUT", `/api/v1/client/visible-producers/${target.id}/subscription`, { bearer: rodrigo.key });

  // Oldest first, so the newest is on top as drawn. The ones drawn as read are marked read.
  const events = [
    ["certificate", homelab, { title: "Certificate renewed", category: "INFO", severity: "NORMAL" }, true],
    ["photos", backup, { title: "Photos synced", category: "COMPLETED", severity: "LOW" }, true],
    ["weekly", anaReports, { title: "Weekly report is ready", category: "INFO", severity: "NORMAL" }, false],
    ["deploy", ci, { title: "Deploy to staging done", category: "COMPLETED", severity: "LOW" }, true],
    ["disk", homelab, { title: "Disk almost full on nas-01", category: "BLOCKED", severity: "CRITICAL" }, false],
    ["backup", backup, { title: "Nightly backup finished", category: "INFO", severity: "NORMAL" }, false],
    [
      "approve",
      ci,
      {
        title: "Your action: approve the release",
        category: "ACTION_REQUIRED",
        severity: "HIGH",
        context: "release-3.0.0",
        message: "The release of 3.0.0 is waiting at the approval gate. Check the changelog and the upgrade notes, then approve it in the pipeline.",
        link: "https://example.org/pipelines/release-3.0.0",
      },
      true,
    ],
  ];
  for (const [key, from, body, read] of events) {
    const event = await publish(from, body);
    world.events[key] = event.id ?? event.event?.id;
    if (read) await json("PUT", `/api/v1/events/${world.events[key]}/read`, { bearer: rodrigo.key });
    await new Promise((resolve) => setTimeout(resolve, 20));
  }

  // The browsers: Rodrigo's own, and Rui's three (one revoked, as drawn in Devices).
  world.sessions = {
    rodrigo: await browserSession(rodrigo, FIREFOX_LINUX),
    ana: await browserSession(ana, CHROME_WINDOWS),
  };
  const ruiChrome = await browserSession(rui, CHROME_WINDOWS);
  const ruiSafari = await browserSession(rui, SAFARI_MAC);
  await operator("POST", `/api/v1/admin/clients/${ruiSafari.id}/revoke`);
  world.sessions.rui = await browserSession(rui, FIREFOX_LINUX);
  world.sessions.ruiChrome = ruiChrome;
  return world;
}

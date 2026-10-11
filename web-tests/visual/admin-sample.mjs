// The drawings' sample data for the admin page (docs/design/admin/README.md: Rodrigo is an admin, Ana
// a mod and Rui basic; the host is signalhub.example), served in place of the management API so a
// frame can be rendered with exactly the content of its drawing, with no server data and no token.
// Times are relative to NOW (12:41 on 11 Oct 2026, the drawings' clock), which the page is given too.

export const NOW = new Date("2026-10-11T12:41:00");
const MIN = 60_000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const at = (ms) => new Date(NOW.getTime() - ms).toISOString();
const day = (text) => new Date(`${text}T09:00:00`).toISOString();

const uuid = (n) => `01997d5e-0000-7000-8000-${String(n).padStart(12, "0")}`;
const user = (n, name, role) => ({ id: uuid(100 + n), name, role });
export const rodrigo = user(1, "Rodrigo", "ADMIN");
export const ana = user(2, "Ana", "MOD");
export const rui = user(3, "Rui", "BASIC");

const KEYS = {
  homelab: [
    { id: "3f1c0b8e-5d2a-4c7e-9b61-0a8d4e2f7c13", createdAt: day("2026-09-27"), lastUsedAt: at(12 * MIN), revokedAt: null },
    { id: "9a47c61d-0be3-4f10-8a2c-7d5e6b1f3a90", createdAt: day("2026-10-02"), lastUsedAt: null, revokedAt: null },
  ],
};

function producer(n, name, owner, visibility, last, keys, extra = {}) {
  return { id: uuid(200 + n), name, createdAt: day("2026-09-10"), disabledAt: null, disabledBy: null, lastEventAt: last === null ? null : at(last), keys, owner, visibility, allowedUsers: [], ...extra };
}

const oneKey = (n, used) => [{ id: `${["a1b2c3d4", "b2c3d4e5", "c3d4e5f6", "d4e5f607", "e5f60718", "f6071829", "07182930", "18293041"][n]}-1111-4222-8333-444455556666`, createdAt: day("2026-09-12"), lastUsedAt: used === null ? null : at(used), revokedAt: null }];

export const producers = [
  producer(1, "ana-reports", ana, "PUBLIC", DAY + 3 * HOUR, oneKey(0, DAY + 3 * HOUR)),
  producer(2, "backup-jobs", rodrigo, "PRIVATE", 2 * HOUR, oneKey(1, 2 * HOUR)),
  producer(3, "ci-pipeline", rodrigo, "PUBLIC", 4 * MIN, [...oneKey(2, 4 * MIN), ...oneKey(3, 5 * DAY)]),
  producer(4, "family-calendar", ana, "PRIVATE", 3 * DAY, oneKey(4, 3 * DAY), { allowedUsers: [rui] }),
  producer(5, "garage-door", rodrigo, "PRIVATE", 12 * DAY, [{ id: "b82e5f07-c1d4-4e2a-9f3b-6a7c8d9e0f12", createdAt: day("2026-09-10"), lastUsedAt: at(12 * DAY), revokedAt: null }], { disabledAt: day("2026-09-29"), disabledBy: "ADMIN" }),
  producer(6, "homelab-monitor", rodrigo, "PRIVATE", 12 * MIN, KEYS.homelab, { allowedUsers: [ana, rui], createdAt: day("2026-09-25") }),
  producer(7, "old-sensor", ana, "PUBLIC", 21 * DAY, oneKey(5, 21 * DAY)),
  producer(8, "price-watch", rui, "PUBLIC", 9 * DAY, oneKey(6, 9 * DAY)),
  producer(9, "quarterly-finance-report-generator", rodrigo, "PRIVATE", null, [
    { id: "c3d91a7e-4f06-4b8d-9e1a-2f3b4c5d6e70", createdAt: day("2026-10-04"), lastUsedAt: null, revokedAt: day("2026-10-07") },
    { id: "d70b2e8a-5c19-4a3e-8b6d-1e2f3a4b5c60", createdAt: day("2026-10-05"), lastUsedAt: null, revokedAt: day("2026-10-07") },
  ], { createdAt: day("2026-10-04") }),
  producer(10, "weather-alerts", rui, "PUBLIC", 3 * MIN, oneKey(7, 3 * MIN)),
];

function client(n, name, owner, extra = {}) {
  return {
    id: uuid(300 + n),
    name,
    admin: owner.role === "ADMIN" && !extra.kind,
    kind: "DEVICE",
    user: owner,
    createdAt: day("2026-09-25"),
    lastActiveAt: at(2 * MIN),
    expiresAt: null,
    revokedAt: null,
    pushTarget: { provider: "fcm", updatedAt: day("2026-09-25") },
    pushPreferences: {},
    pushStatus: { lastSuccess: { at: at(12 * MIN), eventId: uuid(900) }, lastFailure: null, pendingRetries: 0 },
    ...extra,
  };
}

const browser = (n, name, owner, active, signedIn, expires) => client(n, name, owner, { kind: "BROWSER", admin: false, lastActiveAt: at(active), createdAt: signedIn, expiresAt: expires, pushTarget: null, pushStatus: { lastSuccess: null, lastFailure: null, pendingRetries: 0 } });
const failedRetrying = { lastSuccess: { at: at(3 * HOUR), eventId: uuid(901) }, lastFailure: { at: at(40 * MIN), eventId: uuid(902), result: "TRANSIENT_FAILURE" }, pendingRetries: 2 };

export const clients = [
  client(1, "Rodrigo - Pixel 9", rodrigo),
  browser(2, "Rodrigo - Laptop browser", rodrigo, 5 * MIN, day("2026-10-04"), day("2026-11-03")),
  client(3, "Ana - Galaxy Tab", ana, { lastActiveAt: at(3 * HOUR), createdAt: day("2026-10-02"), pushStatus: failedRetrying }),
  client(4, "Ana - Pixel 8a", ana, { lastActiveAt: at(DAY) }),
  browser(5, "Ana - Home browser", ana, 2 * DAY, day("2026-10-01"), day("2026-10-31")),
  client(6, "Rui - iPhone 15", rui, { lastActiveAt: at(HOUR) }),
  browser(7, "Rui - Work laptop", rui, 9 * DAY, day("2026-09-30"), day("2026-10-30")),
  client(8, "Rodrigo - Old Pixel 6", rodrigo, { createdAt: day("2026-06-03"), lastActiveAt: day("2026-10-02"), revokedAt: day("2026-10-02") }),
  client(9, "Ana - Old phone", ana, { createdAt: day("2026-06-10"), lastActiveAt: day("2026-09-14"), revokedAt: day("2026-09-15") }),
];

export const users = [rodrigo, ana, rui].map((person) => ({ ...person, createdAt: day("2026-09-01"), revokedAt: null, devices: [], producers: [], subscriptions: [] }));

export const status = {
  pushProviders: ["fcm"],
  pushClientOptions: "fcm",
  pendingDispatches: 0,
  pendingRetries: 0,
  abandonedRetries: 0,
  eventRetentionSeconds: 31_536_000,
  startedAt: new Date("2026-10-03T08:12:00").toISOString(),
};

// ---- Events ---------------------------------------------------------------------------------

const producerRef = (name) => {
  const found = producers.find((candidate) => candidate.name === name);
  return { id: found.id, name };
};
const eventId = (n) => uuid(1000 + n);

function event(n, title, producerName, category, severity, ago, extra = {}) {
  return {
    id: eventId(n),
    title,
    message: null,
    category,
    severity,
    context: null,
    link: null,
    occurredAt: null,
    createdAt: at(ago),
    readAt: null,
    metadata: {},
    producer: producerRef(producerName),
    push: "SENT",
    ...extra,
  };
}

const read = (ago) => at(ago - MIN);

/** The events of the drawings (Admin - Events), newest first: the first seven are the ones drawn. */
export const events = [
  event(1, "Rain expected at 16:00", "weather-alerts", "INFO", "LOW", 3 * MIN),
  event(2, "Build 1842 failed on main", "ci-pipeline", "BLOCKED", "HIGH", 4 * MIN, {
    message: "3 of 412 tests failed on main. The deploy to staging was not started.",
    context: "signalhub-web",
    link: "https://ci.signalhub.example/runs/1842",
    occurredAt: at(5 * MIN),
    push: "FAILED",
    metadata: { branch: "main", commit: "a1b2c3d", failed_tests: 3, run: 1842, jobs: ["unit", "lint"] },
  }),
  event(3, "Disk usage above 90% on nas-01", "homelab-monitor", "ACTION_REQUIRED", "CRITICAL", 12 * MIN),
  event(4, "Deploy to staging needs approval", "ci-pipeline", "ACTION_REQUIRED", "HIGH", 48 * MIN),
  event(5, "Nightly backup finished", "backup-jobs", "COMPLETED", "NORMAL", 2 * HOUR, { readAt: read(2 * HOUR) }),
  event(6, "Build 1841 passed on main", "ci-pipeline", "COMPLETED", "LOW", 2 * HOUR + 5 * MIN, { readAt: read(2 * HOUR) }),
  event(7, "Frost warning for tonight", "weather-alerts", "INFO", "NORMAL", 6 * HOUR, { readAt: read(6 * HOUR) }),
  event(8, "Weekly report is ready", "ana-reports", "INFO", "NORMAL", DAY + 3 * HOUR, { readAt: read(DAY) }),
  event(9, "Nightly backup finished", "backup-jobs", "COMPLETED", "NORMAL", 5 * DAY + 4 * HOUR, { createdAt: new Date("2026-10-06T03:10:00").toISOString(), readAt: read(5 * DAY) }),
  event(10, "Build 1830 passed on main", "ci-pipeline", "COMPLETED", "LOW", 8 * DAY, { createdAt: new Date("2026-10-03T14:02:00").toISOString(), readAt: read(8 * DAY) }),
  ...Array.from({ length: 15 }, (_, index) => event(11 + index, `Heartbeat ${index + 1}`, "backup-jobs", "INFO", "LOW", (9 + index) * DAY, { readAt: read(9 * DAY) })),
];
export const EVENTS_TOTAL = 1284;

/** The listing, as the server answers it: the filters it takes, the newest 25, a cursor and the total. */
export function listEvents(url) {
  const params = new URL(url).searchParams;
  const many = (name) => params.getAll(name);
  const wanted = (name, values) => !values.length || values.includes(name);
  let matching = events.filter((item) => wanted(item.producer.id, many("producerId")) && wanted(item.severity, many("severity")) && wanted(item.category, many("category")));
  if (params.get("read") === "false") matching = matching.filter((item) => !item.readAt);
  if (params.get("read") === "true") matching = matching.filter((item) => item.readAt);
  if (params.has("push")) matching = matching.filter((item) => many("push").includes(item.push));
  if (params.get("createdFrom")) matching = matching.filter((item) => item.createdAt >= params.get("createdFrom"));
  if (params.get("createdBefore")) matching = matching.filter((item) => item.createdAt < params.get("createdBefore"));
  const limit = Number(params.get("limit") ?? 25);
  const filtered = [...params.keys()].some((key) => !["limit", "total", "cursor"].includes(key));
  const body = { items: params.get("cursor") ? [] : matching.slice(0, limit), nextCursor: !params.get("cursor") && !filtered && matching.length >= limit ? "next-page" : null };
  if (params.get("total") === "true") body.total = filtered ? matching.length : EVENTS_TOTAL;
  return body;
}

const device = (name, owner, kind = "DEVICE") => {
  const found = clients.find((candidate) => candidate.name === name);
  return found ?? { id: uuid(400 + name.length), name, user: owner, kind };
};

const record = (clientId, clientName, owner, outcome, minute, extra = {}) => ({
  clientId,
  clientName,
  userId: owner.id,
  userName: owner.name,
  attempt: 1,
  outcome,
  detail: null,
  at: new Date(`2026-10-11T12:37:0${minute}`).toISOString(),
  final: true,
  ...extra,
});

const browserId = clients.find((candidate) => candidate.name === "Rodrigo - Laptop browser").id;

/** The pushes of Build 1842 (E2): sent, no push address, waiting for a retry, failed, filtered. */
export const deliveries = {
  items: [
    record(clients[0].id, "Rodrigo - Pixel 9", rodrigo, "DELIVERED", 2),
    record(browserId, "Rodrigo - Firefox", rodrigo, "NO_TARGET", 2),
    record(clients[2].id, "Ana - Pixel", ana, "TRANSIENT_FAILURE", 3, { detail: "UNAVAILABLE (503)", final: false }),
    record(clients[3].id, "Ana - Tablet", ana, "INVALID_TARGET", 3, { detail: "UNREGISTERED" }),
    record(clients[5].id, "Rui - iPhone", rui, "FILTERED", 2, { detail: "below the minimum severity" }),
  ],
  users: [
    { id: rodrigo.id, name: "Rodrigo", owner: true },
    { id: ana.id, name: "Ana", owner: false },
    { id: rui.id, name: "Rui", owner: false },
  ],
};

/** E2b: the other wordings. */
export const otherDeliveries = {
  items: [
    record(clients[2].id, "Ana - Pixel", ana, "TRANSIENT_FAILURE", 3, { attempt: 5, detail: "UNAVAILABLE (503)" }),
    record(clients[3].id, "Ana - Tablet", ana, "PERMANENT_FAILURE", 3, { detail: "INVALID_ARGUMENT (400)" }),
    record(clients[5].id, "Rui - iPhone", rui, "UNSUPPORTED_PROVIDER", 2, { detail: "apns" }),
    record(device("Rui - Tablet", rui).id, "Rui - Tablet", rui, "FILTERED", 2, { detail: "pushes paused" }),
    record(device("Rui - Watch", rui).id, "Rui - Watch", rui, "FILTERED", 2, { detail: "producer muted" }),
  ],
  users: [
    { id: ana.id, name: "Ana", owner: false },
    { id: rui.id, name: "Rui", owner: false },
  ],
};

/** The devices with Rui's iPhone asking to skip what is below Critical (E2). */
export const eventClients = clients.map((candidate) => (candidate.name === "Rui - iPhone 15" ? { ...candidate, pushPreferences: { enabled: true, minimumSeverity: "CRITICAL", mutedCategories: [], mutedProducerIds: [] } } : candidate));

export const info = { signalhub: { version: "3.8.0", revision: "a1b2c3d4e5f60718293a4b5c6d7e8f9012345678" } };
export const health = { status: "UP", checks: [{ name: "Database connections health check", status: "UP", data: { "<default>": "UP" } }] };
export const latestEvent = { id: uuid(950), title: "Rain expected at 15:00", category: "INFO", severity: "NORMAL", createdAt: at(MIN), producer: { id: producers[9].id, name: "weather-alerts" }, readAt: null };

/**
 * Answers the management API, /q/health and /q/info from this data (or from `data`'s overrides: a
 * value, or a function of the request), and holds the page's clock at NOW. Nothing reaches the
 * server except the page's own files.
 */
export async function mockAdmin(page, data = {}) {
  const world = { clients, producers, users, status, info, health, latest: [latestEvent], pairings: [], ...data };
  await page.clock.setFixedTime(NOW);
  const json = (route, body, code = 200) => route.fulfill({ status: code, contentType: "application/json", body: JSON.stringify(body) });
  const answer = async (route, value, wrap = (x) => x) => {
    const body = typeof value === "function" ? await value(route.request()) : value;
    if (body === "abort") return route.abort();
    if (body && body.__status) return json(route, body.body ?? {}, body.__status);
    return json(route, wrap(body));
  };
  await page.route("**/api/v1/admin/clients", (route) => answer(route, world.clients, (items) => ({ items })));
  await page.route("**/api/v1/admin/producers", (route) => answer(route, world.producers, (items) => ({ items })));
  await page.route("**/api/v1/admin/users", (route) => answer(route, world.users, (items) => ({ items })));
  await page.route("**/api/v1/admin/pairings", (route) => answer(route, world.pairings, (items) => ({ items })));
  await page.route("**/api/v1/admin/status", (route) => answer(route, world.status));
  // The listing (any filters) and the single newest event the Status page reads; later routes win.
  await page.route("**/api/v1/events?*", (route) => {
    const url = route.request().url();
    if (new URL(url).searchParams.get("limit") === "1" && !url.includes("total=")) return answer(route, world.latest, (items) => ({ items, nextCursor: null }));
    return answer(route, world.eventList ?? ((request) => listEvents(request.url())));
  });
  await page.route(/\/api\/v1\/events\/[0-9a-f-]{36}$/, (route) => {
    const found = events.find((item) => route.request().url().endsWith(item.id));
    return route.request().method() === "GET" ? answer(route, world.eventDetail ?? found ?? { __status: 404, body: { title: "Not Found" } }) : answer(route, found);
  });
  await page.route(/\/api\/v1\/admin\/events\/[0-9a-f-]{36}\/deliveries$/, (route) => {
    const id = route.request().url().split("/").at(-2);
    return answer(route, world.deliveries ? (typeof world.deliveries === "function" ? world.deliveries(id) : world.deliveries) : id === events[1].id ? deliveries : { items: [], users: [] });
  });
  await page.route("**/q/health", (route) => answer(route, world.health));
  await page.route("**/q/info", (route) => answer(route, world.info));
  // Deleting events: a dry run counts, the real request answers with the same count.
  await page.route("**/api/v1/admin/events/delete", (route) => {
    const body = route.request().postDataJSON();
    return answer(route, { count: world.deleteCount ?? (body.ids ? body.ids.length : 42) });
  });
  await page.route(/\/api\/v1\/admin\/producers\/[0-9a-f-]{36}\/events$/, (route) => answer(route, { ...events[0], id: eventId(99), title: route.request().postDataJSON().title, producer: { id: producers[2].id, name: "ci-pipeline" } }));
  for (const [pattern, value] of Object.entries(world.routes ?? {})) await page.route(pattern, (route) => answer(route, value));
  return world;
}

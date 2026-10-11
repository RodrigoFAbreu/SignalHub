// What the Status page and the rail's status button say, from what the management API and the
// server's health and info pages answered. Pure data in, plain data out: no DOM, so the one rule
// that decides "needs attention" is written once (docs/design/users/DESIGN.md, 9.5).
//
// SignalHub needs attention when: the database is down; no push service is set up; every device
// that has a push address failed its last push (at least one such device), so the push service is
// likely down; the events waiting to be pushed are above 20 and did not fall over two checks;
// retries were given up since this page was opened; or a part could not be read. One device's
// failure is a row warning with a link to Devices, never the headline.

import { agoLong, dateTime, duration, plural } from "./format.js";

export const WAITING_LIMIT = 20;
const PROVIDERS = { fcm: "Firebase Cloud Messaging" };

/** A part of the read: `{ok: true, value}` or `{ok: false, error}`; null while it was not asked. */
const read = (part) => part?.ok === true;
const failure = (part) => (part?.error?.kind === "unreachable" ? "SignalHub did not answer" : (part?.error?.message ?? "no answer").replace(/\.$/, ""));
const cannot = (part) => `Could not read: ${(part?.error?.message ?? "no answer").replace(/\.$/, "")}.`;

/** An active device whose latest push result is a failure; a later success clears it. */
export function lastPushFailed(client) {
  const { lastSuccess, lastFailure } = client.pushStatus;
  if (client.revokedAt || !lastFailure) return false;
  return !lastSuccess || Date.parse(lastFailure.at) > Date.parse(lastSuccess.at);
}

/** The active devices that have a push address, and which of those failed their last push. */
export function pushDevices(clients) {
  const withAddress = clients.filter((client) => !client.revokedAt && client.pushTarget);
  return { withAddress, failing: withAddress.filter(lastPushFailed) };
}

function providerName(name) {
  return PROVIDERS[name] ?? name;
}

function outboxRises(samples) {
  if (samples.length < 2) return null;
  const [before, now] = samples.slice(-2);
  return now > WAITING_LIMIT && now >= before ? before : null;
}

/** Rows have `status` ok, bad, un (could not read), look (a warning that is not the headline), or null. */
function row(id, glyph, name, status, text, advice, extra = {}) {
  return { id, glyph, name, status, text, advice, ...extra };
}

/**
 * The rows of Status and its headline. `ctx`: `baseline` (abandoned retries when the page opened),
 * `outbox` (the last waiting counts seen, oldest first), `now`.
 */
export function assess(parts, ctx) {
  const { info, health, status, clients, latest } = parts;
  const rows = { delivering: [], activity: [], server: [] };
  const present = [info, health, status, clients, latest].filter(Boolean);
  const nothingRead = present.length > 0 && present.every((part) => !part.ok);

  // The devices, when they were read: every judgement about pushes that needs them.
  const devices = read(clients) ? pushDevices(clients.value.items) : null;
  const allFailed = devices && devices.withAddress.length > 0 && devices.failing.length === devices.withAddress.length;

  // Database
  if (read(health)) {
    const checks = health.value.checks || [];
    const database = checks.find((check) => /database/i.test(check.name));
    const down = database ? database.status !== "UP" : health.value.status !== "UP";
    rows.delivering.push(
      down
        ? row("database", "database", "Database", "bad", "Not connected. SignalHub cannot store or read events right now.", {
            label: "What to do",
            text: "check that the database container is running (docker compose ps) and read its log. SignalHub reconnects by itself and this page looks again every 30 seconds.",
          })
        : row("database", "database", "Database", "ok", "Connected. Events are being stored and read.", {
            label: "If it goes wrong",
            text: "events cannot be stored. Check that the database container is running (docker compose ps). SignalHub reconnects by itself.",
          }),
    );
  } else if (health) {
    rows.delivering.push(unreadable("database", "Database", health, "use Refresh. If it stays, read the server's log."));
  }

  // Push service
  if (read(status)) {
    const providers = status.value.pushProviders;
    if (providers.length === 0) {
      rows.delivering.push(
        row("push", "notifications_off", "Push service", "bad", "Not set up: nothing is pushed. Events are stored, and show in the app and the web page when they are opened.", {
          label: "What to do",
          text: "add the push service's key file in the server's .env (see Push in docs/deployment.md) and restart.",
        }),
      );
    } else if (allFailed) {
      const names = providers.map(providerName).join(", ");
      rows.delivering.push(
        row(
          "push",
          "notification_important",
          "Push service",
          "bad",
          `${names} is set up, but every device with a push address failed its last push (${devices.failing.length} of ${devices.withAddress.length}): the push service is probably down, or refusing this server.`,
          {
            label: "What to do",
            text: "open Devices and read each failure. If every device fails, the key file may be wrong or revoked: replace it in the server's .env and restart.",
          },
        ),
      );
    } else {
      const names = providers.map(providerName).join(", ");
      const served = status.value.pushClientOptions;
      rows.delivering.push(
        row(
          "push",
          "notifications_active",
          "Push service",
          "ok",
          served
            ? `${names} is set up, and apps are given their push options by this server.`
            : `${names} is set up. This server does not give apps their push options: only apps with them built in can receive pushes.`,
          {
            label: "If it goes wrong",
            text: "events are kept but no phone is told. Check the push service's key file in the server's .env, then restart.",
          },
        ),
      );
    }

    // Events waiting to be pushed
    const waiting = status.value.pendingDispatches;
    const grew = outboxRises(ctx.outbox);
    rows.delivering.push(
      grew !== null
        ? row("waiting", "schedule_send", "Events waiting to be pushed", "bad", `${plural(waiting, "event")} waiting, up from ${grew} at the check before.`, {
            label: "What to do",
            text: "the number should fall to 0 within seconds. If it keeps growing, SignalHub is not keeping up: the push service or the database is slow. Look at Push service above, then at the server's log.",
          }, { short: "Events to be pushed" })
        : row("waiting", "schedule_send", "Events waiting to be pushed", "ok", `${plural(waiting, "event")} waiting`, {
            label: "If it goes wrong",
            text: "a few for a second or two is normal. A number that keeps growing means SignalHub is not keeping up: the push service or the database is slow.",
          }, { short: "Events to be pushed" }),
    );

    // Pushes waiting for a retry, and the ones given up since this page opened
    const given = Math.max(0, status.value.abandonedRetries - (ctx.baseline ?? status.value.abandonedRetries));
    const text = `${status.value.pendingRetries} waiting · ${given} given up since you opened this page`;
    rows.delivering.push(
      given > 0
        ? row("retries", "replay", "Pushes waiting for a retry", "bad", text, {
            label: "What to do",
            text: "the waiting number grows while the push service refuses pushes. Fix the push service first; the waiting ones are then sent by themselves. The given-up ones are not retried, but their events are in the inbox.",
          }, { short: "Waiting for a retry" })
        : row("retries", "replay", "Pushes waiting for a retry", "ok", text, {
            label: "If it goes wrong",
            text: "a temporary failure is tried again by itself, up to 5 tries in all. A push that was given up is not tried again, but its event is still in the inbox.",
          }, { short: "Waiting for a retry" }),
    );
  } else if (status) {
    rows.delivering.push(
      unreadable("push", "Push service", status, "use Refresh. The other rows are from the same check and can be trusted. If it stays, read the server's log."),
      unreadable("waiting", "Events waiting to be pushed", status, "use Refresh. If it stays, read the server's log.", "Events to be pushed"),
      unreadable("retries", "Pushes waiting for a retry", status, "use Refresh. The other rows are from the same check and can be trusted. If it stays, read the server's log.", "Waiting for a retry"),
    );
  }

  // Devices whose last push failed
  if (read(clients)) {
    const failing = clients.value.items.filter(lastPushFailed);
    if (failing.length === 0) {
      rows.delivering.push(
        row("devices", "phonelink_erase", "Devices whose last push failed", "ok", "None", {
          label: "If some are listed",
          text: "open Devices (with Push problems chosen); each one says in words why its last push failed.",
        }, { short: "Last push failed on", shortText: "No device" }),
      );
    } else {
      const names = failing.map((client) => client.name);
      rows.delivering.push(
        row(
          "devices",
          "phonelink_erase",
          "Devices whose last push failed",
          "look",
          `${failing.length === 1 ? "1 device's" : `${failing.length} devices'`} last push failed: ${names.join(", ")}`,
          { label: null, text: "Opens Devices with Push problems chosen. Each device says in words why its last push failed, and whether SignalHub is trying again." },
          { link: { label: "Open Devices", href: "#devices?f=problems" }, short: "Last push failed on", shortText: `${plural(failing.length, "device")}` },
        ),
      );
    }
  } else if (clients) {
    rows.delivering.push(unreadable("devices", "Devices whose last push failed", clients, "use Refresh. If it stays, read the server's log.", "Last push failed on"));
  }

  // Activity
  if (read(latest)) {
    const [event] = latest.value.items;
    rows.activity.push(
      event
        ? row("last-event", "inbox", "Last event received", null, `${agoLong(event.createdAt, ctx.now)}, from ${event.producer.name}: ${event.title}`, {
            label: null,
            text: "A quiet period is not a fault. Producers marks the ones that have not sent for a week.",
          }, { link: { label: "Open event", href: `#events/${event.id}` } })
        : row("last-event", "inbox", "Last event received", null, "None stored", {
            label: null,
            text: "A quiet period is not a fault. Producers marks the ones that have not sent for a week.",
          }),
    );
  } else if (latest) {
    rows.activity.push(unreadable("last-event", "Last event received", latest, "use Refresh. If it stays, read the server's log."));
  }
  if (read(clients)) {
    let best = null;
    for (const client of clients.value.items) {
      const success = client.pushStatus.lastSuccess;
      if (success && (!best || Date.parse(success.at) > Date.parse(best.at))) best = { at: success.at, name: client.name };
    }
    rows.activity.push(
      best
        ? row("last-push", "notifications", "Last push sent", null, `${agoLong(best.at, ctx.now)}, to ${best.name}`, {
            label: null,
            text: "Taken from the devices' last push results. A quiet day has none to show.",
          })
        : row("last-push", "notifications", "Last push sent", null, "None to show", {
            label: null,
            text: "No device's last push was accepted, so nothing has been delivered lately.",
          }),
    );
  } else if (clients) {
    rows.activity.push(unreadable("last-push", "Last push sent", clients, "use Refresh. If it stays, read the server's log."));
  }

  // This server
  if (read(info)) {
    const build = info.value.signalhub || {};
    const development = !build.version || build.version === "development";
    rows.server.push(
      row("version", "info", "Version", null, development ? "development" : `${build.version}`, {
        label: null,
        text: development
          ? "This server was not built from a release, so it has no version number and shows no revision. Releases say 3.8.0 and the like."
          : "The release this server is running. A build that is not a release says development and shows no revision.",
      }, { mono: development ? null : build.revision ? build.revision.slice(0, 7) : null }),
    );
  } else if (info) {
    rows.server.push(unreadable("version", "Version", info, "use Refresh. If it stays, read the server's log."));
  }
  if (read(status) && status.value.startedAt) {
    const started = Date.parse(status.value.startedAt);
    rows.server.push(
      row("started", "timer", "Running since", null, `${dateTime(status.value.startedAt)}, ${uptime(ctx.now - started)}`, { label: null, text: null }),
    );
  }
  if (read(status) && status.value.eventRetentionSeconds !== null && status.value.eventRetentionSeconds !== undefined) {
    rows.server.push(
      row("retention", "delete_sweep", "Event retention", null, `Events older than ${duration(status.value.eventRetentionSeconds)} are deleted by themselves.`, {
        label: null,
        text: "Set by SIGNALHUB_EVENTS_RETENTION in the server's .env. When it is not set the row is not shown and events are kept for ever.",
      }),
    );
  }

  const all = [...rows.delivering, ...rows.activity, ...rows.server];
  const attention = all.filter((item) => item.status === "bad" || item.status === "un");
  const look = all.filter((item) => item.status === "look");
  const ids = new Set([...attention, ...look].map((item) => item.id));
  const working = rows.delivering.filter((item) => !ids.has(item.id));

  return { rows, attention, look, working, problems: attention.length, nothingRead, headline: headline(attention, parts, nothingRead) };
}

function unreadable(id, name, part, text, short) {
  return row(id, "help", name, "un", cannot(part), { label: "What to do", text }, short ? { short } : {});
}

function uptime(ms) {
  const minutes = Math.floor(ms / 60000);
  if (minutes < 1) return "less than a minute";
  if (minutes < 60) return plural(minutes, "minute");
  if (minutes < 60 * 24) return plural(Math.floor(minutes / 60), "hour");
  return plural(Math.floor(minutes / (60 * 24)), "day");
}

function headline(attention, parts, nothingRead) {
  if (nothingRead) {
    const error = [parts.status, parts.health, parts.info, parts.clients, parts.latest].find((part) => part && !part.ok);
    return {
      state: "unknown",
      title: "Cannot tell if SignalHub is working",
      sentence: `The status could not be read: ${failure(error)}. It is trying again every 30 seconds.`,
    };
  }
  if (attention.length === 0) {
    return { state: "working", title: "SignalHub is working", sentence: "Events are being stored and pushes are going out. Nothing needs attention." };
  }
  const bad = new Set(attention.filter((item) => item.status === "bad").map((item) => item.id));
  let what = "Some parts need a look.";
  if (bad.has("database")) what = "Events cannot be stored or read right now.";
  else if (attention.some((item) => item.id === "push" && item.glyph === "notifications_off")) {
    what = "Events are still being received and stored, but nothing is pushed to phones.";
  } else if (bad.size > 0) what = "Events are still being received and stored, but pushes to phones are failing.";
  else if (attention.length > 0) what = "Some parts could not be read.";
  return {
    state: "attention",
    title: "SignalHub needs attention",
    sentence: `${what} ${plural(attention.length, "thing")} to look at${attention.length > 0 ? ":" : "."}`,
    jumps: attention.map((item) => ({ id: item.id, label: item.name })),
  };
}

/** The rail button's state, from the same assessment. */
export function railState(parts, ctx, first) {
  if (first) return { state: "checking", count: 0 };
  const verdict = assess(parts, ctx);
  if (verdict.nothingRead) return { state: "unknown", count: 0 };
  return verdict.problems > 0 ? { state: "check", count: verdict.problems } : { state: "working", count: 0 };
}

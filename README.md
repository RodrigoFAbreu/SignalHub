# SignalHub

A producer-agnostic personal notification platform.

Any system can publish generic events to SignalHub: autonomous agents, CI
pipelines, monitoring, homelab services, or one-off scripts. SignalHub persists
the events and delivers notifications about them to the devices of the people it serves.
Producers share one generic event contract, and SignalHub has no special cases
for individual producers.

## Intended architecture

```
producers ──HTTPS──▶ backend (Quarkus + PostgreSQL) ──push──▶ clients
    ▲                                              ◀─HTTPS──
optional SDK/CLI
```

- **Backend:** Java 25, Quarkus (Quarkus REST, Hibernate ORM with Panache,
  Flyway, Jakarta Validation, SmallRye OpenAPI and Health), PostgreSQL
- **Push delivery:** a push provider, likely Firebase Cloud Messaging
- **Client app:** Flutter, one codebase for Android and iOS, with push
  through Firebase Cloud Messaging. The API is client-agnostic, so other
  clients (web, CLI) remain possible.
- **Producer client:** optional thin SDK/CLI over the HTTP API, in Python
- **Deployment:** Docker / Docker Compose, on x86-64 and ARM64 (such as a
  Raspberry Pi 5)

See [docs/architecture.md](docs/architecture.md).

## Status

Early development.

| Component | Status |
|---|---|
| Backend (`backend/`) | Quarkus service with PostgreSQL, Flyway, health checks, OpenAPI, Docker image and Compose. Generic event ingestion: `POST /api/v1/events`, idempotent with an optional `Idempotency-Key` header, with an optional `link` the owner can open from the event, and `GET /api/v1/events/{id}` with a client key or the admin token. Paginated event listing (the inbox), filterable by producer, category, severity, time and read state: `GET /api/v1/events`. Users, roles and subscriptions: several people share one server, each user (basic, mod or admin, invited by the operator, with no passwords) with their own devices, producers and subscriptions, receiving only the events of the producers they are subscribed to (public producers are open to subscribe, private ones to their owner and allow-list), while producers keep the same API. Every user manages their own producers from their device with its client key, with no work on the machine: they register a producer and get its key (shown once), list their producers (keys by prefix), issue and revoke keys, disable and enable, rename, make a producer public or private, and allow users on a private one by name; they list the producers they may see (public, their own, allowed) and subscribe or unsubscribe, and list the users' names (an admin's device also gets each user's role, active devices and whether they have paired, and reads the producers a user owns). Other users' producers are never reachable. Read state shared by all of a user's devices: mark events read or unread, one at a time or up to an event, and count unread events. Producer authentication with server-issued API keys, managed through an admin-token-protected API or on the admin page's Producers section, which lists every producer with its keys and when it last published (a quiet one stands out), creates producers, shows each new key once to copy, issues and revokes keys, and disables and enables producers. The admin page's Events section browses every event a page at a time, with the inbox's filters (producer, category, severity, read state), and opens one with its details, its metadata as formatted JSON and its link (opened in a new tab), to mark it read or unread, and with its deliveries: one line per device, by name, saying whether its push was delivered to the push service, filtered out by the device's preferences (and which), not sent for want of a push target, or failed and why, with each retry (`GET /api/v1/admin/events/{id}/deliveries`, kept as long as the event). The operator follows each user's traffic there, for testing and debugging: the Events section filters by user (the events of the producers they own or are subscribed to), an open event lists the users it reached with each of their devices' deliveries, and the Users section shows a user's recent events and deliveries (`GET /api/v1/admin/users/{id}/traffic`). The operator deletes test or unwanted events there or through the management API: one, a selection, every event of a producer or every event received before a time, each after a confirmation stating how many a dry run counted (with their pending pushes and delivery records; producers and devices stay); otherwise only retention deletes events. To check that pushes arrive and that the devices' preferences filter a producer as expected, the operator sends a test event as an existing, enabled producer from the Events section or through the management API; it is stored and pushed exactly as that producer's own event would be, and linked once sent so it can be opened and deleted. The admin page's Status section answers "is SignalHub working?" on one screen: the release and commit, health, whether push is configured and apps are given push options, pushes waiting and retrying, retries given up, devices whose last push failed, the retention period and when the most recent event arrived, marking what needs attention (the parts the page cannot read elsewhere summed up by `GET /api/v1/admin/status`). Client registration: each client installation gets its own key for reading events and stores a provider-neutral push target. A new device can register itself by redeeming a one-time pairing code (with a pairing URI to show as a QR code) that the operator creates, so it needs neither the admin token nor a typed key; the operator's admin page (`/admin/`, on the host only, in sections: Devices, Users, Producers, Events and Status) makes the code for a user and shows it as a QR code to scan, copy or download (a device is an admin device when its user is an admin), until a device uses it, then names that device and is ready for the next one, and the user's devices and the admins' get a push when a device pairs. The Users section invites users, renames them, sets their role (making an admin is done only there), subscribes them and revokes them (their devices and producers stop working; their events stay), and Producers shows each owner and who sees it. Whoever created a pairing, the operator or a device, can ask whether its code was used and by which device, never seeing a code or a key. The admin page also lists every device, revoked or not, with its push results, with its user, to rename it and revoke it, and deletes revoked devices (with their push results and unused pairing codes; events stay); each client's registration says whether it is an admin device. Through the client API, as its user's role allows, a mod renames, revokes and deletes their own devices and pairs for themselves, and an admin does so for every device of users who are not admins and pairs for any user, invites users (a first pairing code with them) and sets their role to basic or mod (a basic user changes no device; nothing is done to an admin's device, which only the admin page can do), and the affected devices get a push naming it (none for a deletion). Push notifications: every published event is pushed, durably and at least once, with bounded retries of temporary failures, to every client with a push target whose user is subscribed to the event's producer and whose push preferences allow it (paused, minimum severity, muted categories or producers), through Firebase Cloud Messaging (enabled by a service account key file, every push sent with high priority so it reaches a dozing phone at once) behind a provider-neutral boundary. The management API shows each client's last successful and last failed push (with the provider's result) and its pushes waiting for a retry. The server can also give its clients the app's push options (for FCM, the Firebase options) at `GET /api/v1/client/push-config`, so an app need not have them built in, and the app uses them. Prometheus metrics at `/q/metrics`, including events published and push delivery results and backlog. Optional JSON logs for log collectors and a startup summary of the release and the effective configuration, without secrets. Every release publishes the backend image for x86-64 and ARM64 as `ghcr.io/rodrigofabreu/signalhub:X.Y.Z`, which reports its release and commit at `/q/info`, and attaches the deployment files that run it, so installs and upgrades build nothing. An optional retention period after which old events are deleted. Documented, tested backup and restore of the database, and memory, CPU and storage guidance. Runs on x86-64 and ARM64, both checked natively in CI. An optional TLS reverse proxy (Caddy, with Let's Encrypt or its own CA) serves only the product API to other machines; upgrades (tested in CI from the latest release and from v0.13.0, skipping every release since; an older release refuses to start on a database a newer one migrated) and health monitoring are documented in [docs/deployment.md](docs/deployment.md). |
| Client app (`client/`) | Flutter app for Android and iOS: sets itself up by scanning or pasting a pairing code the operator or an admin device made, or with a server address and client key typed in, and keeps its key in secure storage; registers for push notifications (Firebase Cloud Messaging with the owner's Firebase project, whose options the server serves or the build carries), and shows the inbox: every event, newest first, page by page, with each event's details, also opened by tapping its notification, and filters for unread events, producers, categories and severities, applied by the server; an event's link opens in the system browser from its screen. Unread events and their count are shown; opening an event marks it read on every client, and events can be marked unread or all read. Push preferences for the device: pause, minimum severity, muted categories and producers. On Android, SignalHub's own alert, set in the app and kept on the device: one of five bundled sounds or none, its volume, and SignalHub's own vibration at three strengths or off, in one of four patterns and three lengths, for every push, whether the app is open or not, within the phone's notification settings, and within its silent mode and do-not-disturb except for the pushes the owner chooses to sound through them (none, critical ones or all: by default critical ones on silent, none during do-not-disturb, which also needs the app's Do Not Disturb access); and for critical events, chosen by their severity alone, an alert of their own if the owner wants one. Its settings are on one *Settings* screen, opened by a gear icon on the inbox, in folding groups (*Push filters*, *Alert*, with the critical alert's own settings in a sub-group that opens once the owner wants one, *This device*) that sum up their values while folded and stay open as the owner left them. Its *This device* group names the SignalHub build it is and the commit it was built from, and disconnects the device after a confirmation; on an admin device a *Devices* row opens every device, to make one an admin, revoke one that is not an admin or delete a revoked one, and connects a new device by showing a pairing code as a QR code with its countdown and a link to copy, until a device uses it, then names that device and is ready for the next one. Every release attaches the Android app, `SignalHub-X.Y.Z.apk`, signed with SignalHub's release key and set up for push by the server, so phones install and update it without building it. See [client/README.md](client/README.md#install-a-release). A scripted functional review on an Android phone over `adb`, review tooling rather than product code, is in [scripts/device-review/](scripts/device-review/README.md). |
| Producer SDK/CLI (`sdk/python/`) | Python package and `signalhub send` command over the public HTTP API: configured with the server address and an API key from the environment or a file, arbitrary metadata, an optional link (`--link`), an optional idempotency key so failed sends can be retried safely, the server's validation errors printed, and exit statuses that tell rejected events from temporary failures. Standard library only. Every release attaches its wheel and source archive, which report that release (`signalhub --version`). See [sdk/python/README.md](sdk/python/README.md). |
| Integration examples (`examples/`) | Small producers over the same public API, with nothing special in the backend: a shell wrapper that reports a command's outcome, a disk-usage monitor, a GitHub Actions workflow that reports failed runs, a coding-agent hook for human gates and completions (Claude Code hooks), and a usage-threshold monitor for quotas and budgets. See [examples/README.md](examples/README.md). |

Run the backend with PostgreSQL from a checkout, built from source (to deploy a release instead, see [docs/deployment.md](docs/deployment.md#setup)):

```sh
cp .env.example .env   # set SIGNALHUB_DB_PASSWORD and SIGNALHUB_ADMIN_TOKEN
docker compose up --build --wait
curl http://localhost:8080/q/health/ready

# Register a producer; the response shows its API key once.
ADMIN_TOKEN=$(sed -n 's/^SIGNALHUB_ADMIN_TOKEN=//p' .env)
API_KEY=$(curl -s http://localhost:8080/api/v1/admin/producers \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "my-script"}' | jq -r .apiKey)

# Publish an event as that producer.
curl http://localhost:8080/api/v1/events -H "Authorization: Bearer $API_KEY" \
  -H 'Content-Type: application/json' \
  -d '{"category": "INFO", "severity": "NORMAL", "title": "Hello"}'

# Register a client (an app installation); it reads events with its own key.
CLIENT_KEY=$(curl -s http://localhost:8080/api/v1/admin/clients \
  -H "Authorization: Bearer $ADMIN_TOKEN" -H 'Content-Type: application/json' \
  -d '{"name": "my-laptop"}' | jq -r .clientKey)

# Or publish with the Python command (sdk/python/README.md).
pip install ./sdk/python
SIGNALHUB_URL=http://localhost:8080 SIGNALHUB_API_KEY=$API_KEY \
  signalhub send --category COMPLETED --severity NORMAL --title "Hello again"

# List events, newest first, as that client.
curl -s http://localhost:8080/api/v1/events -H "Authorization: Bearer $CLIENT_KEY"
```

The event model and API are described in
[docs/architecture.md](docs/architecture.md#events), and producers and API
keys in
[docs/architecture.md](docs/architecture.md#producers-and-authentication),
and clients in [docs/architecture.md](docs/architecture.md#clients).

To publish from shells, cron jobs, CI, monitors or coding agents, see the
[integration examples](examples/README.md).

To run it on a home server and reach it from phones and producers over
HTTPS, see [docs/deployment.md](docs/deployment.md).

See [docs/development.md](docs/development.md#backend) for dev mode, tests, and
configuration, and [docs/development.md](docs/development.md#client) for the
client app.

## Development philosophy

- **Trunk-based:** short-lived branches, squash-merged PRs, and a `main` that is
  always releasable.
- **Every commit on `main` is a release:** it is automatically tagged with a
  semantic version derived from its Conventional Commit title.
- **Vertical increments:** each change is complete, tested, and documented on
  its own.
- **Producer-agnostic core:** new needs become generic capabilities.

See [docs/development.md](docs/development.md) for the workflow and release
rules, and [CLAUDE.md](CLAUDE.md) for the rules that apply to all contributors,
human or agent.

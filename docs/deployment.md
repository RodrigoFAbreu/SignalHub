# Deployment

How to run SignalHub unattended on a small home server, such as a Raspberry
Pi 5 with a 64-bit OS, and reach it from phones and producers on other
machines. Everything here is portable: any x86-64 or ARM64 host with Docker
and Docker Compose works the same way.

Each release has everything a deployment needs: its backend image,
published for x86-64 and ARM64, and its deployment files, which run that
image. Nothing is built on the host. The Compose stack, backups and
resources are described in [development.md](development.md#docker-compose)
and [architecture.md](architecture.md#operations); this page adds
installing and upgrading from a release, TLS, network exposure, the
handling of secrets and health monitoring.

## Topology

```
phone, producers ──HTTPS :443──▶ proxy (Caddy) ──/api/ only──▶ backend :8080 ──▶ PostgreSQL
                    HTTP :80 ──▶ redirect to HTTPS, certificate challenges

operator on the host ──http://localhost:8080──▶ backend (management API, health, metrics)
```

- **proxy** terminates TLS and forwards only the product API (`/api/`) to
  the backend. It is [Caddy](https://caddyserver.com/), which obtains and
  renews certificates itself, from the `proxy` profile of `compose.yaml`
  and configured by `proxy/Caddyfile`.
- **backend** publishes its plain-HTTP port on `127.0.0.1` only, for the
  operator on the host.
- **PostgreSQL** publishes no port; only the backend reaches it, over the
  Compose network.

## Setup

1. Install Docker Engine and the Compose plugin (on Raspberry Pi OS, the
   official Docker packages for Debian `arm64`).
2. Get the release's [deployment files](#deployment-files) into the
   directory SignalHub will run from, check them, and unpack them:

   ```sh
   version=1.2.3
   mkdir ~/signalhub && cd ~/signalhub
   curl --fail --location --remote-name-all \
     "https://github.com/RodrigoFAbreu/SignalHub/releases/download/v$version/signalhub-$version-deployment.tar.gz" \
     "https://github.com/RodrigoFAbreu/SignalHub/releases/download/v$version/SHA256SUMS"
   sha256sum --check --ignore-missing SHA256SUMS
   tar --extract --file "signalhub-$version-deployment.tar.gz"
   ```

   Every other command on this page runs in this directory.
3. Choose how clients will trust the certificate (see
   [Certificates](#certificates)): a domain name with a Let's Encrypt
   certificate, or Caddy's own CA.
4. Create `.env` from the example, readable only by you, and fill it in:

   ```sh
   cp .env.example .env
   chmod 600 .env
   ```

   ```sh
   SIGNALHUB_DB_PASSWORD=...                  # openssl rand -hex 24
   SIGNALHUB_ADMIN_TOKEN=...                  # openssl rand -hex 32, see Secrets
   COMPOSE_PROFILES=proxy
   SIGNALHUB_DOMAIN=signalhub.example.com
   SIGNALHUB_TLS=you@example.com              # or: internal
   ```

   `COMPOSE_PROFILES=proxy` in `.env` makes every `docker compose` command
   include the proxy, so there is nothing to remember on restarts.
5. Start the stack, which pulls the release's images, and check it from
   another machine:

   ```sh
   docker compose up --wait
   curl https://signalhub.example.com/api/v1/events   # 401: the API answers, over TLS
   ```

6. Set up each phone. Install the app (see
   [client/README.md](../client/README.md#install-a-release)), then pair
   it with a pairing code, scanned in the app's **Scan pairing code** within
   10 minutes. The simplest way to make one is the
   [admin page](architecture.md#the-admin-page), on the host only: from
   your computer, forward its port over SSH and open it in a browser:

   ```sh
   ssh -L 8080:localhost:8080 you@signalhub-host   # keep it open
   # then open http://localhost:8080/admin/ and enter the admin token
   ```

   Under **Connect a device** it shows the code as a QR code until it is
   used or expires, and copies it as an image or a link to send to whoever
   should connect a device; choose yourself (the user **Owner**, an admin,
   which you can rename) for your own phone. Once the phone has used the
   code, the page names it and is ready for the next one. The page also lists
   every device with its user, to rename it, revoke it, and delete it once
   revoked. Its **Users** section invites other people on this server: a name
   and a role (basic, mod or admin), then a pairing code for their device,
   and each of them receives only the events of the producers they are
   subscribed to (see [Users, roles and
   subscriptions](architecture.md#users-roles-and-subscriptions)). Its
   **Producers** section registers the producers that publish to you, shows
   each new key once to copy into the producer, and issues and revokes keys,
   disables and enables producers, and shows when each last published; its
   **Events** section sends a test event as a producer, to check that the
   phone gets the push, and deletes it afterwards. On the host
   itself, a terminal does the same (see
   [Pairing a device](development.md#pairing-a-device)):

   ```sh
   ADMIN_TOKEN=$(sed -n 's/^SIGNALHUB_ADMIN_TOKEN=//p' .env)
   uri=$(curl -s http://localhost:8080/api/v1/admin/pairings \
     -H "Authorization: Bearer $ADMIN_TOKEN" \
     -H 'Content-Type: application/json' \
     -d '{"name": "Pixel 8"}' | jq -r .uri)
   qrencode -t ansiutf8 "$uri"
   ```

   The phone becomes a client of its own, listed, revoked and deleted through the
   management API, and your other devices get a push saying it was paired. The URI names `https://` and `SIGNALHUB_DOMAIN`, or
   `SIGNALHUB_PUBLIC_URL` if set; the app says so if it cannot reach it.
   Setting a phone up by hand still works: register a client
   (`POST /api/v1/admin/clients`, see
   [development.md](development.md#clients)) and enter the server address
   and its client key under **Or set up by hand**.

All three services restart automatically (`restart: unless-stopped`),
also after the host reboots, as long as the Docker service starts at boot
(the default for the Docker packages).

## Certificates

`SIGNALHUB_TLS` chooses where the certificate for `SIGNALHUB_DOMAIN` comes
from. The proxy does not start without both settings.

- **An email address: Let's Encrypt.** A publicly trusted certificate,
  which every client trusts without setup, renewed automatically; the
  address receives Let's Encrypt's notices. Needs a domain name that
  resolves to the host's public address, and ports 80 and 443 reachable from
  the internet (forwarded by the home router), because Let's Encrypt checks
  the domain over them. This is the choice for the Android and iOS app,
  which accept only publicly trusted certificates.
- **`internal`: Caddy's own CA.** Caddy creates a private CA and issues the
  certificate itself, with no internet access, for any name, including one
  that only resolves on the home network or a VPN. Clients must trust the
  CA's root certificate, which is in the proxy's data volume:

  ```sh
  docker compose exec proxy cat /data/caddy/pki/authorities/local/root.crt > signalhub-ca.crt
  curl --cacert signalhub-ca.crt https://signalhub.home.arpa/api/v1/events
  ```

  Suited to producers (scripts, `curl --cacert`, the Python command with
  `SSL_CERT_FILE=signalhub-ca.crt`); the app does not accept user-installed
  CAs.

The `proxy-data` volume holds the certificates, their private keys and the
internal CA. It survives restarts and upgrades; if it is lost, the proxy
obtains new certificates (and creates a new internal CA, which clients must
trust again). Keep it out of reach like the database.

To serve on other ports, or behind a reverse proxy the host already runs,
leave the `proxy` profile off and let that proxy terminate TLS and forward
what `proxy/Caddyfile` forwards: `/api/` except `/api/v1/admin/`, to
`127.0.0.1:8080`, matched on the normalized path.

## Network exposure

What other machines can reach, with the proxy enabled:

| Port | Serves |
|---|---|
| 443 (TCP and UDP for HTTP/3) | `/api/`: publishing, the inbox and read state, the client API (including device management, and creating pairing codes and learning whether they were used, from a device of a mod or an admin, as [its user's role](architecture.md#roles) allows), redeeming a pairing code. Everything else answers `404`. |
| 80 | Redirects to HTTPS; Let's Encrypt's certificate challenges. |

Not reachable from other machines:

- **The management API** (`/api/v1/admin/`): the proxy answers `404`
  however the path is spelled. Manage producers and clients, and create
  pairing codes for new devices, on the host, over SSH, with
  `http://localhost:8080/api/v1/admin/...` (see
  [development.md](development.md#producers-and-api-keys) and
  [Pairing a device](development.md#pairing-a-device)). A pairing's URI names
  `https://` and `SIGNALHUB_DOMAIN`, or `SIGNALHUB_PUBLIC_URL` if set in
  `.env`. Listing events with the admin token still works through the proxy.
- **The admin page** (`/admin/`): lists
  and changes devices and producers, issues producer keys, creates
  pairing codes and browses, sends test events and deletes events, and
  shows how each event's push went to each device, with the admin token,
  like
  the management API, so it is on `127.0.0.1:8080` only too;
  reach it from another computer through SSH (see step 6 of
  [Setup](#setup)).
- **Health, metrics and OpenAPI** (`/q/`): on `127.0.0.1:8080` only, for
  monitoring on the host. They need no credential, so they are never
  exposed.
- **PostgreSQL**: no published port at all.

Every request through the proxy carries a producer API key, a client key or
a one-time pairing code; none of the product API answers without one. On the host,
allow only ports 22 (SSH, from the home network), 80 and 443 in the
firewall. Ports 80 and 443 need to be open to the internet only for Let's
Encrypt, or for clients outside the home network; a VPN is the tighter
alternative for the latter.

## Secrets

SignalHub reads every secret from its environment or a mounted file at
runtime; none is in the repository or the images.

| Secret | Kept in | Notes |
|---|---|---|
| Database password | `.env` (`SIGNALHUB_DB_PASSWORD`) | Set when the database volume is created; changing it later needs `ALTER ROLE` in PostgreSQL too. |
| Admin token | `.env` (`SIGNALHUB_ADMIN_TOKEN`) | Only needed while managing producers and clients. For the tightest setup, set it, `docker compose up --wait`, manage, then empty it and `docker compose up --wait` again; clients keep reading with their own keys. |
| FCM service account key | A file of its own, mounted read-only (see [development.md](development.md#firebase-cloud-messaging)) | Readable only by UID 10001 (the backend's user): `chmod 400 fcm.json && sudo chown 10001 fcm.json`, in this order, since only the owner may change the mode. |
| App's Firebase options (optional) | A file of its own, mounted read-only (see [development.md](development.md#firebase-cloud-messaging)) | Not a secret: every client key can read it at `GET /api/v1/client/push-config`. Never put the service account key here; the backend refuses one. Readable by UID 10001. |
| Producer API keys and client keys | Each producer's and client's own configuration | The server keeps only hashes; revoke and reissue a key through the management API. |
| TLS keys, internal CA | `proxy-data` volume | Managed by Caddy. |

- `.env` is in neither the deployment files nor the repository (it is
  git-ignored there); `chmod 600 .env` keeps other users of the host from
  reading it. Anyone in the `docker` group can read every container's
  environment (`docker inspect`), so the `docker` group is as trusted as
  root.
- Back up `.env` and the FCM key file separately from the database (see
  [Backup and restore](architecture.md#backup-and-restore)), to a place as
  private as the secrets themselves.
- Settings that are not secret (retention, JSON logs, the domain) live in
  the same `.env`, so one file describes the whole deployment. Resource
  limits and the FCM key mount go into a `compose.override.yaml` beside
  `compose.yaml`, which no release replaces (see
  [Resources](architecture.md#resources)).

## Deployment files

Every release after v1.1.0 attaches its deployment files to its GitHub
release, as `signalhub-X.Y.Z-deployment.tar.gz`, with their checksum in
`SHA256SUMS`:

| File | What it is |
|---|---|
| `compose.yaml` | The release's Compose stack. It runs the release's backend image, named by its version and digest, and the PostgreSQL and Caddy images the release was tested with. |
| `.env.example` | Every setting, with its default. |
| `proxy/Caddyfile` | The TLS reverse proxy's configuration. |

The backend image, `ghcr.io/rodrigofabreu/signalhub:X.Y.Z`, is one image
for x86-64 and ARM64; the release notes name it and its digest, and only
exact versions are tagged (no `latest`). It identifies its release and
commit at `/q/info` and at the start of its startup summary (see
[Version](architecture.md#version)):

```sh
curl --silent http://localhost:8080/q/info   # {"signalhub": {"version": "1.2.3", ...}, ...}
```

The files are the repository's own at the release's tag, except that the
repository's `compose.yaml` builds the backend from source, for development
(see [development.md](development.md#docker-compose)). A release up to
v1.1.0, which has no deployment files, runs from a clone of the repository
at its tag with `docker compose up --build --wait`, in place of steps 2 and
5 of [Setup](#setup); such a build reports itself as a development build.

The Android app of a release, `SignalHub-X.Y.Z.apk`, is attached to the
same GitHub release and listed in the same `SHA256SUMS`; phones install and
update it as described in
[client/README.md](../client/README.md#install-a-release). It reads the
push options the backend serves, so give the backend the app's Firebase
options (see [Secrets](#secrets)) for it to receive push.

## Upgrades

Every release is a `vX.Y.Z` tag with notes on GitHub. An upgrade replaces
the deployment files with the new release's and pulls its images; the
backend migrates the database at startup, forward only, applying every
migration between the two releases, so skipping releases works the same
way. CI upgrades a stack of the previous release to deployment files of the
current code, with its data, and rolls it back again, on every change (the
`Backend container (upgrade from the latest release)` job), and does the
same from v0.13.0, skipping every release since (the `Backend container
(upgrade from v0.13.0)` job). v0.13.0 is the oldest release that stores the
events, producer keys, clients, read state and push preferences these jobs
check; upgrading from an older release applies the same migrations but is
not tested.

1. **Read the release notes** of every release since yours. They list the
   pull requests merged; one marked breaking (`!` in its title) has
   migration notes saying what to change: a setting, the API, or the
   PostgreSQL major version (see below).
2. **Back up** the database, as in
   [Backup and restore](architecture.md#backup-and-restore). It is the way
   back if the new release does not work for you.
3. **Get the release's deployment files**, as in step 2 of
   [Setup](#setup), in the same directory, look for new settings, and
   unpack them over the old ones:

   ```sh
   version=1.2.3
   curl --fail --location --remote-name-all \
     "https://github.com/RodrigoFAbreu/SignalHub/releases/download/v$version/signalhub-$version-deployment.tar.gz" \
     "https://github.com/RodrigoFAbreu/SignalHub/releases/download/v$version/SHA256SUMS"
   sha256sum --check --ignore-missing SHA256SUMS
   tar --extract --to-stdout --file "signalhub-$version-deployment.tar.gz" .env.example \
     | diff .env.example -   # settings added or changed
   tar --extract --file "signalhub-$version-deployment.tar.gz"
   ```

   `.env` and `compose.override.yaml` are not in the files, so they stay
   as they are; add new settings to `.env` as needed. Keep the archive of
   the release you upgraded from: [rolling back](#rolling-back) unpacks it
   again.
4. **Pull and restart:**

   ```sh
   docker compose pull
   docker compose up --wait
   docker image prune --force   # removes the images the upgrade replaced
   ```

   This pulls the new backend image while the old one keeps serving, and
   PostgreSQL and Caddy only if the release pins new images, then
   recreates what changed. The backend is unavailable while it restarts
   and migrates, usually well under a minute: producers get connection
   errors (the `signalhub` command exits with status 3, a temporary
   failure) and should retry; pushes that were pending are sent once it is
   back. Nothing that was acknowledged is lost.
5. **Check** that every service is healthy and the startup summary is as
   expected (see [Health monitoring](#health-monitoring)):

   ```sh
   docker compose ps --format '{{.Service}}: {{.Health}}'
   docker compose logs backend | grep 'Configuration:'
   ```

### From a clone of the repository

An install set up from a clone of the repository, as releases up to
v1.1.0 were, moves to deployment files with its next upgrade. Do steps 1
and 2, then make a new directory for the files and bring the settings over:

```sh
mkdir ~/signalhub && cd ~/signalhub        # not the clone's directory
cp ~/SignalHub/.env .                      # the clone's directory
cp ~/SignalHub/compose.override.yaml .     # if there is one
chmod 600 .env
```

Relative paths in `compose.override.yaml`, such as the FCM key file's, now
start from the new directory: make them absolute. Then continue with step
3 in the new directory. Both `compose.yaml`s name the Compose project
`signalhub`, so the new directory runs on the same database and
certificate volumes; the backend image the clone built is replaced by the
release's. Keep the clone for rolling back to the release it ran.

Upgrading in the clone as before (`git checkout` the new tag and
`docker compose up --build --wait`) keeps working, but builds the backend
on the host and reports a development build.

### From a release with the Connect page

Releases up to v2.11.0 answered `/connect/` on the host (the Connect page,
then a redirect to the admin page). It is gone now and answers `404`:
change bookmarks to `/connect/` to `/admin/`, reached the same way (see
[Network exposure](#network-exposure)). Nothing else changes.

### When the backend does not start

If the backend does not become healthy, its log names the cause: a
setting to fix, or a migration that failed. Each migration runs in its own
transaction, so a failed one leaves no partial change behind; the
migrations before it stay applied, so go back by
[rolling back](#rolling-back).

### Rolling back

Migrations only go forward. An older release's code does not know the
schema a newer one migrated to, so the backend refuses to start on such a
database, before changing anything, and its log says so: `The database
was migrated by a newer SignalHub release (migrations 9 are unknown to
this release)`. Releases up to v0.21.0 refuse it with Flyway's message
instead, `Detected applied migration not resolved locally`, and advise
running Flyway's `repair`: never do that, it deletes the newer migrations
from the schema history but leaves their changes in place. To go back,
restore the backup from step 2 with the older release's deployment files:

```sh
tar --extract --file signalhub-1.2.2-deployment.tar.gz   # the release you upgraded from
docker compose down
docker volume rm signalhub_postgres-data   # the upgraded database
docker compose up --wait postgres
docker compose exec -T postgres sh -c \
  'pg_restore --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --no-owner --no-privileges --exit-on-error --single-transaction' \
  < signalhub-2026-09-25.dump
docker compose up --wait
```

To a release up to v1.1.0, which has no deployment files, run the same
commands in the clone it ran from, with `git checkout v1.1.0` in place of
`tar` and `docker compose up --build --wait` last.

Everything published or changed since the backup is gone, as after any
restore.

### A new PostgreSQL major version

`compose.yaml` pins PostgreSQL's major version (18), and a database
volume works only with the major version that created it. A release that
moves to a new major version is marked breaking (`!`) and says so in its
notes: PostgreSQL refuses to start on the old volume, so nothing is lost,
but the stack does not start until the data is moved. The move is a backup
and a restore into a new, empty volume, as in
[Backup and restore](architecture.md#backup-and-restore); CI moves a stack
with data this way on every change that changes the major version (the
`Backend container (upgrade from ...)` jobs).

From PostgreSQL 17 (releases up to v1.7.1) to 18 (v2.0.0 and later):
18 keeps its data in a directory named for its major version, so
`compose.yaml` mounts the volume at `/var/lib/postgresql` instead of
`/var/lib/postgresql/data`. On the volume of 17, PostgreSQL 18 exits at
once with `Error: in 18+, these Docker images are configured to store
database data in a format which is compatible with "pg_ctlcluster"`, and
the backend waits for it. In the install's directory, with the old release
still running:

```sh
backup=signalhub-$(date +%F).dump
docker compose exec -T postgres sh -c \
  'pg_dump --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --format=custom' \
  > "$backup"                                                        # step 2
docker compose exec -T postgres pg_restore --list < "$backup" > /dev/null   # fails if unreadable
docker compose down
tar --extract --file signalhub-2.0.0-deployment.tar.gz               # step 3, the new release
docker compose pull
docker volume rm signalhub_postgres-data                             # the database of 17
docker compose up --wait postgres                                    # an empty database of 18
docker compose exec -T postgres sh -c \
  'pg_restore --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --no-owner --no-privileges --exit-on-error --single-transaction' \
  < "$backup"
docker compose up --wait                                             # the backend migrates as usual
```

Keep the backup until the new release has run to your satisfaction:
after `docker volume rm`, it is the only copy of the data. If `docker
compose up` was run with the new files first, PostgreSQL 18 refused to
start and the volume still holds 17's data; run `docker compose down`,
unpack the old release's files again, start it, and begin again with the
backup.
Rolling back to a release with PostgreSQL 17 is
[rolling back](#rolling-back): its files and the backup, restored into a
new volume the same way. Events published after the backup are gone
either way, so stop producers, or accept losing what they publish during
the move.

### Upgrading to v3.0.0

v3.0.0 adds [users, roles and subscriptions](architecture.md#users-roles-and-subscriptions)
and is marked breaking (`!`) for one reason: the client API no longer changes
a device's admin flag (`POST /api/v1/client/devices/{id}/admin` answers `409`),
because a device is an admin device exactly when its user is an admin.
Producers, the event schema, the Python SDK and the released app keep working.

**What the upgrade does to your data** (`V17`, applied at startup, with no
operator action and nothing lost):

- It creates one user, **Owner**, an admin (rename them on the admin page,
  *Users*), who becomes the user of every existing client and unredeemed
  pairing code, the owner of every producer (kept private, and subscribed to
  each), and has read the events you had read. You see, receive and can do
  exactly what you did before: your phone, your producers and their keys keep
  working, and so do the SDK and the `signalhub` command.
- **Every existing device is now an admin device,** because it belongs to
  the Owner, an admin; before, only the ones you had marked were. If a
  device should not be one (a tablet you lent), revoke it and pair it again
  for a second user with the role *mod* or *basic*.
- The `admin` flags of clients and pairings are replaced by the role of the
  user. The management API's `admin` fields are still accepted so old
  scripts work, but cannot change anything (see
  [Admin devices](architecture.md#admin-devices)). Requests that name no
  user (a client, a pairing or a producer made with the admin token) act for
  the Owner, the oldest admin who is not revoked.
- The Owner's read state is copied from the events' read marks; the admin
  page keeps a read state of its own for the admin token.

To go back to an earlier release, restore the backup from step 2: a release
refuses to start on a database holding a migration it does not have.

CI upgrades a stack of the previous release and one of v0.13.0 to this
release with their data (see [Upgrades](#upgrades)).

### Upgrading to the self-service release

The release after v3.0.0 that adds [self-service for
users](architecture.md#own-producers-from-a-device) is compatible: one
migration (`V18`) adds a flag to producers, applied at startup with no operator
action and nothing lost. Producers that are disabled stay disabled, and count
as disabled by you, so their owners cannot enable them from a device. The new
paths are under `/api/v1/client/`, so the [proxy](#network-exposure) already
forwards them; there is nothing to configure. Going back is by restoring the
backup, as for every migration.

## Health monitoring

What already happens without an operator:

- **Restarts.** Every service restarts when its process exits and after
  the host reboots (`restart: unless-stopped`).
- **Health checks.** The backend image checks readiness
  (`/q/health/ready`) every 10 seconds, and PostgreSQL its own
  `pg_isready`; `docker compose ps` shows each service as `healthy` or
  `unhealthy`. Readiness fails while PostgreSQL is unreachable and
  recovers by itself once it is back, so Docker does not restart an
  unhealthy backend (and a restart would not help).

What is left is noticing when something is wrong. SignalHub cannot report
its own outage, so check it from outside, and alert through a channel that
does not depend on it: cron's mail, or a heartbeat ("dead man's switch")
service that alerts when the checks stop reporting, which also covers the
host itself being down.

- **On the host**, every few minutes from cron: the backend and its
  database, without credentials.

  ```sh
  curl --fail --silent --max-time 10 --output /dev/null http://localhost:8080/q/health/ready
  ```

- **From another machine**, if the proxy is enabled: the whole path
  producers and clients use, including DNS, the certificate and the proxy.
  An API request without a key answers `401` when all of it works:

  ```sh
  test "$(curl --silent --max-time 10 --output /dev/null --write-out '%{http_code}' \
    https://signalhub.example.com/api/v1/events)" = 401
  ```

- **Disk space.** The database only grows unless a
  [retention](architecture.md#retention) period is set (unwanted events,
  such as tests, can also be
  [deleted](architecture.md#deleting-events) on the admin page); check the free
  space on the host (`df -h /var/lib/docker`) and the database size (see
  [Resources](architecture.md#resources)).
- **At a glance**, the admin page's **Status** section (`/admin/#status`,
  on the host, see [Network exposure](#network-exposure)) answers "is
  SignalHub working?" on one screen: the release and commit, health and
  each check, whether push is configured and apps are given push options,
  pushes waiting and retrying, retries given up since the backend
  started, devices whose last push failed, the retention period and when
  the most recent event arrived, marking what needs attention (see
  [the admin page](architecture.md#the-admin-page)). It is for looking,
  not alerting: it shows only what is true when it is read.
- **Delivery**, with a metrics scraper (see
  [Metrics](architecture.md#metrics)): a `signalhub_push_dispatch_pending`
  that keeps growing means dispatch is stuck; a rising
  `signalhub_push_deliveries_total{result="transient_failure"}` or
  `signalhub_push_retries_abandoned_total` means the push provider is
  unreachable. To check a phone end to end, send a
  [test event](architecture.md#test-events) from the admin page's
  **Events** section and delete it once it has arrived. When a phone did
  not ping for an event, open the event there: its **Deliveries** say, per
  device, whether the push was delivered to the push service, filtered out
  by the device's preferences (and which), not sent for want of a push
  target, or failed and why (see
  [Delivery records](architecture.md#delivery-records)).
- **Logs.** Warnings and errors, such as failed pushes, are in
  `docker compose logs backend`; see [Logs](architecture.md#logs).

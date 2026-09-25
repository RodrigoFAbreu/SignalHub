# Deployment

How to run SignalHub unattended on a small home server, such as a Raspberry
Pi 5 with a 64-bit OS, and reach it from phones and producers on other
machines. Everything here is portable: any x86-64 or ARM64 host with Docker
and Docker Compose works the same way.

The Compose stack, backups and resources are described in
[development.md](development.md#docker-compose) and
[architecture.md](architecture.md#operations); this page adds TLS, network
exposure and the handling of secrets.

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
   official Docker packages for Debian `arm64`), and clone the repository
   at a release tag.
2. Choose how clients will trust the certificate (see
   [Certificates](#certificates)): a domain name with a Let's Encrypt
   certificate, or Caddy's own CA.
3. Create `.env` from the example, readable only by you, and fill it in:

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
4. Start the stack and check it from another machine:

   ```sh
   docker compose up --build --wait
   curl https://signalhub.example.com/api/v1/events   # 401: the API answers, over TLS
   ```

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
| 443 (TCP and UDP for HTTP/3) | `/api/`: publishing, the inbox and read state, the client API. Everything else answers `404`. |
| 80 | Redirects to HTTPS; Let's Encrypt's certificate challenges. |

Not reachable from other machines:

- **The management API** (`/api/v1/admin/`): the proxy answers `404`
  however the path is spelled. Manage producers and clients on the host,
  over SSH, with `http://localhost:8080/api/v1/admin/...` (see
  [development.md](development.md#producers-and-api-keys)). Listing events
  with the admin token still works through the proxy.
- **Health, metrics and OpenAPI** (`/q/`): on `127.0.0.1:8080` only, for
  monitoring on the host. They need no credential, so they are never
  exposed.
- **PostgreSQL**: no published port at all.

Every request through the proxy carries a producer API key or a client key,
with one exception: `GET /api/v1/events/{id}` needs only the event's
unguessable ID (see
[Security limitations](architecture.md#security-limitations)). On the host,
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
| FCM service account key | A file outside the repository, mounted read-only (see [development.md](development.md#firebase-cloud-messaging)) | Owned by you, readable by UID 10001 (the backend's user): `sudo chown 10001 fcm.json && chmod 400 fcm.json`. |
| Producer API keys and client keys | Each producer's and client's own configuration | The server keeps only hashes; revoke and reissue a key through the management API. |
| TLS keys, internal CA | `proxy-data` volume | Managed by Caddy. |

- `.env` is git-ignored; `chmod 600 .env` keeps other users of the host from
  reading it. Anyone in the `docker` group can read every container's
  environment (`docker inspect`), so the `docker` group is as trusted as
  root.
- Back up `.env` and the FCM key file separately from the database (see
  [Backup and restore](architecture.md#backup-and-restore)), to a place as
  private as the secrets themselves.
- Settings that are not secret (retention, JSON logs, the domain) live in
  the same `.env`, so one file describes the whole deployment. Resource
  limits and the FCM key mount go into a git-ignored `compose.override.yaml`
  (see [Resources](architecture.md#resources)).

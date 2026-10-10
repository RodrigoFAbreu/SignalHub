"""Shared helpers of the container tests (see README.md in this folder).

The tests drive a running SignalHub stack over HTTP, with the standard library
only, and reach for `docker compose` where a check needs the containers
themselves (restarting a service, a database dump, an image's labels).

Settings come from the environment, so the same tests run in CI and by hand
against a local `docker compose up`:

SIGNALHUB_URL            the backend on the host (default http://localhost:8080)
SIGNALHUB_TEST_ADMIN_TOKEN the operator's token; default: SIGNALHUB_ADMIN_TOKEN in .env of the
                         Compose folder
SIGNALHUB_COMPOSE_DIR    the folder of the stack's compose.yaml and .env
                         (default: the current folder)
SIGNALHUB_PROXY_URL      the TLS reverse proxy (https://localhost); the tests
                         through the proxy are skipped without it
SIGNALHUB_PROXY_CA       a file with the proxy's CA certificate; default: Caddy's
                         own, read from the proxy container
"""

from __future__ import annotations

import functools
import http.client
import json
import os
import ssl
import subprocess
import time
import unittest
import uuid
from collections.abc import Callable, Mapping
from pathlib import Path
from typing import Any
from urllib.parse import urlencode, urlsplit

JSON = "application/json"


def required(name: str) -> str:
    """A setting the stack's workflow provides; the test is skipped without it."""
    value = os.environ.get(name)
    if not value:
        raise unittest.SkipTest(f"set {name}, see the docstring of this test module")
    return value


def mask(value: str) -> str:
    """Hides a secret in GitHub Actions logs, should a failure ever print it."""
    if os.environ.get("GITHUB_ACTIONS"):
        print(f"::add-mask::{value}", flush=True)
    return value


def unique(name: str) -> str:
    """A name no earlier run of the tests on the same stack used."""
    return f"{name}-{uuid.uuid4().hex[:8]}"


class Response:
    def __init__(
        self, method: str, url: str, status: int, headers: Any, body: bytes
    ) -> None:
        self.method = method
        self.url = url
        self.status = status
        self.headers = headers
        self.body = body

    @property
    def text(self) -> str:
        return self.body.decode("utf-8", errors="replace")

    def json(self) -> Any:
        return json.loads(self.body)

    def header(self, name: str) -> str | None:
        return self.headers.get(name)

    def __repr__(self) -> str:
        return f"{self.method} {self.url} -> {self.status}"


class Endpoint:
    """One address of the stack: the backend on the host, or the proxy."""

    def __init__(self, base_url: str, cafile: str | None = None) -> None:
        self.base_url = base_url.rstrip("/")
        self._parts = urlsplit(self.base_url)
        self._cafile = cafile

    def request(
        self,
        method: str,
        path: str,
        *,
        token: str | None = None,
        cookie: str | None = None,
        headers: Mapping[str, str] | None = None,
        body: Any = None,
        query: Mapping[str, Any] | None = None,
        timeout: float = 30,
    ) -> Response:
        """Sends a request without following redirects or normalizing the path.

        `body` is sent as JSON. `path` is sent exactly as given, so a test can
        spell it the way an attacker might.
        """
        target = path + (f"?{urlencode(query)}" if query else "")
        sent = dict(headers or {})
        if token is not None:
            sent["Authorization"] = f"Bearer {token}"
        if cookie is not None:
            sent["Cookie"] = cookie
        data = None
        if body is not None:
            data = json.dumps(body).encode("utf-8")
            sent["Content-Type"] = JSON
        connection: http.client.HTTPConnection
        if self._parts.scheme == "https":
            context = ssl.create_default_context(cafile=self._cafile)
            connection = http.client.HTTPSConnection(
                self._parts.hostname or "",
                self._parts.port,
                context=context,
                timeout=timeout,
            )
        else:
            connection = http.client.HTTPConnection(
                self._parts.hostname or "", self._parts.port, timeout=timeout
            )
        try:
            connection.request(method, target, body=data, headers=sent)
            answer = connection.getresponse()
            return Response(
                method, self.base_url + target, answer.status, answer.msg, answer.read()
            )
        finally:
            connection.close()

    def get(self, path: str, **kwargs: Any) -> Response:
        return self.request("GET", path, **kwargs)

    def post(self, path: str, **kwargs: Any) -> Response:
        return self.request("POST", path, **kwargs)

    def put(self, path: str, **kwargs: Any) -> Response:
        return self.request("PUT", path, **kwargs)

    def patch(self, path: str, **kwargs: Any) -> Response:
        return self.request("PATCH", path, **kwargs)

    def delete(self, path: str, **kwargs: Any) -> Response:
        return self.request("DELETE", path, **kwargs)


def compose_dir() -> Path:
    return Path(os.environ.get("SIGNALHUB_COMPOSE_DIR") or Path.cwd()).resolve()


def run(
    *command: str,
    cwd: Path | None = None,
    env: Mapping[str, str] | None = None,
    input: str | bytes | None = None,
    check: bool = True,
    timeout: float = 600,
) -> subprocess.CompletedProcess[Any]:
    """Runs a command and captures its output; a failure shows what it printed."""
    if isinstance(input, str):
        input = input.encode("utf-8")
    result = subprocess.run(
        command,
        cwd=cwd or compose_dir(),
        env={**os.environ, **(env or {})},
        input=input,
        capture_output=True,
        check=False,
        timeout=timeout,
    )
    if check and result.returncode != 0:
        raise AssertionError(
            f"{' '.join(command)} exited with {result.returncode}\n"
            f"{result.stdout.decode(errors='replace')}\n{result.stderr.decode(errors='replace')}"
        )
    return result


def text(result: subprocess.CompletedProcess[Any]) -> str:
    return result.stdout.decode("utf-8", errors="replace")


def compose(*args: str, **kwargs: Any) -> subprocess.CompletedProcess[Any]:
    return run("docker", "compose", *args, **kwargs)


def container(service: str) -> str:
    """The ID of a service's container."""
    found = text(compose("ps", "--quiet", service)).strip()
    if not found:
        raise AssertionError(f"the {service} service has no container")
    return found


def inspect(target: str, template: str) -> str:
    """`docker inspect --format` of a container, or an image by its ID."""
    return text(run("docker", "inspect", "--format", template, target)).strip()


def postgres_sql(statement: str) -> str:
    """Runs a statement in the stack's database and returns its rows, unaligned."""
    return text(
        compose(
            "exec",
            "-T",
            "postgres",
            "sh",
            "-c",
            'psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set ON_ERROR_STOP=1'
            " --tuples-only --no-align",
            input=statement,
        )
    ).strip()


def up(
    *services: str, timeout: int = 180, env: Mapping[str, str] | None = None
) -> None:
    """Starts or recreates what changed and waits until it is healthy."""
    compose("up", "--wait", "--wait-timeout", str(timeout), *services, env=env)


def wait_until(
    condition: Callable[[], bool], what: str, timeout: float = 60, interval: float = 1
) -> None:
    """Polls rather than sleeping for a fixed time."""
    deadline = time.monotonic() + timeout
    while True:
        try:
            if condition():
                return
        except (OSError, http.client.HTTPException):
            pass
        if time.monotonic() >= deadline:
            raise AssertionError(f"timed out after {timeout:g}s waiting for {what}")
        time.sleep(interval)


@functools.cache
def env_file_value(name: str) -> str | None:
    path = compose_dir() / ".env"
    if not path.exists():
        return None
    for line in path.read_text().splitlines():
        if line.startswith(f"{name}="):
            return line.split("=", 1)[1]
    return None


@functools.cache
def host() -> Endpoint:
    return Endpoint(os.environ.get("SIGNALHUB_URL", "http://localhost:8080"))


@functools.cache
def admin_token() -> str:
    token = os.environ.get("SIGNALHUB_TEST_ADMIN_TOKEN") or env_file_value(
        "SIGNALHUB_ADMIN_TOKEN"
    )
    if not token:
        raise unittest.SkipTest(
            "set SIGNALHUB_TEST_ADMIN_TOKEN (or SIGNALHUB_ADMIN_TOKEN in .env of the Compose folder)"
        )
    return mask(token)


@functools.cache
def proxy_ca_file() -> str:
    given = os.environ.get("SIGNALHUB_PROXY_CA")
    if given:
        return given
    certificate = compose(
        "exec", "-T", "proxy", "cat", "/data/caddy/pki/authorities/local/root.crt"
    )
    path = (
        Path(os.environ.get("RUNNER_TEMP") or "/tmp")
        / f"signalhub-proxy-ca-{os.getpid()}.crt"
    )
    path.write_bytes(certificate.stdout)
    return str(path)


@functools.cache
def proxy() -> Endpoint:
    url = os.environ.get("SIGNALHUB_PROXY_URL")
    if not url:
        raise unittest.SkipTest(
            "set SIGNALHUB_PROXY_URL (the stack's proxy profile) for this test"
        )
    return Endpoint(url, proxy_ca_file())


def admin(
    method: str, path: str, *, endpoint: Endpoint | None = None, **kwargs: Any
) -> Response:
    """A management request with the operator's token (on the host, by default)."""
    return (endpoint or host()).request(method, path, token=admin_token(), **kwargs)


def created(response: Response) -> Any:
    """The JSON of a response that must have created something."""
    if response.status not in (200, 201):
        raise AssertionError(f"{response}: {response.text}")
    return response.json()


def create_producer(name: str, **fields: Any) -> dict[str, Any]:
    """Registers a producer; the answer holds its key, shown once."""
    answer = created(
        admin("POST", "/api/v1/admin/producers", body={"name": unique(name), **fields})
    )
    mask(answer["apiKey"])
    return answer


def create_client(name: str, **fields: Any) -> dict[str, Any]:
    """Registers a device of the owner (or of `userId`); the answer holds its key."""
    answer = created(
        admin("POST", "/api/v1/admin/clients", body={"name": unique(name), **fields})
    )
    mask(answer["clientKey"])
    return answer


def create_user(name: str, role: str = "BASIC") -> dict[str, Any]:
    return created(
        admin("POST", "/api/v1/admin/users", body={"name": unique(name), "role": role})
    )


def event_fields(title: str, **fields: Any) -> dict[str, Any]:
    return {"category": "INFO", "severity": "LOW", "title": title, **fields}


def publish(
    api_key: str, title: str, *, endpoint: Endpoint | None = None, **fields: Any
) -> Response:
    return (endpoint or host()).post(
        "/api/v1/events", token=api_key, body=event_fields(title, **fields)
    )


def published_id(api_key: str, title: str, **fields: Any) -> str:
    """Publishes an event that must be accepted and returns its ID."""
    return created(publish(api_key, title, **fields))["id"]


def signalhub_command(
    *args: str,
    api_key: str,
    url: str | None = None,
    env: Mapping[str, str] | None = None,
) -> subprocess.CompletedProcess[Any]:
    """Runs the Python package's `signalhub` command against the stack."""
    return run(
        "signalhub",
        *args,
        env={
            "SIGNALHUB_URL": url or host().base_url,
            "SIGNALHUB_API_KEY": api_key,
            **(env or {}),
        },
        check=False,
    )


class StackTestCase(unittest.TestCase):
    """Adds the assertions the tests share."""

    def assertStatus(self, response: Response, expected: int) -> Response:
        self.assertEqual(
            expected, response.status, f"{response}: {response.text[:500]}"
        )
        return response

    def ok(self, response: Response) -> Any:
        """The JSON of a successful response."""
        self.assertTrue(
            200 <= response.status < 300, f"{response}: {response.text[:500]}"
        )
        return response.json() if response.body else None

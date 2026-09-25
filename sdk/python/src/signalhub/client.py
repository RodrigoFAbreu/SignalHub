"""Publishing events to SignalHub over its public HTTP API.

Only the standard library is used, so the package installs anywhere Python
does and adds nothing to a producer's dependencies.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Any, Mapping

URL_ENV = "SIGNALHUB_URL"
API_KEY_ENV = "SIGNALHUB_API_KEY"
API_KEY_FILE_ENV = "SIGNALHUB_API_KEY_FILE"
DEFAULT_TIMEOUT = 10.0
USER_AGENT = "signalhub-python"

EVENTS_PATH = "/api/v1/events"


class _NoRedirects(urllib.request.HTTPRedirectHandler):
    # Following a redirect would send the API key to wherever it points, and
    # urllib turns a redirected POST into a GET. A redirect is reported instead.
    def redirect_request(self, *args: Any, **kwargs: Any) -> None:
        return None


_OPENER = urllib.request.build_opener(_NoRedirects)


class Category(str, Enum):
    """What an event means for the owner (docs/architecture.md, "Events")."""

    ACTION_REQUIRED = "ACTION_REQUIRED"
    BLOCKED = "BLOCKED"
    COMPLETED = "COMPLETED"
    INFO = "INFO"


class Severity(str, Enum):
    """How urgently the owner should notice an event."""

    LOW = "LOW"
    NORMAL = "NORMAL"
    HIGH = "HIGH"
    CRITICAL = "CRITICAL"


class SignalHubError(Exception):
    """Base class for every error this package raises."""


class ConfigurationError(SignalHubError):
    """The server address or API key is missing or unusable."""


class RequestError(SignalHubError):
    """SignalHub answered with an error status."""

    def __init__(self, status: int, message: str) -> None:
        super().__init__(message)
        self.status = status

    @property
    def temporary(self) -> bool:
        """Whether sending the same request again later may succeed."""
        return self.status == 429 or self.status >= 500


class AuthenticationError(RequestError):
    """The API key is missing, unknown, revoked, or its producer is disabled."""


@dataclass(frozen=True)
class Violation:
    field: str
    message: str

    def __str__(self) -> str:
        return f"{self.field}: {self.message}" if self.field else self.message


class ValidationError(RequestError):
    """SignalHub rejected the event; `violations` says which fields and why."""

    def __init__(self, status: int, message: str, violations: list[Violation]) -> None:
        super().__init__(status, message)
        self.violations = violations

    def __str__(self) -> str:
        details = "; ".join(str(violation) for violation in self.violations)
        return f"{self.args[0]}: {details}" if details else self.args[0]


class UnreachableError(SignalHubError):
    """SignalHub could not be reached, or did not answer in time."""


def read_api_key_file(path: str) -> str:
    try:
        with open(path, encoding="utf-8") as file:
            key = file.read().strip()
    except OSError as error:
        raise ConfigurationError(
            f"cannot read the API key file {path}: {error.strerror}"
        ) from error
    if not key:
        raise ConfigurationError(f"the API key file {path} is empty")
    return key


class SignalHub:
    """A producer's connection to one SignalHub server.

    `url` is the server's base address (for example `https://signalhub.example`,
    with any path prefix of a reverse proxy); `api_key` is the producer's key.
    """

    def __init__(
        self, url: str, api_key: str, *, timeout: float = DEFAULT_TIMEOUT
    ) -> None:
        if not url.startswith(("http://", "https://")):
            raise ConfigurationError(
                f"the SignalHub URL must start with http:// or https://, got {url!r}"
            )
        if not api_key:
            raise ConfigurationError("the API key is empty")
        if any(char.isspace() or not char.isprintable() for char in api_key):
            raise ConfigurationError(
                "the API key contains spaces or control characters"
            )
        self._events_url = url.rstrip("/") + EVENTS_PATH
        self._api_key = api_key
        self._timeout = timeout

    @classmethod
    def from_env(cls, *, timeout: float = DEFAULT_TIMEOUT) -> SignalHub:
        """Reads SIGNALHUB_URL and SIGNALHUB_API_KEY (or SIGNALHUB_API_KEY_FILE)."""
        url = os.environ.get(URL_ENV, "")
        if not url:
            raise ConfigurationError(f"{URL_ENV} is not set")
        return cls(url, api_key_from_env(), timeout=timeout)

    def publish(
        self,
        *,
        category: Category | str,
        severity: Severity | str,
        title: str,
        message: str | None = None,
        context: str | None = None,
        metadata: dict[str, Any] | None = None,
        occurred_at: datetime | str | None = None,
    ) -> dict[str, Any]:
        """Publishes one event and returns it as SignalHub stored it.

        The returned event carries the server's `id`, `producer` and
        `createdAt`. Category and severity are case-insensitive, and `-`
        stands for `_` (`action-required`). Values unknown to this package
        are sent as they are, so the server stays the judge of what it accepts.
        """
        body: dict[str, Any] = {
            "category": _enum_value(category),
            "severity": _enum_value(severity),
            "title": title,
        }
        if message is not None:
            body["message"] = message
        if context is not None:
            body["context"] = context
        if metadata is not None:
            body["metadata"] = metadata
        if occurred_at is not None:
            body["occurredAt"] = _timestamp(occurred_at)
        return self._post(body)

    def _post(self, body: dict[str, Any]) -> dict[str, Any]:
        request = urllib.request.Request(
            self._events_url,
            data=json.dumps(body).encode("utf-8"),
            method="POST",
            headers={
                "Authorization": f"Bearer {self._api_key}",
                "Content-Type": "application/json",
                "Accept": "application/json",
                "User-Agent": USER_AGENT,
            },
        )
        try:
            with _OPENER.open(request, timeout=self._timeout) as response:
                event = json.load(response)
        except urllib.error.HTTPError as error:
            raise _request_error(error) from None
        except (urllib.error.URLError, TimeoutError, OSError) as error:
            reason = getattr(error, "reason", error)
            raise UnreachableError(
                f"cannot reach SignalHub at {self._events_url}: {reason}"
            ) from error
        except ValueError as error:
            raise SignalHubError(
                f"{self._events_url} did not answer with JSON; is it a SignalHub server?"
            ) from error
        return event


def api_key_from_env(environ: Mapping[str, str] | None = None) -> str:
    """The key in SIGNALHUB_API_KEY, else read from the file SIGNALHUB_API_KEY_FILE names."""
    env = os.environ if environ is None else environ
    key = env.get(API_KEY_ENV, "")
    if key:
        return key
    path = env.get(API_KEY_FILE_ENV, "")
    if path:
        return read_api_key_file(path)
    raise ConfigurationError(f"no API key: set {API_KEY_ENV} or {API_KEY_FILE_ENV}")


def _enum_value(value: Enum | str) -> str:
    if isinstance(value, Enum):
        return str(value.value)
    return value.strip().upper().replace("-", "_")


def _timestamp(value: datetime | str) -> str:
    if isinstance(value, str):
        return value
    # SignalHub rejects timestamps without an offset, as they are ambiguous.
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError("occurred_at must be timezone-aware")
    return value.isoformat()


def _request_error(error: urllib.error.HTTPError) -> RequestError:
    status = error.code
    try:
        body = json.load(error)
    except (ValueError, OSError):
        body = None
    if not isinstance(body, dict):
        body = {}
    title = body.get("title")
    message = f"{status} {title if isinstance(title, str) else error.reason}"
    if status == 401:
        return AuthenticationError(
            status,
            f"{message}: the API key is invalid or revoked, or its producer is disabled",
        )
    if 400 <= status < 500 and status not in (404, 429):
        violations = [
            Violation(str(item.get("field", "")), str(item.get("message", "")))
            for item in body.get("violations") or []
            if isinstance(item, dict)
        ]
        return ValidationError(status, f"{message}: the event was rejected", violations)
    if status == 404:
        message += ": is the URL the SignalHub server's base address?"
    elif 300 <= status < 400:
        location = error.headers.get("Location", "elsewhere")
        message += (
            f": redirected to {location}; use the address it points to as the URL"
        )
    return RequestError(status, message)

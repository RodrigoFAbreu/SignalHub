"""Publishing events to SignalHub over its public HTTP API.

Only the standard library is used, so the package installs anywhere Python
does and adds nothing to a producer's dependencies.
"""

from __future__ import annotations

import json
import os
import re
import time
import unicodedata
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from datetime import datetime
from enum import Enum
from typing import Any

URL_ENV = "SIGNALHUB_URL"
API_KEY_ENV = "SIGNALHUB_API_KEY"
API_KEY_FILE_ENV = "SIGNALHUB_API_KEY_FILE"
DEFAULT_TIMEOUT = 10.0
USER_AGENT = "signalhub-python"

EVENTS_PATH = "/api/v1/events"
IDEMPOTENCY_KEY_HEADER = "Idempotency-Key"

# The longest the server holds a read of an answer, and how long past it the
# socket waits before giving up on the answer to a held read.
MAX_WAIT_SECONDS = 60
WAIT_SOCKET_MARGIN = 15.0
# A held read that returns still OPEN well before its wait did not really wait
# (a proxy cut it, or the server is busy); asking again at once would spin.
EARLY_RETURN_SECONDS = 5.0
RETRY_PAUSE_SECONDS = 5.0


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


class QuestionAnsweredError(RequestError):
    """Someone answered the question first; `state` is the question's state, with the answer."""

    def __init__(self, status: int, message: str, state: dict[str, Any]) -> None:
        super().__init__(status, message)
        self.state = state


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


@dataclass(frozen=True)
class Choice:
    """One choice of a question.

    `id` is what an answer carries back. Leave it out (`None`) and the id is
    derived from the label by `derive_choice_ids`.
    """

    id: str | None
    label: str
    description: str | None = None


@dataclass(frozen=True)
class Ask:
    """A question on an event (docs/architecture.md, "Answering an event").

    `text` is `none`, `optional` or `required` typed text; `text_style` is
    `note` or `other`; both, and `multiple`, are sent only when given, so the
    server's defaults apply. `closes_at` is when nobody can answer any more.
    """

    choices: Sequence[Choice] = ()
    multiple: bool | None = None
    text: str | None = None
    text_style: str | None = None
    closes_at: datetime | str | None = None

    def to_json(self) -> dict[str, Any]:
        ids = derive_choice_ids(self.choices)
        document: dict[str, Any] = {
            "choices": [
                {"id": id_, "label": choice.label}
                | (
                    {"description": choice.description}
                    if choice.description is not None
                    else {}
                )
                for id_, choice in zip(ids, self.choices)
            ]
        }
        if self.multiple is not None:
            document["multiple"] = self.multiple
        if self.text is not None:
            document["text"] = _enum_value(self.text)
        if self.text_style is not None:
            document["textStyle"] = _enum_value(self.text_style)
        if self.closes_at is not None:
            document["closesAt"] = _timestamp(self.closes_at, "closes_at")
        return document


_ID_RUN = re.compile(r"[^a-z0-9]+")
_ID_ROOM = 60  # of the server's 64, leaving room for a "-2" ... "-10" suffix


def derive_choice_ids(choices: Sequence[Choice]) -> list[str]:
    """The id of each choice: the one it has, else one derived from its label.

    Derived: lower-case, accents removed, every run of characters other than
    `a`-`z` and `0`-`9` becomes `-`, trimmed of `-` and cut to 60 characters;
    `choice-N` (its 1-based position) when nothing is left; `-2`, `-3` and so
    on added on a collision. The same rule is used by the command and the
    admin page.
    """
    ids: list[str] = []
    for position, choice in enumerate(choices, start=1):
        if choice.id:
            ids.append(choice.id)
            continue
        ascii_label = (
            unicodedata.normalize("NFKD", choice.label)
            .encode("ascii", "ignore")
            .decode("ascii")
            .lower()
        )
        base = _ID_RUN.sub("-", ascii_label).strip("-")[:_ID_ROOM].strip("-")
        candidate = base or f"choice-{position}"
        suffix = 2
        while candidate in ids or candidate in {c.id for c in choices if c.id}:
            candidate = f"{base or f'choice-{position}'}-{suffix}"
            suffix += 1
        ids.append(candidate)
    return ids


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
        link: str | None = None,
        occurred_at: datetime | str | None = None,
        idempotency_key: str | None = None,
        ask: Ask | Mapping[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Publishes one event and returns it as SignalHub stored it.

        The returned event carries the server's `id`, `producer` and
        `createdAt`. Category and severity are case-insensitive, and `-`
        stands for `_` (`action-required`). Values unknown to this package
        are sent as they are, so the server stays the judge of what it accepts.

        `link` is one absolute `http` or `https` URL the owner can open from
        the event, such as the page of a failed run; SignalHub stores it as
        sent and never fetches it. Servers older than v2.3.0 reject it.

        With an `idempotency_key` (1 to 200 visible ASCII characters, unique
        per event, such as a UUID or a run ID), publishing the same event
        again returns the event already stored instead of storing another, so
        the call can be repeated after a temporary failure. The key is sent as
        the `Idempotency-Key` header.

        With an `ask` (an `Ask`, or the JSON object itself) the event is also
        a question: the people allowed to answer it do so in their client, and
        `wait_answer` reads the answer. Servers older than the release that
        added questions reject it.
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
        if link is not None:
            body["link"] = link
        if occurred_at is not None:
            body["occurredAt"] = _timestamp(occurred_at)
        if ask is not None:
            body["ask"] = ask.to_json() if isinstance(ask, Ask) else dict(ask)
        headers = {}
        if idempotency_key is not None:
            headers[IDEMPOTENCY_KEY_HEADER] = _idempotency_key(idempotency_key)
        return self._request("POST", self._events_url, body, headers, self._timeout)

    def close_question(self, event_id: str, note: str | None = None) -> dict[str, Any]:
        """Closes the question of the producer's event without an answer.

        For a question answered somewhere else. Returns the question's state
        (`state` `CLOSED`, also when it had closed already, by the producer or
        by its time). Raises `QuestionAnsweredError`, whose `state` holds the
        answer, if someone answered in SignalHub first.
        """
        body = {"note": note} if note is not None else None
        return self._request(
            "POST", self._answer_url(event_id) + "/close", body, {}, self._timeout
        )

    def read_answer(self, event_id: str, *, wait: int = 0) -> dict[str, Any]:
        """The question's state now, or held up to `wait` seconds (0 to 60).

        `state` is `OPEN`, `ANSWERED` (with `answer`) or `CLOSED` (with
        `closedBy`, `closedAt` and `closeNote`).
        """
        if not 0 <= wait <= MAX_WAIT_SECONDS:
            raise ValueError(f"wait must be 0 to {MAX_WAIT_SECONDS} seconds")
        url = self._answer_url(event_id) + (f"?wait={wait}" if wait else "")
        timeout = wait + WAIT_SOCKET_MARGIN if wait else self._timeout
        return self._request("GET", url, None, {}, timeout)

    def wait_answer(
        self,
        event_id: str,
        timeout: float | None = None,
        *,
        sleep: Callable[[float], None] = time.sleep,
        clock: Callable[[], float] = time.monotonic,
    ) -> dict[str, Any]:
        """Waits until the question is answered or closed, and returns its state.

        Repeats 60 second held reads until the state leaves `OPEN` or `timeout`
        seconds pass (`None`: no limit); on timeout it returns the last state,
        still `OPEN`. A read that comes back `OPEN` in under 5 seconds, well
        before its wait, is followed by a pause of 5 seconds; a temporary
        error (SignalHub unreachable, a `502`, `503` or `429`, a restart during
        an upgrade) is retried after 5 seconds until `timeout`, and raised if
        that was all there was. A `404` (a deleted event, or not this
        producer's) is raised at once.
        """
        deadline = None if timeout is None else clock() + timeout
        state: dict[str, Any] | None = None
        while True:
            remaining = None if deadline is None else deadline - clock()
            if remaining is not None and remaining <= 0:
                break
            wait = MAX_WAIT_SECONDS
            if remaining is not None:
                wait = max(1, min(MAX_WAIT_SECONDS, int(remaining)))
            started = clock()
            try:
                state = self.read_answer(event_id, wait=wait)
            except UnreachableError as error:
                failure: SignalHubError = error
            except RequestError as error:
                if not error.temporary:
                    raise
                failure = error
            else:
                if state.get("state") != "OPEN":
                    return state
                if clock() - started < min(wait, EARLY_RETURN_SECONDS):
                    _pause(sleep, deadline, clock)
                continue
            if deadline is None or clock() + RETRY_PAUSE_SECONDS < deadline:
                sleep(RETRY_PAUSE_SECONDS)
                continue
            if state is None:
                raise failure
            break
        return state if state is not None else {"state": "OPEN"}

    def _answer_url(self, event_id: str) -> str:
        return f"{self._events_url}/{urllib.parse.quote(event_id, safe='')}/answer"

    def _request(
        self,
        method: str,
        url: str,
        body: dict[str, Any] | None,
        headers: dict[str, str],
        timeout: float,
    ) -> dict[str, Any]:
        data = json.dumps(body).encode("utf-8") if body is not None else None
        request = urllib.request.Request(
            url,
            data=data,
            method=method,
            headers={
                "Authorization": f"Bearer {self._api_key}",
                **({"Content-Type": "application/json"} if data is not None else {}),
                "Accept": "application/json",
                "User-Agent": USER_AGENT,
                **headers,
            },
        )
        try:
            with _OPENER.open(request, timeout=timeout) as response:
                document = json.load(response)
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
        return document


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


def _pause(
    sleep: Callable[[float], None], deadline: float | None, clock: Callable[[], float]
) -> None:
    left = RETRY_PAUSE_SECONDS if deadline is None else deadline - clock()
    if left > 0:
        sleep(min(RETRY_PAUSE_SECONDS, left))


def _timestamp(value: datetime | str, name: str = "occurred_at") -> str:
    if isinstance(value, str):
        return value
    # SignalHub rejects timestamps without an offset, as they are ambiguous.
    if value.tzinfo is None or value.utcoffset() is None:
        raise ValueError(f"{name} must be timezone-aware")
    return value.isoformat()


def _idempotency_key(key: str) -> str:
    # Only what cannot travel in a header is refused here; the server checks
    # the rest (spaces, length).
    if not key or not key.isascii() or not key.isprintable():
        raise ValueError("idempotency_key must be 1 to 200 visible ASCII characters")
    return key


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
    question = body.get("question")
    if status == 409 and isinstance(question, dict):
        return QuestionAnsweredError(
            status, f"{message}: someone answered the question first", question
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

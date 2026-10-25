"""The `signalhub` command: publish events from shells, scripts and CI jobs.

Exit status: 0 published (or answered, or closed), 1 rejected (an invalid event
or API key, or an event that is gone; sending it again will not help), 2 usage
or configuration error, 3 temporary failure (SignalHub unreachable, overloaded
or failing; sending it again later may help). `wait-answer` also exits 5 when
the question was closed, 6 when its own timeout passed, and `close-question`
7 when someone answered first.
"""

from __future__ import annotations

import argparse
import importlib.metadata
import json
import os
import re
import sys
from collections.abc import Mapping
from datetime import datetime, timedelta, timezone
from typing import Any, NoReturn, TextIO

from signalhub.client import (
    API_KEY_ENV,
    API_KEY_FILE_ENV,
    DEFAULT_TIMEOUT,
    URL_ENV,
    Ask,
    Category,
    Choice,
    ConfigurationError,
    QuestionAnsweredError,
    RequestError,
    Severity,
    SignalHub,
    SignalHubError,
    UnreachableError,
    api_key_from_env,
    derive_choice_ids,
    read_api_key_file,
)

EXIT_OK = 0
EXIT_REJECTED = 1
EXIT_USAGE = 2
EXIT_TEMPORARY = 3
EXIT_CLOSED = 5
EXIT_WAIT_TIMEOUT = 6
EXIT_ANSWERED_FIRST = 7


def version() -> str:
    """The SignalHub release this package belongs to, from its metadata.

    Only a release's build carries a release version; any other build has the
    placeholder of pyproject.toml, a development version.
    """
    try:
        number = importlib.metadata.version("signalhub")
    except importlib.metadata.PackageNotFoundError:
        return "SignalHub development build"
    if ".dev" in number:
        return "SignalHub development build"
    return f"SignalHub {number}"


class UsageError(SignalHubError):
    """An option value the command cannot use."""


class _Parser(argparse.ArgumentParser):
    def error(self, message: str) -> NoReturn:
        self.print_usage(sys.stderr)
        self.exit(EXIT_USAGE, f"{self.prog}: error: {message}\n")


def _parser() -> argparse.ArgumentParser:
    parser = _Parser(
        prog="signalhub",
        description="Publish events to SignalHub.",
        epilog="Exit status: 0 done, 1 rejected, 2 usage or configuration error, "
        "3 temporary failure (sending again later may help); wait-answer: 5 closed, "
        "6 its timeout passed; close-question: 7 someone answered first.",
    )
    parser.add_argument(
        "--version",
        action="version",
        version=version(),
        help="print the SignalHub release of this command and exit",
    )
    commands = parser.add_subparsers(dest="command", required=True, metavar="COMMAND")
    send = commands.add_parser(
        "send",
        help="publish one event",
        description="Publish one event and print its ID.",
        epilog=f"The server comes from --url or {URL_ENV}, the producer's API key from "
        f"--api-key-file, {API_KEY_ENV} or {API_KEY_FILE_ENV}. There is no option "
        "for the key itself, so it never appears in process lists or shell history.",
    )
    send.add_argument(
        "--category",
        required=True,
        help="one of " + ", ".join(c.value for c in Category) + " (case-insensitive)",
    )
    send.add_argument(
        "--severity",
        required=True,
        help="one of " + ", ".join(s.value for s in Severity) + " (case-insensitive)",
    )
    send.add_argument(
        "--title", required=True, help="short summary, at most 200 characters"
    )
    send.add_argument(
        "--message",
        help="longer text, at most 4000 characters; - reads it from standard input",
    )
    send.add_argument(
        "--context", help="project or context, e.g. a repository, host or job"
    )
    send.add_argument(
        "--metadata",
        metavar="JSON",
        help="producer data as a JSON object, e.g. '{\"run\": 42}'",
    )
    send.add_argument(
        "--meta",
        metavar="KEY=VALUE",
        action="append",
        default=[],
        help="one metadata string value; repeatable, applied over --metadata",
    )
    send.add_argument(
        "--link",
        metavar="URL",
        help="an http or https URL the owner can open from the event, "
        "e.g. the page of a failed run",
    )
    send.add_argument(
        "--occurred-at",
        metavar="TIMESTAMP",
        help="when it happened, ISO-8601 with an offset, e.g. 2026-09-25T14:03:00Z",
    )
    send.add_argument(
        "--idempotency-key",
        metavar="KEY",
        help="unique key of this event, e.g. a run ID: sending it again with the "
        "same key prints the stored event instead of storing another, so a "
        "temporary failure (exit status 3) can be retried safely",
    )
    send.add_argument(
        "--choice",
        metavar="[ID=]LABEL",
        action="append",
        default=[],
        help="ask a question: one choice, repeatable; without ID= the id is derived "
        "from the label (lower-case letters and digits joined by -)",
    )
    send.add_argument(
        "--choice-description",
        metavar="ID=TEXT",
        action="append",
        default=[],
        help="text shown under a choice's label (by its id); repeatable",
    )
    send.add_argument(
        "--multiple",
        action="store_true",
        help="the person may pick one or more choices (needs two or more)",
    )
    send.add_argument(
        "--text",
        choices=["optional", "required"],
        help="the answer takes typed text; without choices it is a typed question",
    )
    send.add_argument(
        "--text-style",
        choices=["note", "other"],
        help="typed text is a note beside the choice (default), or an Other row "
        "picked instead of a choice (with --text optional)",
    )
    send.add_argument(
        "--closes-in",
        metavar="DURATION",
        help="the question closes by itself after this long: a number and s, m, h "
        "or d (at most 30d), e.g. 2h",
    )
    _connection_options(send)
    send.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT,
        help=f"seconds to wait for SignalHub (default: {DEFAULT_TIMEOUT:g})",
    )
    send.add_argument(
        "--json",
        action="store_true",
        help="print the stored event as JSON instead of its ID",
    )

    wait = commands.add_parser(
        "wait-answer",
        help="wait for the answer to an event's question",
        description="Wait until the question of an event is answered or closed. "
        "Prints the chosen choice ids, one per line, then, when there is text, an "
        "empty line and the text. Exit status: 0 answered, 5 closed (by its time "
        "or by the producer), 6 --timeout passed, 1 the event is gone or not this "
        "producer's, 3 SignalHub failing.",
    )
    wait.add_argument("event_id", metavar="EVENT_ID", help="the ID `send` printed")
    wait.add_argument(
        "--timeout",
        metavar="DURATION",
        help="give up after this long: a number and s, m, h or d (default: no limit)",
    )
    _connection_options(wait)
    wait.add_argument(
        "--json",
        action="store_true",
        help="print the question's state as JSON (a closed one carries closedBy, "
        "closedAt and closeNote)",
    )

    close = commands.add_parser(
        "close-question",
        help="close an event's question without an answer",
        description="Close the question of an event answered somewhere else. Exit "
        "status: 0 closed (also if it was closed already, even by its time), 7 "
        "someone answered first (their answer is printed as wait-answer prints it).",
    )
    close.add_argument("event_id", metavar="EVENT_ID", help="the ID `send` printed")
    close.add_argument(
        "--note",
        help="shown with the close, e.g. where it was answered (200 characters)",
    )
    _connection_options(close)
    close.add_argument(
        "--timeout",
        type=float,
        default=DEFAULT_TIMEOUT,
        help=f"seconds to wait for SignalHub (default: {DEFAULT_TIMEOUT:g})",
    )
    return parser


def _connection_options(command: argparse.ArgumentParser) -> None:
    command.add_argument("--url", help=f"SignalHub base address (default: ${URL_ENV})")
    command.add_argument(
        "--api-key-file", metavar="PATH", help="file holding the API key"
    )


def main(
    argv: list[str] | None = None,
    *,
    environ: Mapping[str, str] | None = None,
    stdin: TextIO | None = None,
    stdout: TextIO | None = None,
    stderr: TextIO | None = None,
) -> int:
    stdin = stdin or sys.stdin
    stdout = stdout or sys.stdout
    stderr = stderr or sys.stderr
    try:
        args = _parser().parse_args(argv)
    except SystemExit as exit:  # --help, or a usage error already printed
        return int(exit.code or 0)
    try:
        if args.command == "wait-answer":
            return _wait_answer(args, environ, stdout, stderr)
        if args.command == "close-question":
            return _close_question(args, environ, stdout, stderr)
        hub = _connect(args, environ, args.timeout)
        event = hub.publish(
            category=args.category,
            severity=args.severity,
            title=args.title,
            message=stdin.read() if args.message == "-" else args.message,
            context=args.context,
            metadata=_metadata(args.metadata, args.meta),
            link=args.link,
            occurred_at=args.occurred_at,
            idempotency_key=args.idempotency_key,
            ask=_ask(args),
        )
    except (ConfigurationError, UsageError, ValueError) as error:
        print(f"signalhub: {error}", file=stderr)
        return EXIT_USAGE
    except RequestError as error:
        print(f"signalhub: {error}", file=stderr)
        return EXIT_TEMPORARY if error.temporary else EXIT_REJECTED
    except UnreachableError as error:
        print(f"signalhub: {error}", file=stderr)
        return EXIT_TEMPORARY
    except SignalHubError as error:
        print(f"signalhub: {error}", file=stderr)
        return EXIT_REJECTED
    print(json.dumps(event, indent=2) if args.json else event["id"], file=stdout)
    return EXIT_OK


def _connect(
    args: argparse.Namespace,
    environ: Mapping[str, str] | None,
    timeout: float = DEFAULT_TIMEOUT,
) -> SignalHub:
    env = os.environ if environ is None else environ
    url = args.url or env.get(URL_ENV, "")
    if not url:
        raise ConfigurationError(f"no SignalHub URL: pass --url or set {URL_ENV}")
    if args.api_key_file:
        key = read_api_key_file(args.api_key_file)
    else:
        key = api_key_from_env(env)
    return SignalHub(url, key, timeout=timeout)


_DURATION = re.compile(r"(\d+)([smhd])")
_UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400}


def _seconds(option: str, text: str) -> int:
    match = _DURATION.fullmatch(text.strip())
    if not match:
        raise UsageError(
            f"{option} needs a number and s, m, h or d, e.g. 30m, got {text!r}"
        )
    return int(match.group(1)) * _UNITS[match.group(2)]


def _ask(args: argparse.Namespace) -> Ask | None:
    """The question the `send` options describe, or None if none of them is given."""
    given = (
        args.choice
        or args.choice_description
        or args.multiple
        or args.text
        or args.text_style
        or args.closes_in
    )
    if not given:
        return None
    labelled = [_choice(text) for text in args.choice]
    ids = derive_choice_ids(labelled)
    descriptions: dict[str, str] = {}
    for pair in args.choice_description:
        key, separator, text = pair.partition("=")
        if not separator or not key:
            raise UsageError(f"--choice-description needs ID=TEXT, got {pair!r}")
        if key not in ids:
            raise UsageError(
                f"--choice-description names {key!r}, which no --choice has"
            )
        descriptions[key] = text
    closes_at = None
    if args.closes_in:
        closes_at = datetime.now(timezone.utc) + timedelta(
            seconds=_seconds("--closes-in", args.closes_in)
        )
    return Ask(
        choices=[
            Choice(id_, choice.label, descriptions.get(id_))
            for id_, choice in zip(ids, labelled)
        ],
        multiple=True if args.multiple else None,
        text=args.text,
        text_style=args.text_style,
        closes_at=closes_at,
    )


def _choice(text: str) -> Choice:
    """`ID=LABEL` or just `LABEL` (whose id is derived)."""
    identifier, separator, label = text.partition("=")
    if separator and re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/-]*", identifier):
        return Choice(identifier, label)
    return Choice(None, text)


def _wait_answer(
    args: argparse.Namespace,
    environ: Mapping[str, str] | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    timeout = None if args.timeout is None else _seconds("--timeout", args.timeout)
    hub = _connect(args, environ)
    state = hub.wait_answer(args.event_id, timeout)
    if args.json:
        print(json.dumps(state, indent=2), file=stdout)
    if state["state"] == "ANSWERED":
        if not args.json:
            _print_answer(state["answer"], stdout)
        return EXIT_OK
    if state["state"] == "CLOSED":
        print(f"signalhub: the question was closed ({_closed(state)})", file=stderr)
        return EXIT_CLOSED
    print("signalhub: no answer yet; the timeout passed", file=stderr)
    return EXIT_WAIT_TIMEOUT


def _close_question(
    args: argparse.Namespace,
    environ: Mapping[str, str] | None,
    stdout: TextIO,
    stderr: TextIO,
) -> int:
    hub = _connect(args, environ, args.timeout)
    try:
        hub.close_question(args.event_id, args.note)
    except QuestionAnsweredError as error:
        print(f"signalhub: {error}", file=stderr)
        _print_answer(error.state["answer"], stdout)
        return EXIT_ANSWERED_FIRST
    return EXIT_OK


def _print_answer(answer: dict[str, Any], stdout: TextIO) -> None:
    for choice in answer["choices"]:
        print(choice, file=stdout)
    if answer.get("text") is not None:
        # Ids are never empty, so the empty line tells them from the text.
        print(file=stdout)
        print(answer["text"], file=stdout)


def _closed(state: dict[str, Any]) -> str:
    by = "by its time" if state.get("closedBy") == "TIME" else "by the producer"
    note = state.get("closeNote")
    return f"{by}: {note}" if note else by


def _metadata(document: str | None, pairs: list[str]) -> dict[str, Any] | None:
    metadata: dict[str, Any] | None = None
    if document is not None:
        try:
            metadata = json.loads(document)
        except ValueError as error:
            raise UsageError(f"--metadata is not valid JSON: {error}") from None
        if not isinstance(metadata, dict):
            raise UsageError("--metadata must be a JSON object")
    for pair in pairs:
        key, separator, value = pair.partition("=")
        if not separator or not key:
            raise UsageError(f"--meta needs KEY=VALUE, got {pair!r}")
        metadata = metadata if metadata is not None else {}
        metadata[key] = value
    return metadata


def run() -> NoReturn:
    sys.exit(main())

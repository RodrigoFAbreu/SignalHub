"""The `signalhub` command: publish events from shells, scripts and CI jobs.

Exit status: 0 published, 1 rejected (an invalid event or API key; sending it
again will not help), 2 usage or configuration error, 3 temporary failure
(SignalHub unreachable, overloaded or failing; sending it again later may
help).
"""

from __future__ import annotations

import argparse
import importlib.metadata
import json
import os
import sys
from collections.abc import Mapping
from typing import Any, NoReturn, TextIO

from signalhub.client import (
    API_KEY_ENV,
    API_KEY_FILE_ENV,
    DEFAULT_TIMEOUT,
    URL_ENV,
    Category,
    ConfigurationError,
    RequestError,
    Severity,
    SignalHub,
    SignalHubError,
    UnreachableError,
    api_key_from_env,
    read_api_key_file,
)

EXIT_OK = 0
EXIT_REJECTED = 1
EXIT_USAGE = 2
EXIT_TEMPORARY = 3


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
        epilog="Exit status: 0 published, 1 rejected, 2 usage or configuration error, "
        "3 temporary failure (sending again later may help).",
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
    send.add_argument("--url", help=f"SignalHub base address (default: ${URL_ENV})")
    send.add_argument("--api-key-file", metavar="PATH", help="file holding the API key")
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
    return parser


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
        hub = _connect(args, environ)
        event = hub.publish(
            category=args.category,
            severity=args.severity,
            title=args.title,
            message=stdin.read() if args.message == "-" else args.message,
            context=args.context,
            metadata=_metadata(args.metadata, args.meta),
            occurred_at=args.occurred_at,
            idempotency_key=args.idempotency_key,
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


def _connect(args: argparse.Namespace, environ: Mapping[str, str] | None) -> SignalHub:
    env = os.environ if environ is None else environ
    url = args.url or env.get(URL_ENV, "")
    if not url:
        raise ConfigurationError(f"no SignalHub URL: pass --url or set {URL_ENV}")
    if args.api_key_file:
        key = read_api_key_file(args.api_key_file)
    else:
        key = api_key_from_env(env)
    return SignalHub(url, key, timeout=args.timeout)


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

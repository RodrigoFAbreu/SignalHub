#!/usr/bin/env python3
"""Asks the owner a question through SignalHub and waits for the answer.

A script that must not go on without a human (a deploy, a migration, a
destructive clean-up) publishes the question, the owner answers it in the app
or on the web page, and the script reads the answer and acts on it. When
nobody answers in time, the script closes the question so it does not linger
in the owner's inbox. It uses the Python package in sdk/python and
SIGNALHUB_URL and SIGNALHUB_API_KEY (or SIGNALHUB_API_KEY_FILE).

    ask_to_continue.py --title "Deploy build 1842 to production?" \\
        --choice deploy=Deploy --choice hold=Hold --wait 30m \\
    && ./deploy.sh

It prints the chosen choice IDs, one per line (then, with text, an empty line
and the text), and exits 0 when answered, 5 when the owner's question was
closed, 6 when nobody answered within --wait (the question is then closed),
1 when SignalHub rejected a request, 2 on a usage error, 3 on a temporary
failure. A script that goes on only for one choice checks the line it printed.
"""

from __future__ import annotations

import argparse
import re
import sys

from signalhub import (
    Ask,
    Category,
    Choice,
    ConfigurationError,
    RequestError,
    Severity,
    SignalHub,
    SignalHubError,
)

UNITS = {"s": 1, "m": 60, "h": 3600, "d": 86400}


def seconds(text: str) -> int:
    match = re.fullmatch(r"(\d+)([smhd])", text)
    if not match:
        raise argparse.ArgumentTypeError(f"{text!r} is not a number and s, m, h or d")
    return int(match.group(1)) * UNITS[match.group(2)]


def parse_choice(text: str) -> Choice:
    identifier, separator, label = text.partition("=")
    return Choice(identifier, label) if separator else Choice(None, text)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--title", required=True, help="the question")
    parser.add_argument("--message", help="more detail, shown under the question")
    parser.add_argument("--context", help="event context, e.g. a repository or host")
    parser.add_argument(
        "--choice",
        action="append",
        default=[],
        type=parse_choice,
        metavar="[ID=]LABEL",
        help="a choice to pick; repeatable (none: the owner types an answer)",
    )
    parser.add_argument(
        "--wait",
        type=seconds,
        default=seconds("30m"),
        help="how long to wait for the answer: a number and s, m, h or d (30m)",
    )
    return parser.parse_args(argv)


def print_answer(answer: dict) -> None:
    for choice in answer["choices"]:
        print(choice)
    if answer.get("text") is not None:
        print()
        print(answer["text"])


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        hub = SignalHub.from_env()
        event = hub.publish(
            category=Category.ACTION_REQUIRED,
            severity=Severity.HIGH,
            title=args.title[:200],
            message=args.message,
            context=args.context,
            ask=Ask(choices=args.choice),
        )
        state = hub.wait_answer(event["id"], args.wait)
        if state["state"] == "OPEN":
            hub.close_question(event["id"], note="Nobody answered in time")
            print("ask_to_continue: nobody answered in time", file=sys.stderr)
            return 6
    except ConfigurationError as error:
        print(f"ask_to_continue: {error}", file=sys.stderr)
        return 2
    except RequestError as error:
        print(f"ask_to_continue: {error}", file=sys.stderr)
        return 3 if error.temporary else 1
    except SignalHubError as error:
        print(f"ask_to_continue: {error}", file=sys.stderr)
        return 3
    if state["state"] == "ANSWERED":
        print_answer(state["answer"])
        return 0
    print("ask_to_continue: the question was closed", file=sys.stderr)
    return 5


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

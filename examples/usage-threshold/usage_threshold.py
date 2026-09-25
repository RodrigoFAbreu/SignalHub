#!/usr/bin/env python3
"""Publishes an event when a usage meter crosses a threshold.

Give it a reading (an API quota, a monthly budget, a mobile data plan, ...)
and it publishes once when usage reaches the warning level and once more when
it reaches the limit. A state file remembers the last level notified, so
running it every few minutes does not repeat a notification; when usage
drops below the warning level (a new billing period), the next crossing
notifies again. It uses the Python package in sdk/python and SIGNALHUB_URL
and SIGNALHUB_API_KEY (or SIGNALHUB_API_KEY_FILE).

    usage_threshold.py --name "API quota" --used 8200 --limit 10000 \\
        --warn-at 80 --state-file ~/.cache/api-quota.level

Exit status: 0 when nothing needed publishing or the event was published,
1 when SignalHub rejected it, 2 on a usage error, 3 on a temporary failure;
the state file is only updated after a successful publish, so the next run
tries again.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from signalhub import (
    Category,
    ConfigurationError,
    RequestError,
    Severity,
    SignalHub,
    SignalHubError,
)

# Levels in increasing order; the state file holds the last one notified.
LEVELS = ("ok", "warning", "exceeded")


def level_of(used: float, limit: float, warn_at: float) -> str:
    if used >= limit:
        return "exceeded"
    if used >= limit * warn_at / 100:
        return "warning"
    return "ok"


def read_level(state_file: Path | None) -> str:
    if state_file is None or not state_file.exists():
        return "ok"
    level = state_file.read_text(encoding="utf-8").strip()
    return level if level in LEVELS else "ok"


def event_for(args: argparse.Namespace, level: str) -> dict[str, object]:
    percent = round(args.used / args.limit * 100)
    reading = f"{args.used:g} of {args.limit:g}"
    if level == "exceeded":
        category, severity = Category.BLOCKED, Severity.CRITICAL
        title = f"{args.name} is used up ({percent}%)"
    else:
        category, severity = Category.ACTION_REQUIRED, Severity.HIGH
        title = f"{args.name} is at {percent}%"
    return {
        "category": category,
        "severity": severity,
        "title": title[:200],
        "message": f"{args.name}: {reading} used; the warning level is {args.warn_at:g}%.",
        "context": args.context,
        "metadata": {
            "meter": args.name,
            "used": args.used,
            "limit": args.limit,
            "percent": percent,
            "level": level,
        },
    }


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--name", required=True, help="what is measured")
    parser.add_argument("--used", required=True, type=float)
    parser.add_argument("--limit", required=True, type=float)
    parser.add_argument(
        "--warn-at", type=float, default=80, help="percent of the limit (80)"
    )
    parser.add_argument("--context", help="event context, e.g. a host or account")
    parser.add_argument("--state-file", type=Path, help="remembers the last level")
    args = parser.parse_args(argv)
    if args.limit <= 0:
        parser.error("--limit must be positive")
    return args


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    level = level_of(args.used, args.limit, args.warn_at)
    notified = read_level(args.state_file)
    if LEVELS.index(level) > LEVELS.index(notified):
        try:
            SignalHub.from_env().publish(**event_for(args, level))
        except SignalHubError as error:
            print(f"usage_threshold.py: {error}", file=sys.stderr)
            if isinstance(error, ConfigurationError):
                return 2
            if isinstance(error, RequestError) and not error.temporary:
                return 1
            return 3
    if args.state_file is not None and level != notified:
        args.state_file.write_text(level + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())

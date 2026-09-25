#!/usr/bin/env python3
"""Publishes a coding agent's human gates and completions to SignalHub.

A Claude Code hook: it reads the hook's JSON input on standard input and
publishes an `ACTION_REQUIRED` event when the agent waits for the owner
(`Notification`) and a `COMPLETED` event when it finishes (`Stop`). Other
agents can call it the same way with that JSON. It uses the Python package in
sdk/python and SIGNALHUB_URL and SIGNALHUB_API_KEY (or
SIGNALHUB_API_KEY_FILE); see examples/README.md for the hook settings.

It always exits 0 and reports problems on standard error, so SignalHub being
down never blocks or changes the agent's work.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path
from typing import Any, TextIO

from signalhub import Category, Severity, SignalHub, SignalHubError


def event_for(hook: dict[str, Any]) -> dict[str, Any] | None:
    """The event for a hook input, or None for hooks that notify nobody."""
    project = Path(hook.get("cwd") or ".").resolve().name
    metadata = {
        key: hook[name]
        for key, name in (
            ("hook", "hook_event_name"),
            ("sessionId", "session_id"),
            ("notificationType", "notification_type"),
            ("directory", "cwd"),
        )
        if hook.get(name)
    }
    context = _context(project)
    if hook.get("hook_event_name") == "Notification":
        message = hook.get("message") or "The agent is waiting for you."
        return {
            "category": Category.ACTION_REQUIRED,
            "severity": Severity.HIGH,
            "title": message[:200],
            "message": message[:4000],
            "context": context,
            "metadata": metadata,
        }
    if hook.get("hook_event_name") == "Stop":
        return {
            "category": Category.COMPLETED,
            "severity": Severity.NORMAL,
            "title": f"Agent finished in {project}"[:200],
            "context": context,
            "metadata": metadata,
        }
    return None


def _context(project: str) -> str | None:
    """The project name as an event context, which allows fewer characters."""
    context = re.sub(r"[^A-Za-z0-9._:/-]", "-", project)[:200]
    return context if re.match(r"[A-Za-z0-9]", context) else None


def main(stdin: TextIO = sys.stdin, stderr: TextIO = sys.stderr) -> int:
    try:
        event = event_for(json.load(stdin))
        if event is not None:
            SignalHub.from_env(timeout=5).publish(**event)
    except (SignalHubError, ValueError, TypeError, AttributeError) as error:
        print(f"agent_hook.py: not published to SignalHub: {error}", file=stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())

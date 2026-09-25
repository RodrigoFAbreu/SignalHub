"""An in-process stand-in for the SignalHub events endpoint on 127.0.0.1."""

from __future__ import annotations

import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any


class FakeSignalHub:
    """Records each request and answers with the next queued response.

    Without a queued response it stores the event like SignalHub does: `201`
    with the body plus server-set fields.
    """

    def __init__(self) -> None:
        self.requests: list[dict[str, Any]] = []
        self.responses: list[tuple[int, str | None]] = []
        self.headers: dict[str, str] = {}
        fake = self

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self) -> None:  # noqa: N802 - http.server's naming
                length = int(self.headers.get("Content-Length", 0))
                body = self.rfile.read(length).decode("utf-8")
                fake.requests.append(
                    {
                        "path": self.path,
                        "headers": dict(self.headers),
                        "body": json.loads(body),
                    }
                )
                status, text = (
                    fake.responses.pop(0) if fake.responses else fake._stored(body)
                )
                self.send_response(status)
                for name, value in fake.headers.items():
                    self.send_header(name, value)
                if text is not None:
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(text.encode("utf-8"))))
                self.end_headers()
                if text is not None:
                    self.wfile.write(text.encode("utf-8"))

            def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
                pass

        self._server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.url = f"http://127.0.0.1:{self._server.server_address[1]}"
        self._thread = threading.Thread(
            target=self._server.serve_forever,
            kwargs={"poll_interval": 0.01},
            daemon=True,
        )

    def _stored(self, body: str) -> tuple[int, str]:
        event = json.loads(body)
        event.setdefault("metadata", {})
        event.update(
            {
                "id": "0199a1b2-c3d4-7e5f-8a9b-0c1d2e3f4a5b",
                "producer": {
                    "id": "0199a1b2-0000-7000-8000-000000000001",
                    "name": "test",
                },
                "createdAt": "2026-09-25T14:03:00Z",
                "readAt": None,
            }
        )
        return 201, json.dumps(event)

    def respond(self, status: int, body: Any = None) -> None:
        self.responses.append((status, body if body is None else json.dumps(body)))

    def respond_raw(self, status: int, text: str) -> None:
        self.responses.append((status, text))

    def __enter__(self) -> FakeSignalHub:
        self._thread.start()
        return self

    def __exit__(self, *exc: object) -> None:
        self._server.shutdown()
        self._server.server_close()


def start(test: unittest.TestCase) -> FakeSignalHub:
    """Starts a fake that stops when the test ends."""
    server = FakeSignalHub().__enter__()
    test.addCleanup(server.__exit__)
    return server

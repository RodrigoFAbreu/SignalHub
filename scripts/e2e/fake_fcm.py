"""A stand-in for Google's OAuth token endpoint and the FCM HTTP v1 API.

The end-to-end CI job points the packaged backend at it, so a published event's
push can be checked without a Firebase project or network access. Every send is
appended to a JSON Lines file. A registration token starting with
"unregistered-" is answered as FCM answers a token whose app was uninstalled.

    python scripts/e2e/fake_fcm.py --port 8099 --record sends.jsonl
"""

from __future__ import annotations

import argparse
import base64
import json
import threading
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ACCESS_TOKEN = "fake-fcm-access-token"
UNREGISTERED_PREFIX = "unregistered-"
JWT_BEARER = "urn:ietf:params:oauth:grant-type:jwt-bearer"


class FakeFcm(BaseHTTPRequestHandler):
    record: Path
    lock = threading.Lock()

    def do_POST(self) -> None:
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/token":
            self._token(body)
        elif self.path.startswith("/v1/projects/") and self.path.endswith(
            "/messages:send"
        ):
            self._send(body)
        else:
            self._answer(404, {"error": {"code": 404, "status": "NOT_FOUND"}})

    def _token(self, body: bytes) -> None:
        form = urllib.parse.parse_qs(body.decode())
        assertion = form.get("assertion", [""])[0].split(".")
        # The signature is checked by the backend's own tests (FakeFcm.java); here
        # it is enough that the backend sent a signed assertion for the right scope.
        if form.get("grant_type") != [JWT_BEARER] or len(assertion) != 3:
            self._answer(400, {"error": "invalid_grant"})
            return
        claims = json.loads(base64.urlsafe_b64decode(assertion[1] + "=="))
        if "firebase.messaging" not in claims.get("scope", ""):
            self._answer(400, {"error": "invalid_scope"})
            return
        self._answer(
            200,
            {"access_token": ACCESS_TOKEN, "expires_in": 3599, "token_type": "Bearer"},
        )

    def _send(self, body: bytes) -> None:
        if self.headers.get("Authorization") != f"Bearer {ACCESS_TOKEN}":
            self._answer(401, {"error": {"code": 401, "status": "UNAUTHENTICATED"}})
            return
        message = json.loads(body)["message"]
        with self.lock, self.record.open("a", encoding="utf-8") as record:
            record.write(json.dumps({"path": self.path, "message": message}) + "\n")
        if message["token"].startswith(UNREGISTERED_PREFIX):
            self._answer(404, _unregistered())
        else:
            self._answer(200, {"name": self.path.split("/messages")[0] + "/messages/1"})

    def _answer(self, status: int, body: object) -> None:
        payload = json.dumps(body).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)


def _unregistered() -> dict[str, object]:
    return {
        "error": {
            "code": 404,
            "message": "Requested entity was not found.",
            "status": "NOT_FOUND",
            "details": [
                {
                    "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError",
                    "errorCode": "UNREGISTERED",
                }
            ],
        }
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--record", type=Path, required=True)
    args = parser.parse_args()
    FakeFcm.record = args.record
    args.record.touch()
    # All interfaces: the backend container reaches it through the Docker host.
    ThreadingHTTPServer(("0.0.0.0", args.port), FakeFcm).serve_forever()


if __name__ == "__main__":
    main()

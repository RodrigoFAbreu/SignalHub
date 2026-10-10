"""The helpers the container tests share, against a throwaway server (no stack needed).

CI's Python job runs this module; the container jobs run the others.
"""

import json
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from signalhub_stack import Endpoint, wait_until


class Echo(BaseHTTPRequestHandler):
    def do_request(self):
        length = int(self.headers.get("Content-Length") or 0)
        answer = {
            "method": self.command,
            "target": self.path,
            "authorization": self.headers.get("Authorization"),
            "cookie": self.headers.get("Cookie"),
            "body": self.rfile.read(length).decode() if length else None,
        }
        if self.path == "/redirect":
            self.send_response(308)
            self.send_header("Location", "/elsewhere")
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        payload = json.dumps(answer).encode()
        self.send_response(201)
        self.send_header("Content-Type", "application/json")
        self.send_header("Set-Cookie", "a=b; Secure")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = do_POST = do_PUT = do_PATCH = do_DELETE = do_request

    def log_message(self, format, *args):
        pass


class EndpointTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), Echo)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.endpoint = Endpoint(f"http://127.0.0.1:{cls.server.server_address[1]}")

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()

    def test_a_path_is_sent_exactly_as_spelled(self):
        for path in ("/api//v1/x", "/api/v1/%61dmin/y", "/a/../b", "/api/%2e%2e/q"):
            with self.subTest(path):
                self.assertEqual(path, self.endpoint.get(path).json()["target"])

    def test_a_query_is_encoded(self):
        sent = self.endpoint.get("/events", query={"producerId": "a b", "limit": 1})
        self.assertEqual("/events?producerId=a+b&limit=1", sent.json()["target"])

    def test_a_token_and_a_cookie_are_sent_as_headers(self):
        sent = self.endpoint.get("/", token="secret", cookie="session=1").json()
        self.assertEqual("Bearer secret", sent["authorization"])
        self.assertEqual("session=1", sent["cookie"])

    def test_a_body_is_sent_as_json(self):
        answer = self.endpoint.post("/", body={"name": "x"})
        self.assertEqual(201, answer.status)
        self.assertEqual('{"name": "x"}', answer.json()["body"])

    def test_every_method_is_sent(self):
        for method in ("get", "post", "put", "patch", "delete"):
            with self.subTest(method):
                self.assertEqual(
                    method.upper(), getattr(self.endpoint, method)("/").json()["method"]
                )

    def test_a_redirect_is_not_followed(self):
        answer = self.endpoint.get("/redirect")
        self.assertEqual(308, answer.status)
        self.assertEqual("/elsewhere", answer.header("Location"))

    def test_headers_are_read_without_regard_to_case(self):
        self.assertEqual("a=b; Secure", self.endpoint.get("/").header("set-cookie"))


class WaitUntilTest(unittest.TestCase):
    def test_it_returns_once_the_condition_holds(self):
        attempts = []
        wait_until(
            lambda: attempts.append(1) or len(attempts) == 3, "three tries", interval=0
        )
        self.assertEqual(3, len(attempts))

    def test_it_gives_up_with_what_it_waited_for(self):
        with self.assertRaisesRegex(AssertionError, "waiting for the moon"):
            wait_until(lambda: False, "the moon", timeout=0, interval=0)


if __name__ == "__main__":
    unittest.main()

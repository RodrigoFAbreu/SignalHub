"""Tests of check-image.sh against stand-ins for docker and curl.

The stand-ins answer as a healthy image of release 1.2.3 would, so the tests
need no Docker, network or image.
"""

import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "check-image.sh"
REVISION = "0123456789abcdef0123456789abcdef01234567"

# Answers every docker command check-image.sh runs. `docker logs` prints the
# startup summary ($SUMMARY), then far more than a pipe buffer holds, as a
# real backend's log may: a reader that stops at the summary makes the rest
# fail with SIGPIPE.
DOCKER = r"""#!/usr/bin/env bash
case "$1 $2" in
  "image inspect")
    case "$4" in
      *image.version*) echo 1.2.3 ;;
      *image.revision*) echo "$REVISION" ;;
      *image.source*) echo https://github.com/RodrigoFAbreu/SignalHub ;;
      *image.created*) echo 2026-09-26T00:00:00Z ;;
      *Architecture*) echo arm64 ;;
    esac ;;
  "version --format") echo arm64 ;;
  "inspect --format")
    case "$3" in
      *Health*) echo healthy ;;
      *Running*) echo true ;;
    esac ;;
  "port "*) echo 127.0.0.1:18080 ;;
  "logs "*)
    echo "INFO [StartupDiagnostics] (main) $SUMMARY"
    head --bytes 1000000 /dev/zero | tr '\0' 'x' ;;
esac
"""

CURL = f"""#!/usr/bin/env bash
echo '{{"signalhub": {{"version": "1.2.3", "revision": "{REVISION}"}}}}'
"""


class CheckImageTest(unittest.TestCase):
    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.bin = Path(directory.name)
        for name, content in {"docker": DOCKER, "curl": CURL}.items():
            path = self.bin / name
            path.write_text(content)
            path.chmod(path.stat().st_mode | stat.S_IXUSR)

    def check(self, summary):
        env = {
            **os.environ,
            "PATH": f"{self.bin}{os.pathsep}{os.environ['PATH']}",
            "REVISION": REVISION,
            "SUMMARY": summary,
        }
        return subprocess.run(
            [SCRIPT, "ghcr.io/rodrigofabreu/signalhub:1.2.3", "1.2.3", REVISION],
            env=env,
            capture_output=True,
            text=True,
            check=False,
        )

    def test_accepts_the_startup_summary_of_the_release_in_a_long_log(self):
        result = self.check(
            f"SignalHub 1.2.3 (commit {REVISION}); Configuration: profile prod; JSON logs off"
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("startup summary: begins with 'SignalHub 1.2.3", result.stdout)

    def test_rejects_the_startup_summary_of_another_build(self):
        result = self.check("SignalHub development build; Configuration: profile prod;")
        self.assertEqual(result.returncode, 1)
        self.assertIn("the startup summary does not begin with", result.stderr)


if __name__ == "__main__":
    unittest.main()

"""Keep the caller's completed-release gate while sharing image promotion."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


class LatestCallerTests(unittest.TestCase):
    def test_promotion_uses_the_completed_release(self):
        source = (ROOT / ".github/workflows/build-and-publish.yml").read_text()
        job = source.split("\n  latest:\n", 1)[1]
        self.assertIn("needs: [version, image, release]", job)
        self.assertIn("needs.version.outputs.next != ''", job)
        self.assertIn(
            "uses: RodrigoFAbreu/action-workflows/.github/workflows/promote-image.yml@main",
            job,
        )
        self.assertIn(
            "source: ghcr.io/rodrigofabreu/signalhub@${{ needs.image.outputs.digest }}",
            job,
        )
        self.assertIn("packages: write", job)


if __name__ == "__main__":
    unittest.main()

import unittest

from run_stats import peak, report, summarize

T = "2026-01-01T00:{minute:02d}:{second:02d}Z"


def job(
    name, start, end, labels=("ubuntu-latest",), conclusion="success", created=None
):
    def at(seconds):
        return T.format(minute=seconds // 60, second=seconds % 60)

    return {
        "name": name,
        "labels": list(labels),
        "created_at": at(start if created is None else created),
        "started_at": at(start),
        "completed_at": at(end),
        "conclusion": conclusion,
    }


class PeakTest(unittest.TestCase):
    def test_a_job_that_ends_when_another_starts_does_not_overlap(self):
        self.assertEqual(1, peak([(0, 10), (10, 20)]))

    def test_overlapping_jobs_count_together(self):
        self.assertEqual(3, peak([(0, 30), (5, 10), (8, 40), (50, 60)]))

    def test_no_jobs(self):
        self.assertEqual(0, peak([]))


class SummarizeTest(unittest.TestCase):
    def setUp(self):
        self.summary = summarize(
            [
                job("a", 0, 120),
                job("b", 30, 90, created=20),
                job("c", 60, 240, labels=["macos-15"]),
                job("d", 100, 190, labels=["ubuntu-24.04-arm"]),
                job("skipped", 5, 5, conclusion="skipped"),
            ]
        )

    def test_linux_and_macos_are_apart(self):
        linux, mac = self.summary["systems"]["Linux"], self.summary["systems"]["macOS"]
        self.assertEqual((3, 2), (linux["jobs"], linux["peak"]))
        self.assertEqual((1, 1), (mac["jobs"], mac["peak"]))

    def test_runner_minutes_are_exact_and_billed_rounded_up_per_job(self):
        linux = self.summary["systems"]["Linux"]
        self.assertAlmostEqual((120 + 60 + 90) / 60, linux["minutes"])
        self.assertEqual(2 + 1 + 2, linux["billed_minutes"])

    def test_wall_time_and_longest_wait(self):
        self.assertEqual(240, self.summary["wall_seconds"])
        self.assertEqual(10, self.summary["max_wait"])

    def test_a_skipped_job_holds_no_runner(self):
        self.assertEqual(4, self.summary["jobs"])

    def test_the_report_names_the_numbers(self):
        text = report(1, self.summary)
        self.assertIn("Linux: 3 jobs, peak 2 at once", text)
        self.assertIn("macOS: 1 jobs, peak 1 at once", text)
        self.assertIn("wall time 4.0 min", text)

    def test_a_run_without_jobs(self):
        self.assertEqual({"jobs": 0}, summarize([]))


if __name__ == "__main__":
    unittest.main()

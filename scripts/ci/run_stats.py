#!/usr/bin/env python3
"""Reports how much runner capacity a workflow run held (docs/development.md#measuring-a-run).

The free plan shares 20 runners (5 of them macOS) between all repositories, so
the number that matters is the peak of jobs running at once, not the number of
jobs. For each run it prints the jobs, the peak of concurrent jobs (Linux and
macOS apart), the runner-minutes (exact, and rounded up per job as GitHub
bills), the longest wait for a runner, and the wall time from the first job's
start to the last one's end.

    scripts/ci/run_stats.py RUN_ID [RUN_ID ...]    # needs the gh CLI, signed in
    scripts/ci/run_stats.py --jobs FILE            # the JSON of the jobs API, saved
"""

import argparse
import json
import math
import subprocess
import sys
from datetime import datetime

REPOSITORY = "RodrigoFAbreu/SignalHub"


def parse_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def operating_system(job):
    labels = [label.lower() for label in job.get("labels", [])]
    return "macOS" if any(label.startswith("macos") for label in labels) else "Linux"


def ran(job):
    """A job that held a runner: skipped and never-started jobs held none."""
    return (
        job.get("started_at")
        and job.get("completed_at")
        and job.get("conclusion") not in ("skipped", None)
    )


def peak(intervals):
    """The most intervals open at once; one ending when another starts does not overlap."""
    events = []
    for start, end in intervals:
        events.append((start, 1))
        events.append((end, -1))
    open_now = highest = 0
    for _, change in sorted(events):
        open_now += change
        highest = max(highest, open_now)
    return highest


def summarize(jobs):
    """The numbers of one run, from the jobs of the API (`jobs` key)."""
    held = [job for job in jobs if ran(job)]
    if not held:
        return {"jobs": 0}
    rows = []
    for job in held:
        start, end = parse_time(job["started_at"]), parse_time(job["completed_at"])
        queued = parse_time(job["created_at"])
        rows.append(
            {
                "name": job["name"],
                "os": operating_system(job),
                "start": start,
                "end": end,
                "seconds": (end - start).total_seconds(),
                "wait": max((start - queued).total_seconds(), 0),
            }
        )
    first = min(row["start"] for row in rows)
    last = max(row["end"] for row in rows)
    systems = {}
    for system in ("Linux", "macOS"):
        mine = [row for row in rows if row["os"] == system]
        systems[system] = {
            "jobs": len(mine),
            "peak": peak([(row["start"], row["end"]) for row in mine]),
            "minutes": sum(row["seconds"] for row in mine) / 60,
            "billed_minutes": sum(math.ceil(row["seconds"] / 60) for row in mine),
        }
    return {
        "jobs": len(rows),
        "rows": sorted(rows, key=lambda row: row["start"]),
        "first": first,
        "systems": systems,
        "wall_seconds": (last - first).total_seconds(),
        "max_wait": max(row["wait"] for row in rows),
    }


def report(run_id, summary):
    lines = [f"run {run_id}: {summary['jobs']} jobs"]
    if not summary["jobs"]:
        return "\n".join(lines)
    for row in summary["rows"]:
        lines.append(
            f"  {row['os']:5}  +{(row['start'] - summary['first']).total_seconds() / 60:5.1f} min"
            f"  {row['seconds'] / 60:5.1f} min  waited {row['wait']:3.0f} s  {row['name']}"
        )
    for system, numbers in summary["systems"].items():
        lines.append(
            f"  {system}: {numbers['jobs']} jobs, peak {numbers['peak']} at once, "
            f"{numbers['minutes']:.1f} runner-minutes ({numbers['billed_minutes']} billed)"
        )
    lines.append(
        f"  wall time {summary['wall_seconds'] / 60:.1f} min, "
        f"longest wait for a runner {summary['max_wait']:.0f} s"
    )
    return "\n".join(lines)


def fetch_jobs(run_id):
    output = subprocess.run(
        [
            "gh",
            "api",
            "--paginate",
            "--slurp",
            f"repos/{REPOSITORY}/actions/runs/{run_id}/jobs?per_page=100",
        ],
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    return [job for page in json.loads(output) for job in page["jobs"]]


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("runs", nargs="*", help="workflow run ids")
    parser.add_argument("--jobs", help="a saved response of the run's jobs API")
    args = parser.parse_args(argv)
    if bool(args.runs) == bool(args.jobs):
        parser.error("give run ids, or --jobs FILE")
    if args.jobs:
        with open(args.jobs, encoding="utf-8") as file:
            print(report(args.jobs, summarize(json.load(file)["jobs"])))
        return 0
    for run_id in args.runs:
        print(report(run_id, summarize(fetch_jobs(run_id))))
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/bin/sh
# Publishes an event with the `signalhub` command when a file system is at
# least PERCENT full, and nothing otherwise. Run it from cron or a systemd
# timer; each run over the threshold publishes again.
#
# Usage: check-disk-usage.sh [PATH [PERCENT]]   (defaults: / and 90)
# Needs the `signalhub` command (sdk/python) and SIGNALHUB_URL and
# SIGNALHUB_API_KEY (or SIGNALHUB_API_KEY_FILE) in the environment.
set -eu

path=${1:-/}
threshold=${2:-90}

# POSIX df output: a header, then the file system, with the available space,
# the capacity and the mount point last.
report=$(df -P "$path" | awk 'NR == 2')
used=$(echo "$report" | awk '{ sub("%", "", $5); print $5 }')
available_kib=$(echo "$report" | awk '{ print $4 }')
mount=$(echo "$report" | awk '{ print $6 }')

if [ "$used" -lt "$threshold" ]; then
  exit 0
fi

# A full file system stops databases and logs, so it is critical.
severity=HIGH
if [ "$used" -ge 98 ]; then
  severity=CRITICAL
fi

signalhub send --category ACTION_REQUIRED --severity "$severity" \
  --title "Disk $mount on $(uname -n) is $used% full" \
  --message "$((available_kib / 1024)) MiB left on $mount; the threshold is $threshold%." \
  --context "$(uname -n)" \
  --meta "mount=$mount" --meta "usedPercent=$used" \
  --meta "thresholdPercent=$threshold" --meta "availableKiB=$available_kib"

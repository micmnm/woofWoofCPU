#!/bin/bash
# Deliberately hogs a resource so the dog has something to bark at.
#   scripts/hog.sh cpu [seconds]        burn one core (default 300 s)
#   scripts/hog.sh mem [GB] [seconds]   hold GB of touched memory (default 4 GB, 300 s)
set -euo pipefail

case "${1:-}" in
  cpu)
    secs="${2:-300}"
    yes > /dev/null &
    pid=$!
    trap 'kill $pid 2>/dev/null || true' EXIT
    echo "Burning one core as 'yes' (pid $pid) for ${secs}s…"
    sleep "$secs"
    ;;
  mem)
    gb="${2:-4}"
    secs="${3:-300}"
    echo "Holding ${gb} GB in python3 for ${secs}s…"
    python3 -c "
import time
b = bytearray(int($gb * 1024**3))
for i in range(0, len(b), 4096): b[i] = 1
time.sleep($secs)
"
    ;;
  *)
    echo "usage: $0 cpu [seconds] | mem [GB] [seconds]" >&2
    exit 1
    ;;
esac

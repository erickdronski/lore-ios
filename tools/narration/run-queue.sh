#!/bin/zsh
# Sequential studio-narration queue. One city at a time — Chatterbox saturates
# the MPS GPU, so parallel runs would thrash, not speed up. Each city batch is
# resumable (generate.py only synthesizes dives that still lack audio), so this
# script can be killed and re-run freely.
#
# Usage: ./run-queue.sh chicago philadelphia nyc ...
set -u
cd "$(dirname "$0")"
export PYTORCH_ENABLE_MPS_FALLBACK=1
export HF_HUB_DISABLE_XET=1

for c in "$@"; do
  echo "=== $(date '+%Y-%m-%d %H:%M') narrating: $c ==="
  .venv/bin/python generate.py --batch-city "$c" --upload 2>/dev/null | grep -vE "Sampling" | tail -6
done
echo "=== queue complete: $(date '+%Y-%m-%d %H:%M') ==="

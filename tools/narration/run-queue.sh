#!/bin/zsh
# Sequential studio-narration queue. One city at a time. The production path is
# Voicebox when its local server is running, then ElevenLabs when
# ELEVENLABS_API_KEY is present. Chatterbox remains available for local draft
# runs by setting LORE_NARRATION_PROVIDER=chatterbox. Each city batch is
# resumable (generate.py only synthesizes dives that still lack audio), so this
# script can be killed and re-run freely.
#
# Usage: ./run-queue.sh chicago philadelphia nyc ...
set -u
cd "$(dirname "$0")"
export PYTORCH_ENABLE_MPS_FALLBACK=1
export HF_HUB_DISABLE_XET=1
provider="${LORE_NARRATION_PROVIDER:-}"
if [[ -z "$provider" ]]; then
  voicebox_url="${VOICEBOX_API_URL:-http://127.0.0.1:17493}"
  voicebox_client_id="${VOICEBOX_CLIENT_ID:-lore-narration}"
  voicebox_bound=false
  if [[ -n "${VOICEBOX_PROFILE:-}" ]]; then
    voicebox_bound=true
  elif curl -sS --max-time 2 "$voicebox_url/mcp/bindings" 2>/dev/null | grep -q "\"client_id\":\"$voicebox_client_id\""; then
    voicebox_bound=true
  fi
  if [[ "$voicebox_bound" == "true" ]] && \
     (curl -sS --max-time 2 "$voicebox_url/health" >/dev/null 2>&1 || \
      curl -sS --max-time 2 "$voicebox_url/profiles" >/dev/null 2>&1); then
    provider="voicebox"
  elif [[ -n "${ELEVENLABS_API_KEY:-}" ]]; then
    provider="elevenlabs"
  else
    provider="chatterbox"
  fi
fi
echo "provider: $provider"

for c in "$@"; do
  echo "=== $(date '+%Y-%m-%d %H:%M') narrating: $c ==="
  .venv/bin/python generate.py --provider "$provider" --batch-city "$c" --upload 2>&1 | grep -vE "Sampling" | tail -12
done
echo "=== queue complete: $(date '+%Y-%m-%d %H:%M') ==="

#!/usr/bin/env python3
"""Lore narration generator - premium pre-rendered audio for dives.

Synthesizes dive narratives into hosted audio files and optionally uploads them
to Supabase Storage (`narration` public bucket) + stamps the dive row so the app
plays a studio track instead of on-device TTS.

Providers:
- Chatterbox: local Apple-Silicon MPS, no per-run cost, useful for drafts.
- ElevenLabs: paid studio voice, production default when ELEVENLABS_API_KEY is
  present. API keys stay on the workstation/CI and are never shipped in the app.
- Voicebox: local open-source workstation TTS server. Preferred no-cost studio
  path when the Voicebox app/server is running and VOICEBOX_PROFILE points to a
  rights-cleared house narrator profile.

Single place (audition):
  .venv/bin/python generate.py --provider elevenlabs --city austin \
      --slug texas-state-capitol --out ~/Desktop/sample.mp3

City batch (the overnight run; uploads as it goes, resumable):
  .venv/bin/python generate.py --provider elevenlabs --batch-city austin --upload

Machine notes (work laptop):
- TLS proxy breaks python-urllib AND the hf-xet downloader → all HTTP goes
  through `curl` (system keychain), and model weights can be curl-fetched with
  --model-dir models/chatterbox.
- Voice rule: default Chatterbox narrator, or a --voice reference clip we have
  the RIGHTS to (our own recording / licensed). Never clone a real person
  without written consent.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.parse
from datetime import datetime, timezone
from pathlib import Path

SUPABASE_URL = "https://uiuwzymvyrgfyiugqlkp.supabase.co"
PROJECT_REF = "uiuwzymvyrgfyiugqlkp"
# Public anon key (safe to embed; RLS-guarded read-only surface).
ANON = (
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9."
    "eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVpdXd6eW12eXJnZnlpdWdxbGtwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODI5NjMwNzYsImV4cCI6MjA5ODUzOTA3Nn0."
    "4t_e9svhpmXkvr8z595sWrkiQliu6vMrW7wdhuE5I0U"
)
PAT_PATH = Path.home() / ".config/lore/supabase.token"

CHATTERBOX_VOICE_TAG = "chatterbox-default"
ELEVENLABS_VOICE_ID = "30fc8796-ceb6-4a66-b3a7-4a145ef7f346"
ELEVENLABS_MODEL = "eleven_multilingual_v2"
ELEVENLABS_OUTPUT_FORMAT = "mp3_44100_128"
VOICEBOX_API_URL = "http://127.0.0.1:17493"
VOICEBOX_CLIENT_ID = "lore-narration"
VOICEBOX_LANGUAGE = "en"
VOICEBOX_MAX_CHARS = 6_000
MAX_CHUNK = 280
SILENCE_S = 0.35


def curl_json(url: str, headers: dict[str, str]) -> object:
    """GET via curl (the TLS proxy breaks python-urllib on this machine)."""
    cmd = ["curl", "-sS", "--fail-with-body", url]
    for key, value in headers.items():
        cmd += ["-H", f"{key}: {value}"]
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return json.loads(result.stdout)


def curl_json_request(
    method: str,
    url: str,
    headers: dict[str, str],
    payload: dict | None = None,
) -> object:
    """JSON request via curl. Used for local Voicebox too, so the narration
    tool has one audited HTTP path and avoids python urllib TLS drift."""
    cmd = ["curl", "-sS", "--http1.1", "--fail-with-body", "-X", method, url]
    for key, value in headers.items():
        cmd += ["-H", f"{key}: {value}"]
    if payload is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(payload)]
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.returncode != 0:
        body = result.stdout.strip() or result.stderr.strip()
        raise RuntimeError(f"curl {method} {url} failed: {body[:500]}")
    return json.loads(result.stdout or "{}")


def service_key() -> str:
    """The project's service_role key via the Management API PAT (never stored)."""
    if not PAT_PATH.exists():
        sys.exit(f"--upload needs the Supabase PAT at {PAT_PATH}")
    pat = PAT_PATH.read_text().strip()
    keys = curl_json(
        f"https://api.supabase.com/v1/projects/{PROJECT_REF}/api-keys?reveal=true",
        {"Authorization": f"Bearer {pat}"},
    )
    for key in keys:
        if key.get("name") == "service_role":
            return key["api_key"]
    sys.exit("service_role key not found via Management API")


def content_type(local: Path) -> str:
    suffix = local.suffix.lower()
    if suffix == ".mp3":
        return "audio/mpeg"
    if suffix in {".m4a", ".mp4"}:
        return "audio/mp4"
    if suffix == ".aac":
        return "audio/aac"
    if suffix == ".wav":
        return "audio/wav"
    return "application/octet-stream"


def duration_seconds(local: Path, fallback_text: str) -> float:
    """Read audio duration with macOS afinfo; fall back to spoken-word estimate."""
    result = subprocess.run(["afinfo", str(local)], capture_output=True, text=True)
    if result.returncode == 0:
        match = re.search(r"estimated duration:\s*([0-9.]+)\s*sec", result.stdout)
        if match:
            return float(match.group(1))
    words = len(re.findall(r"\w+", fallback_text))
    return max(1.0, words / 2.35)


def fetch_dives(city: str, slug: str | None, missing_only: bool) -> list[dict]:
    """Dive rows (with place identity) for one slug or a whole city."""
    params: list[tuple[str, str]] = [
        ("select", "place_id,narrative,audio_path,place:place_id!inner(name,slug,city)"),
        ("place.city", f"eq.{city}"),
        ("narrative", "not.is.null"),
        ("order", "place_id"),
        ("limit", "500"),
    ]
    if slug:
        params.append(("place.slug", f"eq.{slug}"))
    if missing_only:
        params.append(("audio_path", "is.null"))
    qs = urllib.parse.urlencode(params)
    rows = curl_json(
        f"{SUPABASE_URL}/rest/v1/dive?{qs}",
        {"apikey": ANON, "Authorization": f"Bearer {ANON}"},
    )
    return [r for r in rows if (r.get("narrative") or "").strip()]


def sentence_chunks(text: str, limit: int = MAX_CHUNK) -> list[str]:
    sentences = re.split(r"(?<=[.!?])\s+", text.replace("\n", " ").strip())
    chunks: list[str] = []
    current = ""
    for sentence in sentences:
        if not sentence:
            continue
        candidate = f"{current} {sentence}".strip()
        if len(candidate) <= limit:
            current = candidate
        else:
            if current:
                chunks.append(current)
            current = sentence
    if current:
        chunks.append(current)
    return chunks


def synthesize_chatterbox(model, text: str, out: Path, voice: str | None,
                          exaggeration: float, cfg_weight: float) -> float:
    """Narrate `text` into an AAC file at `out`; returns duration in seconds."""
    import torch
    import torchaudio

    kwargs = {"exaggeration": exaggeration, "cfg_weight": cfg_weight}
    if voice:
        kwargs["audio_prompt_path"] = voice
    chunks = sentence_chunks(text)
    pieces = []
    silence = torch.zeros(1, int(model.sr * SILENCE_S))
    for i, chunk in enumerate(chunks, 1):
        print(f"    [{i}/{len(chunks)}] {chunk[:56]}…", flush=True)
        wav = model.generate(chunk, **kwargs)
        pieces.append(wav.cpu())
        pieces.append(silence)
    audio = torch.cat(pieces[:-1], dim=1)
    out.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp:
        torchaudio.save(tmp.name, audio, model.sr)
        # Chatterbox emits mono 24 kHz; valid AAC bitrates depend on rate ×
        # channels, so try 64 kbps and fall back to the encoder's default
        # rather than dying after minutes of GPU synthesis.
        encode = subprocess.run(
            ["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", tmp.name, str(out)],
            capture_output=True, text=True,
        )
        if encode.returncode != 0:
            encode = subprocess.run(
                ["afconvert", "-f", "m4af", "-d", "aac", tmp.name, str(out)],
                capture_output=True, text=True,
            )
        if encode.returncode != 0:
            sys.exit(f"afconvert failed: {encode.stderr.strip()}")
        Path(tmp.name).unlink(missing_ok=True)
    return audio.shape[1] / model.sr


def _curl_retry_output(args: list[str], out: Path, attempts: int = 4) -> None:
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(out.suffix + ".tmp")
    last = None
    import time

    for attempt in range(attempts):
        tmp.unlink(missing_ok=True)
        result = subprocess.run(
            ["curl", "-sS", "--http1.1", "--fail-with-body", *args, "--output", str(tmp)],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            tmp.replace(out)
            return
        last = result
        time.sleep(2 * (attempt + 1))

    body = ""
    if tmp.exists():
        body = tmp.read_text(errors="ignore")[:500]
        tmp.unlink(missing_ok=True)
    raise RuntimeError(
        f"curl failed after {attempts} attempts "
        f"(exit {last.returncode}): {(body or last.stderr).strip()[:500]}"
    )


def synthesize_elevenlabs(text: str, out: Path, args) -> float:
    """Generate a paid studio read through ElevenLabs and write it to `out`."""
    api_key = os.getenv("ELEVENLABS_API_KEY")
    if not api_key:
        raise RuntimeError("ELEVENLABS_API_KEY is required for --provider elevenlabs")
    if len(text) > 10_000:
        raise RuntimeError(
            "ElevenLabs multilingual v2 accepts 10,000 characters; shorten the script "
            "or split this dive before generating studio audio."
        )

    voice_id = args.voice_id or ELEVENLABS_VOICE_ID
    payload = {
        "text": text,
        "model_id": args.eleven_model,
        "voice_settings": {
            "stability": args.stability,
            "similarity_boost": args.similarity_boost,
            "style": args.style,
            "use_speaker_boost": not args.no_speaker_boost,
        },
    }
    url = (
        f"https://api.elevenlabs.io/v1/text-to-speech/{voice_id}"
        f"?output_format={args.eleven_output_format}"
    )
    _curl_retry_output([
        "-X", "POST",
        url,
        "-H", f"xi-api-key: {api_key}",
        "-H", "Content-Type: application/json",
        "-d", json.dumps(payload),
    ], out)
    return duration_seconds(out, text)


def _voicebox_url(args, path: str) -> str:
    return f"{args.voicebox_api_url.rstrip('/')}/{path.lstrip('/')}"


def _voicebox_headers(args) -> dict[str, str]:
    return {
        "Accept": "application/json",
        "X-Voicebox-Client-Id": args.voicebox_client_id,
    }


def _voicebox_generation_id(payload: dict) -> str:
    generation_id = payload.get("generation_id") or payload.get("id") or payload.get("audio_id")
    if not generation_id:
        raise RuntimeError(f"Voicebox response did not include a generation id: {payload}")
    return str(generation_id)


def _write_voicebox_audio(payload: dict, out: Path, args) -> bool:
    """Write Voicebox audio when the response already contains bytes or an
    accessible file reference. Returns false when the generation still needs to
    be polled/downloaded."""
    out.parent.mkdir(parents=True, exist_ok=True)

    audio_b64 = payload.get("audio_base64")
    if isinstance(audio_b64, str) and audio_b64:
        out.write_bytes(base64.b64decode(audio_b64))
        return True

    audio_path = payload.get("audio_path")
    if isinstance(audio_path, str) and audio_path:
        path = Path(audio_path).expanduser()
        if path.exists():
            shutil.copyfile(path, out)
            return True

    audio_url = payload.get("audio_url")
    if isinstance(audio_url, str) and audio_url:
        _curl_retry_output([audio_url], out)
        return True

    generation_id = payload.get("generation_id") or payload.get("id") or payload.get("audio_id")
    if generation_id and payload.get("status") in {"completed", "complete", "done", "succeeded", "success"}:
        _curl_retry_output([_voicebox_url(args, f"/audio/{generation_id}")], out)
        return True

    return False


def synthesize_voicebox(text: str, out: Path, args) -> float:
    """Generate a local Voicebox studio read and write it to `out`.

    Voicebox runs as a localhost workstation service. No model, key, or voice
    profile data is embedded in the iOS app; this tool only creates hosted
    narration files that the app already knows how to play.
    """
    if len(text) > args.voicebox_max_chars:
        raise RuntimeError(
            f"Voicebox text is {len(text)} characters, above "
            f"--voicebox-max-chars={args.voicebox_max_chars}. Shorten or split "
            "this dive before generating studio audio."
        )

    payload: dict[str, object] = {
        "text": text,
        "language": args.voicebox_language,
        "personality": args.voicebox_personality,
    }
    if args.voicebox_profile:
        payload["profile"] = args.voicebox_profile
    if args.voicebox_engine:
        payload["engine"] = args.voicebox_engine

    try:
        response = curl_json_request(
            "POST",
            _voicebox_url(args, "/speak"),
            _voicebox_headers(args),
            payload,
        )
    except RuntimeError as first_error:
        # Some API-only deployments expose the older synchronous /generate
        # route. Try it once before treating the local service as unavailable.
        try:
            generate_payload = {
                "text": text,
                "language": args.voicebox_language,
                "model_size": args.voicebox_model_size,
            }
            if args.voicebox_profile:
                generate_payload["profile_id"] = args.voicebox_profile
            response = curl_json_request(
                "POST",
                _voicebox_url(args, "/generate"),
                _voicebox_headers(args),
                generate_payload,
            )
        except RuntimeError as second_error:
            raise RuntimeError(
                "Voicebox did not answer /speak or /generate. Start the "
                f"Voicebox app/server at {args.voicebox_api_url}. "
                f"First error: {first_error}; fallback error: {second_error}"
            ) from second_error

    if _write_voicebox_audio(response, out, args):
        return duration_seconds(out, text)

    generation_id = _voicebox_generation_id(response)
    # Voicebox's /generate/{id}/status is an SSE stream. The JSON-safe polling
    # surface is /history/{id}; once the row is completed, /audio/{id} serves
    # the default version's audio bytes.
    poll_url = _voicebox_url(args, f"/history/{generation_id}")
    deadline = time.monotonic() + args.voicebox_timeout
    last_status = response.get("status")
    while time.monotonic() < deadline:
        time.sleep(args.voicebox_poll_interval)
        status_payload = curl_json_request("GET", poll_url, _voicebox_headers(args))
        if _write_voicebox_audio(status_payload, out, args):
            return duration_seconds(out, text)
        last_status = status_payload.get("status") or last_status
        if last_status in {"failed", "error", "cancelled", "canceled"}:
            raise RuntimeError(f"Voicebox generation failed: {status_payload}")

    raise RuntimeError(
        f"Voicebox generation {generation_id} timed out after "
        f"{args.voicebox_timeout}s; last status={last_status!r}"
    )


def _curl_retry(args: list[str], attempts: int = 4) -> None:
    """Run curl with retries: the work-laptop TLS proxy intermittently drops
    POST bodies (curl exit 56, the same trap that kills big git pushes), so a
    transient failure must never kill a multi-hour batch. --http1.1 avoids the
    proxy's flaky HTTP/2 handling."""
    import time

    last = None
    for attempt in range(attempts):
        result = subprocess.run(
            ["curl", "-sS", "--http1.1", "--fail-with-body", *args],
            capture_output=True, text=True,
        )
        if result.returncode == 0:
            return
        last = result
        time.sleep(2 * (attempt + 1))
    raise RuntimeError(
        f"curl failed after {attempts} attempts "
        f"(exit {last.returncode}): {last.stderr.strip()[:200]}"
    )


def upload(
    key: str,
    local: Path,
    storage_path: str,
    place_id: str,
    seconds: float,
    voice_tag: str,
) -> None:
    """Push the file to the public narration bucket + stamp the dive row."""
    _curl_retry([
        "-X", "POST",
        f"{SUPABASE_URL}/storage/v1/object/narration/{storage_path}",
        "-H", f"Authorization: Bearer {key}",
        "-H", f"Content-Type: {content_type(local)}",
        "-H", "x-upsert: true",
        "--data-binary", f"@{local}",
    ])
    patch = json.dumps({
        "audio_path": storage_path,
        "audio_seconds": round(seconds),
        "audio_voice": voice_tag,
        "audio_generated_at": datetime.now(timezone.utc).isoformat(),
    })
    _curl_retry([
        "-X", "PATCH",
        f"{SUPABASE_URL}/rest/v1/dive?place_id=eq.{place_id}",
        "-H", f"apikey: {key}", "-H", f"Authorization: Bearer {key}",
        "-H", "Content-Type: application/json",
        "-H", "Prefer: return=minimal",
        "-d", patch,
    ])


def load_model(model_dir: str | None):
    import torch

    # resemble-perth's implicit audio watermarker fails to import on
    # py3.12/macOS, leaving the class as None and crashing ChatterboxTTS's
    # init. Shim a passthrough so synthesis works; when the package fixes
    # 3.12 support the real watermarker takes over automatically.
    import perth

    if getattr(perth, "PerthImplicitWatermarker", None) is None:
        class _PassthroughWatermarker:  # pragma: no cover
            def apply_watermark(self, wav, *args, **kwargs):
                return wav

        perth.PerthImplicitWatermarker = _PassthroughWatermarker
        print("note: perth watermarker unavailable on this python; using passthrough")

    from chatterbox.tts import ChatterboxTTS

    device = "mps" if torch.backends.mps.is_available() else "cpu"
    print(f"loading Chatterbox on {device}…", flush=True)
    if model_dir:
        return ChatterboxTTS.from_local(model_dir, device)
    return ChatterboxTTS.from_pretrained(device=device)


def output_extension(provider: str) -> str:
    if provider == "elevenlabs":
        return "mp3"
    if provider == "voicebox":
        return "wav"
    return "m4a"


def voice_tag(args) -> str:
    if args.provider == "elevenlabs":
        voice_id = args.voice_id or ELEVENLABS_VOICE_ID
        return f"elevenlabs:{args.eleven_model}:{voice_id}"
    if args.provider == "voicebox":
        profile = args.voicebox_profile or "client-default"
        engine = args.voicebox_engine or "profile-default"
        return f"voicebox:{engine}:{profile}"
    return CHATTERBOX_VOICE_TAG


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--city")
    parser.add_argument("--slug")
    parser.add_argument("--batch-city", help="generate every missing-audio dive in a city")
    parser.add_argument("--out", help="output file (single-place mode)")
    parser.add_argument("--upload", action="store_true",
                        help="upload to Storage + stamp the dive row")
    parser.add_argument("--provider", choices=["chatterbox", "elevenlabs", "voicebox"],
                        default=os.getenv("LORE_NARRATION_PROVIDER", "chatterbox"))

    # Chatterbox draft/local controls.
    parser.add_argument("--voice", help="reference wav (rights-cleared only)")
    parser.add_argument("--exaggeration", type=float, default=0.45)
    parser.add_argument("--cfg-weight", type=float, default=0.4)
    parser.add_argument("--model-dir", help="local Chatterbox checkpoint dir")

    # ElevenLabs studio controls. The default voice id is the Arthur candidate
    # tracked in lore/docs/15-AUDIO-NARRATION.md; override once the house voice
    # is formally selected.
    parser.add_argument("--voice-id", default=os.getenv("ELEVENLABS_VOICE_ID"))
    parser.add_argument("--eleven-model", default=os.getenv("ELEVENLABS_MODEL", ELEVENLABS_MODEL))
    parser.add_argument(
        "--eleven-output-format",
        default=os.getenv("ELEVENLABS_OUTPUT_FORMAT", ELEVENLABS_OUTPUT_FORMAT),
    )
    parser.add_argument("--stability", type=float, default=0.72)
    parser.add_argument("--similarity-boost", type=float, default=0.62)
    parser.add_argument("--style", type=float, default=0.08)
    parser.add_argument("--no-speaker-boost", action="store_true")

    # Voicebox local studio controls. Keep personality off by default so source
    # backed Lore copy is read, not rewritten.
    parser.add_argument("--voicebox-api-url", default=os.getenv("VOICEBOX_API_URL", VOICEBOX_API_URL))
    parser.add_argument("--voicebox-client-id", default=os.getenv("VOICEBOX_CLIENT_ID", VOICEBOX_CLIENT_ID))
    parser.add_argument("--voicebox-profile", default=os.getenv("VOICEBOX_PROFILE"))
    parser.add_argument("--voicebox-engine", default=os.getenv("VOICEBOX_ENGINE"))
    parser.add_argument("--voicebox-language", default=os.getenv("VOICEBOX_LANGUAGE", VOICEBOX_LANGUAGE))
    parser.add_argument("--voicebox-model-size", default=os.getenv("VOICEBOX_MODEL_SIZE", "1.7B"))
    parser.add_argument(
        "--voicebox-max-chars",
        type=int,
        default=int(os.getenv("VOICEBOX_MAX_CHARS", VOICEBOX_MAX_CHARS)),
    )
    parser.add_argument("--voicebox-timeout", type=int, default=int(os.getenv("VOICEBOX_TIMEOUT", "900")))
    parser.add_argument(
        "--voicebox-poll-interval",
        type=float,
        default=float(os.getenv("VOICEBOX_POLL_INTERVAL", "2.0")),
    )
    parser.add_argument(
        "--voicebox-personality",
        action="store_true",
        help="allow Voicebox personality processing; off keeps Lore's exact narration script",
    )
    args = parser.parse_args()

    if args.batch_city:
        rows = fetch_dives(args.batch_city, None, missing_only=True)
    elif args.city and args.slug:
        rows = fetch_dives(args.city, args.slug, missing_only=False)
    else:
        sys.exit("need --city + --slug (single) or --batch-city (batch)")
    if not rows:
        sys.exit("nothing to generate (no matching dives with narratives)")
    print(f"{len(rows)} dive(s) to narrate")

    key = service_key() if args.upload else None
    model = load_model(args.model_dir) if args.provider == "chatterbox" else None
    tag = voice_tag(args)
    print(f"provider: {args.provider} ({tag})", flush=True)

    failures: list[str] = []
    for n, row in enumerate(rows, 1):
        place = row["place"]
        slug, city = place["slug"], place["city"]
        print(f"[{n}/{len(rows)}] {place['name']} ({city}/{slug})", flush=True)
        if args.out and not args.batch_city:
            out = Path(args.out).expanduser()
        else:
            out = Path("out") / city / f"{slug}.{output_extension(args.provider)}"
        # One dive must never kill a multi-hour batch: synthesis or upload
        # failures are logged + skipped, and the resumable batch (missing-only)
        # picks them up on the next run.
        try:
            text = row["narrative"].strip()
            if args.provider == "elevenlabs":
                seconds = synthesize_elevenlabs(text, out, args)
            elif args.provider == "voicebox":
                seconds = synthesize_voicebox(text, out, args)
            else:
                seconds = synthesize_chatterbox(model, text, out,
                                                args.voice, args.exaggeration, args.cfg_weight)
            print(f"  ✓ {out} ({seconds:.0f}s, {out.stat().st_size // 1024} KB)", flush=True)
            if key:
                storage_path = f"{city}/{slug}.{output_extension(args.provider)}"
                upload(key, out, storage_path, row["place_id"], seconds, tag)
                print(f"  ↑ narration/{storage_path} + dive row stamped", flush=True)
        except Exception as error:  # noqa: BLE001 — batch resilience by design
            failures.append(f"{city}/{slug}")
            print(f"  ✗ SKIPPED {city}/{slug}: {error}", flush=True)

    if failures:
        print(f"\n{len(failures)} dive(s) failed and were skipped — rerun the "
              f"batch to retry them:\n  " + "\n  ".join(failures), flush=True)


if __name__ == "__main__":
    main()

# Lore Narration

This tool creates the studio audio files that make Lore+ narration feel like a
premium guide instead of on-device speech.

## Production Path

Use Voicebox for the no-cost local studio path when the Voicebox app/server is
running:

```sh
mkdir -p "$HOME/Library/Application Support/LoreVoicebox"
/Applications/Voicebox.app/Contents/MacOS/voicebox-server \
  --host 127.0.0.1 \
  --port 17493 \
  --data-dir "$HOME/Library/Application Support/LoreVoicebox"
```

In another shell:

```sh
cd /Users/dron/Projects/lore-ios/tools/narration
export LORE_NARRATION_PROVIDER=voicebox
export VOICEBOX_API_URL=http://127.0.0.1:17493
export VOICEBOX_CLIENT_ID=lore-narration
export VOICEBOX_PROFILE="Lore House Narrator"
export VOICEBOX_ENGINE=kokoro
.venv/bin/python generate.py --provider voicebox --city nyc --slug mcsorleys-old-ale-house --out /tmp/lore-sample.wav
```

`kokoro` is the quick local smoke-test engine. Move to `qwen` for premium batch
work only after the model is downloaded and the workstation has enough free disk
for the larger local weights.

Voicebox can also bind Lore's client id to a local profile so queue runs do not
need `VOICEBOX_PROFILE` every time:

```sh
curl -X PUT http://127.0.0.1:17493/mcp/bindings \
  --json '{"client_id":"lore-narration","label":"Lore narration pipeline","profile_id":"<voicebox-profile-id>","default_engine":"kokoro","default_personality":false}'
```

Use `--upload` only after listening approval for the voice/profile:

```sh
.venv/bin/python generate.py --provider voicebox --batch-city nyc --upload
```

ElevenLabs remains available as the paid fallback when
`ELEVENLABS_API_KEY` is available:

```sh
cd /Users/dron/Projects/lore-ios/tools/narration
.venv/bin/python generate.py --provider elevenlabs --batch-city nyc --upload
```

The script writes finished files to Supabase Storage under
`narration/<city>/<slug>.<provider-format>` and stamps the matching `dive` row:

- `audio_path`
- `audio_seconds`
- `audio_voice`
- `audio_generated_at`

The iOS app sees `audio_path`, plays the hosted studio file, and only falls back
to on-device speech when a city has not been generated yet or playback fails.

## Provider Rules

- Keep provider keys on the workstation or CI. Never embed TTS keys in the iOS
  app.
- Voicebox is localhost-only studio tooling. Keep it out of the app binary; the
  app consumes the finished hosted narration files already stamped in `dive`.
- Keep Voicebox `personality` off for Lore production reads unless editorially
  approved. Source-backed narration text should be read, not rewritten.
- `VOICEBOX_PROFILE` should name a rights-cleared house narrator profile.
- `VOICEBOX_ENGINE` may select a local Voicebox engine such as `kokoro` for
  smoke tests or `qwen` for premium batches when disk/model setup is ready.
- `VOICEBOX_API_URL` defaults to `http://127.0.0.1:17493`.
- `ELEVENLABS_VOICE_ID` overrides the current Arthur house-voice candidate.
- `ELEVENLABS_MODEL` defaults to `eleven_multilingual_v2`.
- `ELEVENLABS_OUTPUT_FORMAT` defaults to `mp3_44100_128`.
- The Supabase Management API PAT belongs at `~/.config/lore/supabase.token`.

## Local Drafts

Chatterbox remains available for no-cost draft runs:

```sh
.venv/bin/python generate.py --provider chatterbox --city austin --slug texas-state-capitol --out /tmp/sample.m4a
```

For queued city work, `run-queue.sh` picks Voicebox when the local server
answers and either `VOICEBOX_PROFILE` or a `lore-narration` client binding is
available, then ElevenLabs when `ELEVENLABS_API_KEY` is loaded, and otherwise
falls back to Chatterbox.

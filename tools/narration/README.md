# Lore Narration

This tool creates the studio audio files that make Lore+ narration feel like a
premium guide instead of on-device speech.

## Production Path

Use ElevenLabs for the flagship voice when `ELEVENLABS_API_KEY` is available:

```sh
cd /Users/dron/Projects/lore-ios/tools/narration
.venv/bin/python generate.py --provider elevenlabs --batch-city nyc --upload
```

The script writes finished files to Supabase Storage under
`narration/<city>/<slug>.mp3` and stamps the matching `dive` row:

- `audio_path`
- `audio_seconds`
- `audio_voice`
- `audio_generated_at`

The iOS app sees `audio_path`, plays the hosted studio file, and only falls back
to on-device speech when a city has not been generated yet or playback fails.

## Provider Rules

- Keep provider keys on the workstation or CI. Never embed TTS keys in the iOS
  app.
- `ELEVENLABS_VOICE_ID` overrides the current Arthur house-voice candidate.
- `ELEVENLABS_MODEL` defaults to `eleven_multilingual_v2`.
- `ELEVENLABS_OUTPUT_FORMAT` defaults to `mp3_44100_128`.
- The Supabase Management API PAT belongs at `~/.config/lore/supabase.token`.

## Local Drafts

Chatterbox remains available for no-cost draft runs:

```sh
.venv/bin/python generate.py --provider chatterbox --city austin --slug texas-state-capitol --out /tmp/sample.m4a
```

For queued city work, `run-queue.sh` picks ElevenLabs when `ELEVENLABS_API_KEY`
is loaded and otherwise falls back to Chatterbox.

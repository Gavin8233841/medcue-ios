# OpenAI Image Local API

This workspace has a local OpenAI image generation path for Codex threads that need `gpt-image-2`.

## Credential

Store the API key in macOS Keychain:

```bash
tools/install-openai-image-key.sh
```

The key is stored as:

- Service: `appcontest-openai-image`
- Account: `openai-image-api`

The tools read `OPENAI_API_KEY` first. If it is not set, they read the macOS Keychain item above.
On macOS, the `*.sh` wrappers also auto-detect the current system proxy from `scutil --proxy` and pass it into Node when needed.

Do not write the real API key into source files, docs, tests, build logs, screenshots, or app bundle resources.

## One-Off Image Generation

```bash
tools/openai-image-generate.sh \
  --prompt "A clean product mockup of a medication reminder app on an iPhone, realistic lighting" \
  --output artifacts/openai-images/medication-reminder.png
```

Optional passthrough fields:

```bash
tools/openai-image-generate.sh \
  --prompt "A refined app icon concept for medication adherence" \
  --size 1024x1024 \
  --quality high \
  --output-format png
```

Generated images are written under `artifacts/openai-images/`, which is already ignored by git.

## Local API Path

Start the local proxy:

```bash
tools/openai-image-api-server.sh
```

Then call the OpenAI-compatible local path:

```bash
curl -sS http://127.0.0.1:8787/v1/images/generations \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "gpt-image-2",
    "prompt": "A clean product mockup of a medication reminder app on an iPhone"
  }'
```

The local server binds to `127.0.0.1` by default and forwards requests to:

```text
https://api.openai.com/v1/images/generations
```

It returns the OpenAI JSON response without printing credentials.

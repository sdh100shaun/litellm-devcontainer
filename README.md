# litellm-devcontainer

A [Dev Container Feature](https://containers.dev/implementors/features/) that installs [LiteLLM](https://github.com/BerriAI/litellm) and [Ollama](https://ollama.com/) as in-container services, giving any devcontainer a unified, OpenAI-compatible AI gateway. Instead of configuring each AI tool separately, you point everything at a single `http://localhost:4000/v1` endpoint. Local models run via Ollama with zero API costs; optional pass-through stanzas for AWS Bedrock, Anthropic, and OpenAI let you switch providers by changing one environment variable.

---

## Quick Start

Add to your `devcontainer.json`:

```json
{
  "name": "My Project",
  "image": "mcr.microsoft.com/devcontainers/base:ubuntu",
  "features": {
    "ghcr.io/sdh100shaun/devcontainer-features/litellm-ollama:1": {
      "ollamaModel": "qwen2.5-coder:7b",
      "litellmPort": "4000"
    }
  },
  "forwardPorts": [4000, 11434],
  "postStartCommand": "start-ai-services.sh"
}
```

After the container starts, LiteLLM is reachable at `http://localhost:4000/v1` and Ollama at `http://localhost:11434`.

---

## Options

| Option           | Type    | Default            | Description                                                                     |
|------------------|---------|--------------------|---------------------------------------------------------------------------------|
| `ollamaModel`    | string  | `qwen2.5-coder:7b` | Model to pull on start. Leave empty to skip auto-pull.                          |
| `litellmVersion` | string  | `latest`           | pip version specifier, e.g. `1.40.0`. Defaults to the latest release.          |
| `litellmPort`    | string  | `4000`             | Port the LiteLLM proxy listens on.                                              |
| `enableBedrock`  | boolean | `false`            | Add AWS Bedrock models. Requires `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`. |
| `enableAnthropic`| boolean | `false`            | Add Anthropic models. Requires `ANTHROPIC_API_KEY`.                             |
| `enableOpenAI`   | boolean | `false`            | Add OpenAI models. Requires `OPENAI_API_KEY`.                                   |

### Environment variables injected automatically

| Variable           | Value                             |
|--------------------|-----------------------------------|
| `LITELLM_BASE_URL` | `http://localhost:<litellmPort>`  |
| `OPENAI_API_BASE`  | `http://localhost:<litellmPort>`  |
| `OLLAMA_HOST`      | `http://localhost:11434`          |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Dev Container                                                  │
│                                                                 │
│  ┌────────────┐   OpenAI API    ┌─────────────────────────┐    │
│  │ Your App   │ ──────────────► │  LiteLLM Proxy :4000    │    │
│  │ (any tool) │                 │  /v1/chat/completions   │    │
│  └────────────┘                 └────────────┬────────────┘    │
│                                              │                  │
│                         ┌────────────────────┼─────────────┐   │
│                         │                    │             │   │
│                         ▼                    ▼             ▼   │
│                  ┌────────────┐   ┌──────────────┐  ┌──────────┐
│                  │   Ollama   │   │  Anthropic   │  │  OpenAI  │
│                  │  :11434    │   │  API (cloud) │  │  (cloud) │
│                  │  (local)   │   └──────────────┘  └──────────┘
│                  └────────────┘                               │
│                       │                              ┌────────┐│
│               qwen2.5-coder:7b                       │Bedrock ││
│               mistral, phi3, …                       │(cloud) ││
│                                                      └────────┘│
└─────────────────────────────────────────────────────────────────┘

Host machine:
  localhost:4000  ──► forwarded from container (forwardPorts)
  localhost:11434 ──► forwarded from container (forwardPorts)
```

---

## Using from the Host

Forward ports in `devcontainer.json` (shown above) then point any OpenAI-compatible tool at `http://localhost:4000/v1`:

### Cursor

Settings → Models → OpenAI API Compatible:
```
Base URL : http://localhost:4000/v1
API Key  : sk-devcontainer   (value of LITELLM_MASTER_KEY)
```

### Continue.dev (`~/.continue/config.json`)

```json
{
  "models": [
    {
      "title": "Local (qwen2.5-coder)",
      "provider": "openai",
      "model": "qwen2.5-coder:7b",
      "apiBase": "http://localhost:4000/v1",
      "apiKey": "sk-devcontainer"
    }
  ]
}
```

### Any OpenAI SDK

```python
import openai

client = openai.OpenAI(
    base_url="http://localhost:4000/v1",
    api_key="sk-devcontainer",
)
response = client.chat.completions.create(
    model="default",          # routes to local Ollama model
    messages=[{"role": "user", "content": "Hello!"}],
)
```

---

## Cloud Provider Examples

### With Anthropic

```json
{
  "features": {
    "ghcr.io/sdh100shaun/devcontainer-features/litellm-ollama:1": {
      "enableAnthropic": true
    }
  },
  "containerEnv": {
    "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}"
  }
}
```

### With AWS Bedrock

```json
{
  "features": {
    "ghcr.io/sdh100shaun/devcontainer-features/litellm-ollama:1": {
      "enableBedrock": true
    }
  },
  "containerEnv": {
    "AWS_ACCESS_KEY_ID": "${localEnv:AWS_ACCESS_KEY_ID}",
    "AWS_SECRET_ACCESS_KEY": "${localEnv:AWS_SECRET_ACCESS_KEY}",
    "AWS_REGION": "eu-west-2"
  }
}
```

---

## Docker Compose Variant

For teams that prefer Compose, use `.devcontainer/docker-compose.yml`:

```bash
# Edit .devcontainer/litellm-config.yaml to add cloud providers, then:
docker compose -f .devcontainer/docker-compose.yml up -d
```

The `app` service starts only after LiteLLM passes its health check (`depends_on: condition: service_healthy`).

---

## Troubleshooting

### Slow first start (model download)

The first `start-ai-services.sh` invocation pulls the Ollama model, which can be several gigabytes. Subsequent starts are fast because the model is cached in `~/.ollama`.

To persist models across container rebuilds, add a volume mount in `devcontainer.json`:

```json
"mounts": [
  "source=ollama-models,target=/root/.ollama,type=volume"
]
```

### GPU passthrough

The feature works CPU-only by default. To enable GPU acceleration add to `devcontainer.json`:

```json
"hostRequirements": { "gpu": "optional" },
"runArgs": ["--gpus=all"]
```

Apple Silicon: Ollama detects Metal automatically when running natively; GPU passthrough is not supported inside Docker on macOS.

### Port conflicts

If port 4000 or 11434 is already in use, change the port via the `litellmPort` option and update `forwardPorts` accordingly.

### Checking service logs

Both services write logs to `/tmp/litellm-ollama-logs/` inside the container:

```bash
tail -f /tmp/litellm-ollama-logs/ollama.log
tail -f /tmp/litellm-ollama-logs/litellm.log
```

### Services didn't start

`start-ai-services.sh` must be invoked via `postStartCommand`. If it's missing from your `devcontainer.json`, add:

```json
"postStartCommand": "start-ai-services.sh"
```

---

## Development

See [`plan.md`](./plan.md) for the full specification and deliverables checklist.

```bash
# TypeScript tooling
npm install
npm run check          # biome lint + format check

# Shell script validation
shellcheck --shell=sh  src/litellm-ollama/install.sh
shellcheck --shell=bash src/litellm-ollama/start-ai-services.sh

# Validate bats test file syntax
bats --count test/litellm-ollama/test.sh

# Run feature tests locally (requires devcontainer CLI)
devcontainer features test \
  --base-image mcr.microsoft.com/devcontainers/base:ubuntu \
  --features src/litellm-ollama \
  --test-folder test/litellm-ollama
```

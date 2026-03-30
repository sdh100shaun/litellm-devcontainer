# Plan: LiteLLM + Ollama Dev Container Feature

## Goal

Build a publishable [Dev Container Feature](https://containers.dev/implementors/features/) that gives any devcontainer a unified LiteLLM gateway backed by a local Ollama sidecar, with optional pass-through to AWS Bedrock, Anthropic, and OpenAI. Developers get a single `LITELLM_BASE_URL` endpoint — every AI-aware tool in the container just works.

---

## Repository Layout

```
devcontainer-features/
├── README.md
├── LICENSE
├── .github/
│   └── workflows/
│       ├── release.yml          # OCI publish on tag
│       └── test.yml             # devcontainer features test on PR
├── src/
│   └── litellm-ollama/
│       ├── devcontainer-feature.json
│       ├── install.sh           # runs inside the devcontainer at build time
│       ├── start-ai-services.sh # startup orchestration script
│       └── README.md
└── test/
    └── litellm-ollama/
        ├── test.sh              # bats tests
        └── scenarios.json       # devcontainer features test matrix
```

---

## Feature Specification (`devcontainer-feature.json`)

```json
{
  "id": "litellm-ollama",
  "version": "1.0.0",
  "name": "LiteLLM + Ollama Gateway",
  "description": "Installs a LiteLLM proxy and Ollama daemon as in-container services. Exposes a unified OpenAI-compatible API at http://localhost:4000.",
  "options": {
    "ollamaModel": {
      "type": "string",
      "default": "qwen2.5-coder:7b",
      "description": "Ollama model to pull on container start (leave empty to skip auto-pull)."
    },
    "litellmVersion": {
      "type": "string",
      "default": "latest",
      "description": "pip version specifier for litellm, e.g. '1.40.0' or 'latest'."
    },
    "enableBedrock": {
      "type": "boolean",
      "default": false,
      "description": "Add AWS Bedrock models to the LiteLLM config (requires AWS env vars at runtime)."
    },
    "enableAnthropic": {
      "type": "boolean",
      "default": false,
      "description": "Add Anthropic models to the LiteLLM config (requires ANTHROPIC_API_KEY at runtime)."
    },
    "enableOpenAI": {
      "type": "boolean",
      "default": false,
      "description": "Add OpenAI models to the LiteLLM config (requires OPENAI_API_KEY at runtime)."
    },
    "litellmPort": {
      "type": "string",
      "default": "4000",
      "description": "Port for the LiteLLM proxy."
    }
  },
  "containerEnv": {
    "LITELLM_BASE_URL": "http://localhost:${litellmPort}",
    "OPENAI_API_BASE": "http://localhost:${litellmPort}",
    "OLLAMA_HOST": "http://localhost:11434"
  },
  "installsAfter": ["ghcr.io/devcontainers/features/python"]
}
```

---

## `install.sh` — Implementation Steps

The script runs as root inside the container at build time. It must be idempotent.

### Step 1 — Detect OS and package manager
- Support Debian/Ubuntu (apt) and Alpine (apk).
- Abort with a clear error on unsupported distros.

### Step 2 — Install Ollama
- Use the official install script: `curl -fsSL https://ollama.com/install.sh | sh`
- Verify with `ollama --version`.

### Step 3 — Install LiteLLM
- `pip install --no-cache-dir "litellm[proxy]==${LITELLM_VERSION}"` (or `latest`).
- Verify with `litellm --version`.

### Step 4 — Generate `litellm-config.yaml`
Write to `/etc/litellm/config.yaml`. Build the model list dynamically based on feature options.

### Step 5 — Install startup script
Copy `start-ai-services.sh` to `/usr/local/bin/` and make it executable.

### Step 6 — Write environment defaults
Write `/etc/profile.d/litellm-ollama.sh` with LITELLM_PORT, OLLAMA_MODEL, etc.

---

## Constraints and Gotchas

| Issue                                        | Mitigation                                                            |
|----------------------------------------------|-----------------------------------------------------------------------|
| Ollama needs GPU drivers for acceleration    | Feature works CPU-only by default; document GPU passthrough separately |
| Model pull on first start is slow (multi-GB) | Use a volume mount for `~/.ollama` so models survive rebuilds          |
| No init system in minimal images             | The `start-ai-services.sh` wrapper approach works without systemd      |
| LiteLLM and Ollama both bind localhost       | `forwardPorts` exposes them for host tooling (Cursor, Copilot, etc.)   |
| Secret keys in compose env                   | Always source from `.env` file, never commit; document in README       |
| Feature version pinning                      | Encourage `1` (minor-floating) not `1.0.0` in usage examples           |

---

## Deliverables Checklist

- [x] `src/litellm-ollama/devcontainer-feature.json`
- [x] `src/litellm-ollama/install.sh` (idempotent, POSIX sh, shellcheck clean)
- [x] `src/litellm-ollama/start-ai-services.sh` (bash, shellcheck clean)
- [x] `src/litellm-ollama/README.md` with usage examples and option table
- [x] `test/litellm-ollama/test.sh` (bats suite, 21 tests — well over min 8)
- [x] `test/litellm-ollama/scenarios.json` (5 scenarios)
- [x] `.devcontainer/docker-compose.yml` compose variant (service_healthy depends_on)
- [x] `.devcontainer/litellm-config.yaml` compose config template
- [x] `.github/workflows/release.yml` OCI publish workflow (semver tags)
- [x] `.github/workflows/test.yml` PR test workflow (shellcheck + bats + scenarios)
- [x] `README.md` top-level with quick-start and architecture diagram (ASCII)

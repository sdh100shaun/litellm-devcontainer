# LiteLLM + Ollama Gateway — Dev Container Feature

Installs [LiteLLM](https://github.com/BerriAI/litellm) proxy and [Ollama](https://ollama.com/) as in-container services. Exposes a unified OpenAI-compatible API at `http://localhost:4000`.

See the [top-level README](../../README.md) for the full usage guide, architecture diagram, and troubleshooting section.

## Options

| Option           | Type    | Default            | Description                                                           |
|------------------|---------|--------------------|-----------------------------------------------------------------------|
| `ollamaModel`    | string  | `qwen2.5-coder:7b` | Ollama model to pull on container start. Empty = skip auto-pull.      |
| `litellmVersion` | string  | `latest`           | pip version specifier for litellm, e.g. `1.40.0`.                    |
| `litellmPort`    | string  | `4000`             | Port the LiteLLM proxy listens on.                                    |
| `enableBedrock`  | boolean | `false`            | Add AWS Bedrock models (requires AWS env vars).                       |
| `enableAnthropic`| boolean | `false`            | Add Anthropic models (requires `ANTHROPIC_API_KEY`).                  |
| `enableOpenAI`   | boolean | `false`            | Add OpenAI models (requires `OPENAI_API_KEY`).                        |

## Usage

```json
{
  "features": {
    "ghcr.io/sdh100shaun/devcontainer-features/litellm-ollama:1": {
      "ollamaModel": "qwen2.5-coder:7b",
      "enableAnthropic": true
    }
  },
  "forwardPorts": [4000, 11434],
  "postStartCommand": "start-ai-services.sh",
  "containerEnv": {
    "ANTHROPIC_API_KEY": "${localEnv:ANTHROPIC_API_KEY}"
  }
}
```

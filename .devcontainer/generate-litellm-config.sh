#!/bin/sh
# .devcontainer/generate-litellm-config.sh
# Purpose: Generate /app/generated-config.yaml at container startup based on
#          which API keys are present in the environment, then exec LiteLLM.
#
# This script is the entrypoint for the litellm service in docker-compose.yml.
# It replaces the static litellm-config.yaml mount: providers are toggled by
# setting (or unsetting) their API key environment variables in .env —
# no YAML editing or uncommentation required.
#
# Toggle logic:
#   OPENAI_API_KEY set     → OpenAI models included
#   ANTHROPIC_API_KEY set  → Anthropic models included
#   AWS_ACCESS_KEY_ID set  → AWS Bedrock models included
#   (none set)             → Ollama-only, zero cloud cost
#
# Design decision: Using env-var presence (not an explicit boolean flag) keeps
# the compose workflow consistent with how developers already manage secrets —
# add a key to .env, restart the service, it works.

set -eu

OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5-coder:7b}"
OLLAMA_HOST="${OLLAMA_HOST:-http://ollama:11434}"
LITELLM_PORT="${LITELLM_PORT:-4000}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-devcontainer}"
AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-eu-west-2}"
OUTPUT="/app/generated-config.yaml"

log() { echo "[litellm-config-gen] $*"; }

log "Generating LiteLLM config based on environment..."

# ---------------------------------------------------------------------------
# Base config — Ollama local model always present
# ---------------------------------------------------------------------------
cat > "${OUTPUT}" << YAML
model_list:
  # Local Ollama model — always available (zero cost, no key required)
  - model_name: "${OLLAMA_MODEL}"
    litellm_params:
      model: "ollama/${OLLAMA_MODEL}"
      api_base: "${OLLAMA_HOST}"

  - model_name: "default"
    litellm_params:
      model: "ollama/${OLLAMA_MODEL}"
      api_base: "${OLLAMA_HOST}"

YAML

# ---------------------------------------------------------------------------
# OpenAI — toggled by presence of OPENAI_API_KEY
# ---------------------------------------------------------------------------
if [ -n "${OPENAI_API_KEY:-}" ]; then
    log "  OPENAI_API_KEY detected  → adding OpenAI models (gpt-4o, gpt-4o-mini)"
    cat >> "${OUTPUT}" << YAML
  - model_name: "gpt-4o"
    litellm_params:
      model: "openai/gpt-4o"
      api_key: "os.environ/OPENAI_API_KEY"

  - model_name: "gpt-4o-mini"
    litellm_params:
      model: "openai/gpt-4o-mini"
      api_key: "os.environ/OPENAI_API_KEY"

YAML
else
    log "  OPENAI_API_KEY not set   → skipping OpenAI models"
fi

# ---------------------------------------------------------------------------
# Anthropic — toggled by presence of ANTHROPIC_API_KEY
# ---------------------------------------------------------------------------
if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    log "  ANTHROPIC_API_KEY detected → adding Anthropic models (claude-sonnet, claude-haiku)"
    cat >> "${OUTPUT}" << YAML
  - model_name: "claude-sonnet"
    litellm_params:
      model: "anthropic/claude-sonnet-4-6"
      api_key: "os.environ/ANTHROPIC_API_KEY"

  - model_name: "claude-haiku"
    litellm_params:
      model: "anthropic/claude-haiku-4-5-20251001"
      api_key: "os.environ/ANTHROPIC_API_KEY"

YAML
else
    log "  ANTHROPIC_API_KEY not set  → skipping Anthropic models"
fi

# ---------------------------------------------------------------------------
# AWS Bedrock — toggled by presence of AWS_ACCESS_KEY_ID
# ---------------------------------------------------------------------------
if [ -n "${AWS_ACCESS_KEY_ID:-}" ]; then
    log "  AWS_ACCESS_KEY_ID detected → adding Bedrock models (region: ${AWS_DEFAULT_REGION})"
    cat >> "${OUTPUT}" << YAML
  - model_name: "bedrock-claude-sonnet"
    litellm_params:
      model: "bedrock/anthropic.claude-sonnet-4-5"
      aws_region_name: "${AWS_DEFAULT_REGION}"

  - model_name: "bedrock-claude-haiku"
    litellm_params:
      model: "bedrock/anthropic.claude-3-5-haiku-20241022-v1:0"
      aws_region_name: "${AWS_DEFAULT_REGION}"

YAML
else
    log "  AWS_ACCESS_KEY_ID not set  → skipping Bedrock models"
fi

# ---------------------------------------------------------------------------
# Global LiteLLM settings
# ---------------------------------------------------------------------------
cat >> "${OUTPUT}" << YAML
litellm_settings:
  drop_params: true
  request_timeout: 120

general_settings:
  master_key: "${LITELLM_MASTER_KEY}"
YAML

log "Config written to ${OUTPUT}:"
log "---"
sed 's/^/  /' "${OUTPUT}"
log "---"

# Hand off to LiteLLM — exec replaces this shell process so signals propagate
log "Starting LiteLLM on port ${LITELLM_PORT}..."
exec litellm \
    --config "${OUTPUT}" \
    --port "${LITELLM_PORT}" \
    --host "0.0.0.0"

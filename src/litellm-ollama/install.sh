#!/bin/sh
# install.sh
# Purpose: Dev Container Feature install script for litellm-ollama.
#
# This script is executed as root inside the container IMAGE BUILD phase
# (not at runtime). It installs Ollama and LiteLLM, generates
# /etc/litellm/config.yaml based on feature options, and places
# start-ai-services.sh on PATH.
#
# Relation to feature: This is the "install" entrypoint defined in
# devcontainer-feature.json. The devcontainer runner calls it once
# during `docker build`.
#
# Idempotency: Every installation step is guarded by a presence check so
# running the script twice produces no errors and no duplicate config.
#
# Supported base images: ubuntu:22.04, ubuntu:24.04, debian:bookworm,
#                        alpine:3.x (apk-based).
#
# Feature options are injected as UPPERCASE environment variables by the
# devcontainer runner. camelCase → UPPERCASE concatenation:
#   ollamaModel    → OLLAMAMODEL
#   litellmVersion → LITELLMVERSION
#   enableBedrock  → ENABLEBEDROCK
#   enableAnthropic→ ENABLEANTHROPIC
#   enableOpenAI   → ENABLEOPENAI
#   litellmPort    → LITELLMPORT

set -e

# ---------------------------------------------------------------------------
# Resolve paths
# ---------------------------------------------------------------------------
FEATURE_DIR="$(cd "$(dirname "$0")" && pwd)"
LITELLM_CONFIG_DIR="/etc/litellm"
LITELLM_CONFIG_FILE="${LITELLM_CONFIG_DIR}/config.yaml"
PROFILE_FILE="/etc/profile.d/litellm-ollama.sh"

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
log() {
    echo "[litellm-ollama] $*"
}

err() {
    echo "[litellm-ollama] ERROR: $*" >&2
    exit 1
}

# ---------------------------------------------------------------------------
# Resolve feature options (with safe defaults)
# ---------------------------------------------------------------------------
OLLAMA_MODEL="${OLLAMAMODEL:-qwen2.5-coder:7b}"
LITELLM_VERSION="${LITELLMVERSION:-latest}"
ENABLE_BEDROCK="${ENABLEBEDROCK:-false}"
ENABLE_ANTHROPIC="${ENABLEANTHROPIC:-false}"
ENABLE_OPENAI="${ENABLEOPENAI:-false}"
LITELLM_PORT="${LITELLMPORT:-4000}"

log "================================================="
log "  LiteLLM + Ollama Dev Container Feature v1.0.0"
log "================================================="
log "  ollamaModel    = ${OLLAMA_MODEL}"
log "  litellmVersion = ${LITELLM_VERSION}"
log "  litellmPort    = ${LITELLM_PORT}"
log "  enableBedrock  = ${ENABLE_BEDROCK}"
log "  enableAnthropic= ${ENABLE_ANTHROPIC}"
log "  enableOpenAI   = ${ENABLE_OPENAI}"
log "================================================="

# ---------------------------------------------------------------------------
# Step 1: Detect OS and package manager
# ---------------------------------------------------------------------------
log "Step 1: Detecting OS..."

if [ -f /etc/os-release ]; then
    # shellcheck source=/dev/null
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_VERSION="${VERSION_ID:-unknown}"
    log "Detected: ${PRETTY_NAME:-${OS_ID} ${OS_VERSION}}"
else
    OS_ID="unknown"
    OS_VERSION="unknown"
    log "WARNING: /etc/os-release not found; assuming Debian-like."
fi

# Detect package manager once; all install helpers use this variable.
if command -v apt-get > /dev/null 2>&1; then
    PKG_MANAGER="apt"
elif command -v apk > /dev/null 2>&1; then
    PKG_MANAGER="apk"
else
    err "Unsupported package manager. Only apt (Debian/Ubuntu) and apk (Alpine) are supported."
fi
log "Package manager: ${PKG_MANAGER}"

# ---------------------------------------------------------------------------
# Step 2: Install system dependencies (curl, python3, pip)
# ---------------------------------------------------------------------------
log "Step 2: Installing system dependencies..."

install_apt_deps() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y -q 2>&1 | tail -5
    apt-get install -y -q --no-install-recommends \
        curl \
        ca-certificates \
        python3 \
        python3-pip \
        python3-venv
}

install_apk_deps() {
    apk add --no-cache \
        curl \
        ca-certificates \
        python3 \
        py3-pip
}

# Only install if any required tool is missing (idempotency guard)
if ! command -v curl > /dev/null 2>&1 || ! command -v python3 > /dev/null 2>&1; then
    log "Installing missing dependencies..."
    case "${PKG_MANAGER}" in
        apt) install_apt_deps ;;
        apk) install_apk_deps ;;
    esac
    log "System dependencies installed."
else
    log "System dependencies already present; skipping."
fi

# ---------------------------------------------------------------------------
# Step 3: Install Ollama
# ---------------------------------------------------------------------------
log "Step 3: Installing Ollama..."

if ! command -v ollama > /dev/null 2>&1; then
    log "Downloading and running Ollama installer..."
    curl -fsSL https://ollama.com/install.sh | sh
    log "Ollama installed: $(ollama --version 2>/dev/null || echo 'installed')"
else
    log "Ollama already installed ($(ollama --version 2>/dev/null || echo 'version unknown')); skipping."
fi

# ---------------------------------------------------------------------------
# Step 4: Install LiteLLM proxy
# ---------------------------------------------------------------------------
log "Step 4: Installing LiteLLM proxy..."

if ! command -v litellm > /dev/null 2>&1; then
    # Determine the pip install specifier.
    # Design decision: "latest" maps to no version pin; any other value is
    # used as-is so users can pin to e.g. "1.40.0".
    if [ "${LITELLM_VERSION}" = "latest" ]; then
        PIP_SPEC="litellm[proxy]"
    else
        PIP_SPEC="litellm[proxy]==${LITELLM_VERSION}"
    fi

    log "Installing: ${PIP_SPEC}"

    # Try system pip first; fall back to venv for PEP 668 (externally managed) envs.
    if python3 -m pip install --no-cache-dir "${PIP_SPEC}" --break-system-packages -q 2>/dev/null; then
        log "LiteLLM installed via system pip."
    elif python3 -m pip install --no-cache-dir "${PIP_SPEC}" -q 2>/dev/null; then
        log "LiteLLM installed via system pip (legacy)."
    else
        log "System pip install failed; falling back to virtual environment..."
        VENV_DIR="/usr/local/share/litellm-venv"
        python3 -m venv "${VENV_DIR}"
        "${VENV_DIR}/bin/pip" install --no-cache-dir "${PIP_SPEC}" -q
        # Create a thin wrapper so 'litellm' is on PATH
        ln -sf "${VENV_DIR}/bin/litellm" /usr/local/bin/litellm
        log "LiteLLM installed in venv at ${VENV_DIR}."
    fi

    log "LiteLLM installed: $(litellm --version 2>/dev/null || echo 'installed')"
else
    log "LiteLLM already installed ($(litellm --version 2>/dev/null || echo 'version unknown')); skipping."
fi

# ---------------------------------------------------------------------------
# Step 5: Generate /etc/litellm/config.yaml
# ---------------------------------------------------------------------------
log "Step 5: Generating ${LITELLM_CONFIG_FILE}..."

# Create the config directory if it does not exist
mkdir -p "${LITELLM_CONFIG_DIR}"

# Design decision: Config is written at BUILD time (not runtime) so it is
# visible on the filesystem for inspection. Users can override by mounting
# their own file:
#   "mounts": ["source=/path/to/config.yaml,target=/etc/litellm/config.yaml,type=bind"]
#
# We always overwrite on rebuild to pick up any option changes.

# Write the base config (always-present Ollama local model + default alias)
cat > "${LITELLM_CONFIG_FILE}" << YAML_EOF
# /etc/litellm/config.yaml
# Generated by the litellm-ollama devcontainer feature install.sh.
# Rebuild the container to regenerate with updated options.

model_list:
  # Local Ollama model — always available regardless of feature options.
  - model_name: "${OLLAMA_MODEL}"
    litellm_params:
      model: "ollama/${OLLAMA_MODEL}"
      api_base: "http://localhost:11434"

  # 'default' alias always routes to the local Ollama model.
  - model_name: "default"
    litellm_params:
      model: "ollama/${OLLAMA_MODEL}"
      api_base: "http://localhost:11434"

YAML_EOF

# Conditionally append provider stanzas.
# Design decision: Append rather than template-replace so each stanza can
# include an explanatory comment and the file structure stays readable.

if [ "${ENABLE_OPENAI}" = "true" ]; then
    log "  Appending OpenAI stanza (enableOpenAI=true)..."
    cat >> "${LITELLM_CONFIG_FILE}" << YAML_EOF
  # OpenAI — enabled via enableOpenAI option.
  # Requires OPENAI_API_KEY environment variable at runtime.
  - model_name: "gpt-4o"
    litellm_params:
      model: "openai/gpt-4o"
      api_key: "os.environ/OPENAI_API_KEY"

  - model_name: "gpt-4o-mini"
    litellm_params:
      model: "openai/gpt-4o-mini"
      api_key: "os.environ/OPENAI_API_KEY"

YAML_EOF
fi

if [ "${ENABLE_ANTHROPIC}" = "true" ]; then
    log "  Appending Anthropic stanza (enableAnthropic=true)..."
    cat >> "${LITELLM_CONFIG_FILE}" << YAML_EOF
  # Anthropic — enabled via enableAnthropic option.
  # Requires ANTHROPIC_API_KEY environment variable at runtime.
  - model_name: "claude-sonnet"
    litellm_params:
      model: "anthropic/claude-sonnet-4-6"
      api_key: "os.environ/ANTHROPIC_API_KEY"

  - model_name: "claude-haiku"
    litellm_params:
      model: "anthropic/claude-haiku-4-5-20251001"
      api_key: "os.environ/ANTHROPIC_API_KEY"

YAML_EOF
fi

if [ "${ENABLE_BEDROCK}" = "true" ]; then
    log "  Appending AWS Bedrock stanza (enableBedrock=true)..."
    cat >> "${LITELLM_CONFIG_FILE}" << YAML_EOF
  # AWS Bedrock — enabled via enableBedrock option.
  # Requires AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION at runtime.
  - model_name: "bedrock-claude-sonnet"
    litellm_params:
      model: "bedrock/anthropic.claude-sonnet-4-5"
      aws_region_name: "eu-west-2"

  - model_name: "bedrock-claude-haiku"
    litellm_params:
      model: "bedrock/anthropic.claude-3-5-haiku-20241022-v1:0"
      aws_region_name: "eu-west-2"

YAML_EOF
fi

# Append global LiteLLM proxy settings
cat >> "${LITELLM_CONFIG_FILE}" << YAML_EOF
litellm_settings:
  drop_params: true
  request_timeout: 120

general_settings:
  # master_key is dev-only and intentionally not a secret.
  # Override by setting LITELLM_MASTER_KEY in containerEnv.
  master_key: "sk-devcontainer"
YAML_EOF

log "Config written to ${LITELLM_CONFIG_FILE}"

# ---------------------------------------------------------------------------
# Step 6: Install start-ai-services.sh
# ---------------------------------------------------------------------------
log "Step 6: Installing start-ai-services.sh..."

cp "${FEATURE_DIR}/start-ai-services.sh" /usr/local/bin/start-ai-services.sh
chmod +x /usr/local/bin/start-ai-services.sh
log "start-ai-services.sh installed at /usr/local/bin/start-ai-services.sh"

# ---------------------------------------------------------------------------
# Step 7: Write environment defaults to profile.d
# ---------------------------------------------------------------------------
log "Step 7: Writing environment defaults to ${PROFILE_FILE}..."

# Design decision: We write to /etc/profile.d/ so the env vars are available
# in all login shells without requiring the user to set containerEnv manually.
# The devcontainer runner also injects containerEnv from devcontainer-feature.json,
# so these are a belt-and-braces fallback.
cat > "${PROFILE_FILE}" << PROFILE_EOF
# /etc/profile.d/litellm-ollama.sh
# Written by the litellm-ollama devcontainer feature.
# Override any of these in devcontainer.json "containerEnv".
export LITELLM_PORT="${LITELLM_PORT}"
export LITELLM_BASE_URL="http://localhost:${LITELLM_PORT}"
export OPENAI_API_BASE="http://localhost:${LITELLM_PORT}"
export OLLAMA_HOST="http://localhost:11434"
export OLLAMA_MODEL="${OLLAMA_MODEL}"
export LITELLM_CONFIG="/etc/litellm/config.yaml"
export LITELLM_MASTER_KEY="\${LITELLM_MASTER_KEY:-sk-devcontainer}"
PROFILE_EOF

chmod 644 "${PROFILE_FILE}"
log "Environment defaults written."

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
log "================================================="
log "  Installation complete!"
log ""
log "  Run 'start-ai-services.sh' to start services."
log "  LiteLLM will listen on: http://localhost:${LITELLM_PORT}"
log "  Ollama will listen on:  http://localhost:11434"
log "================================================="

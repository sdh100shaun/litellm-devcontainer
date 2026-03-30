#!/usr/bin/env bash
# start-ai-services.sh
# Purpose: Start and manage the Ollama and LiteLLM background services.
#
# This script is installed at /usr/local/bin/start-ai-services.sh by install.sh.
# It is designed to be the container entrypoint or called from postStartCommand.
#
# Behaviour (in order):
#   1. Start Ollama as a background process.
#   2. Poll http://localhost:11434/api/tags until ready (max 60s).
#   3. Pull the configured model only if not already present locally.
#   4. Start LiteLLM proxy as a background process.
#   5. Poll http://localhost:${LITELLM_PORT}/health until ready (max 60s).
#   6. Print a summary box showing URLs and available models.
#   7. Use 'wait' to keep both processes alive; exit cleanly if either dies.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration — all can be overridden via environment
# ---------------------------------------------------------------------------
LITELLM_PORT="${LITELLM_PORT:-4000}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5-coder:7b}"
LITELLM_CONFIG="${LITELLM_CONFIG:-/etc/litellm/config.yaml}"
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY:-sk-devcontainer}"
OLLAMA_READY_TIMEOUT=60
LITELLM_READY_TIMEOUT=60
LOG_DIR="${LOG_DIR:-/tmp/litellm-ollama-logs}"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
log() {
    echo "[litellm-ollama] $*"
}

err() {
    echo "[litellm-ollama] ERROR: $*" >&2
}

# ---------------------------------------------------------------------------
# wait_for_url <url> <service-name> <timeout-seconds>
# Polls the given URL until it returns HTTP 200 or the timeout is reached.
# Exits with a non-zero status and a clear error message on timeout.
# ---------------------------------------------------------------------------
wait_for_url() {
    local url="$1"
    local service="$2"
    local timeout="$3"
    local elapsed=0
    local poll_interval=2

    log "Waiting for ${service} at ${url} (timeout: ${timeout}s)..."
    while ! curl -sf --connect-timeout "${poll_interval}" --max-time "${poll_interval}" "${url}" > /dev/null 2>&1; do
        if [ "${elapsed}" -ge "${timeout}" ]; then
            err "${service} did not become ready within ${timeout}s."
            err "Check logs in ${LOG_DIR}/ for details."
            return 1
        fi
        sleep "${poll_interval}"
        elapsed=$((elapsed + poll_interval))
    done
    log "${service} is ready (${elapsed}s elapsed)."
}

# ---------------------------------------------------------------------------
# print_summary
# Prints a human-readable summary box once all services are up.
# ---------------------------------------------------------------------------
print_summary() {
    local litellm_url="http://localhost:${LITELLM_PORT}"
    local ollama_url="http://localhost:11434"

    log ""
    log "╔══════════════════════════════════════════════════════╗"
    log "║        LiteLLM + Ollama — Services Ready             ║"
    log "╠══════════════════════════════════════════════════════╣"
    log "║  Ollama API   :  ${ollama_url}              ║"
    log "║  LiteLLM API  :  ${litellm_url}/v1               ║"
    log "║  Health check :  ${litellm_url}/health           ║"
    log "║  Model list   :  ${litellm_url}/v1/models        ║"
    log "╠══════════════════════════════════════════════════════╣"
    log "║  Default model : ${OLLAMA_MODEL}"
    log "║  Master key    : \${LITELLM_MASTER_KEY}  (env var)"
    log "╠══════════════════════════════════════════════════════╣"
    log "║  OpenAI-compatible client config:                    ║"
    log "║    base_url = ${litellm_url}/v1            ║"
    log "║    api_key  = \${LITELLM_MASTER_KEY}               ║"
    log "╚══════════════════════════════════════════════════════╝"
    log ""
}

# ---------------------------------------------------------------------------
# cleanup — called on SIGTERM/SIGINT to stop both services gracefully
# ---------------------------------------------------------------------------
# shellcheck disable=SC2317  # cleanup is invoked indirectly via trap
cleanup() {
    log "Shutting down services (signal received)..."
    # Kill with || true so cleanup never fails even if PIDs are already gone
    kill "${OLLAMA_PID:-}" 2>/dev/null || true
    kill "${LITELLM_PID:-}" 2>/dev/null || true
    wait "${OLLAMA_PID:-}" 2>/dev/null || true
    wait "${LITELLM_PID:-}" 2>/dev/null || true
    log "Services stopped."
}
trap cleanup SIGTERM SIGINT

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
mkdir -p "${LOG_DIR}"

log "Starting LiteLLM + Ollama services..."
log "  Model  : ${OLLAMA_MODEL}"
log "  Port   : ${LITELLM_PORT}"
log "  Config : ${LITELLM_CONFIG}"

# Step 1 — Start Ollama in the background
log "Step 1: Starting Ollama..."
ollama serve > "${LOG_DIR}/ollama.log" 2>&1 &
OLLAMA_PID=$!
log "Ollama started (PID: ${OLLAMA_PID}). Logs: ${LOG_DIR}/ollama.log"

# Step 2 — Wait for Ollama to be ready
wait_for_url "http://localhost:11434/api/tags" "Ollama" "${OLLAMA_READY_TIMEOUT}"

# Step 3 — Pull model only if not already present
# Design decision: We check 'ollama list' before pulling to make restarts fast.
# On first start the model will be pulled (can be multi-GB for large models).
log "Step 3: Checking model '${OLLAMA_MODEL}'..."
if [ -n "${OLLAMA_MODEL}" ]; then
    if ollama list 2>/dev/null | grep -qF "${OLLAMA_MODEL%%:*}"; then
        log "Model '${OLLAMA_MODEL}' already present; skipping pull."
    else
        log "Pulling model '${OLLAMA_MODEL}' (first-run download — may take several minutes)..."
        ollama pull "${OLLAMA_MODEL}"
        log "Model '${OLLAMA_MODEL}' pulled successfully."
    fi
else
    log "OLLAMA_MODEL is empty; skipping model pull."
fi

# Step 4 — Start LiteLLM proxy in the background
log "Step 4: Starting LiteLLM proxy on port ${LITELLM_PORT}..."
LITELLM_MASTER_KEY="${LITELLM_MASTER_KEY}" \
    litellm \
        --config "${LITELLM_CONFIG}" \
        --port "${LITELLM_PORT}" \
        --host "0.0.0.0" \
    > "${LOG_DIR}/litellm.log" 2>&1 &
LITELLM_PID=$!
log "LiteLLM started (PID: ${LITELLM_PID}). Logs: ${LOG_DIR}/litellm.log"

# Step 5 — Wait for LiteLLM to be ready
wait_for_url "http://localhost:${LITELLM_PORT}/health" "LiteLLM" "${LITELLM_READY_TIMEOUT}"

# Step 6 — Print summary
print_summary

# Step 7 — Wait for both processes
# If either exits unexpectedly, the 'wait' returns with its exit code and
# this script exits non-zero, signalling the container runtime.
log "Services running. Waiting for PIDs Ollama=${OLLAMA_PID} LiteLLM=${LITELLM_PID}..."

# Disable set -e for the wait block so we can capture the exit code manually
set +e
wait -n "${OLLAMA_PID}" "${LITELLM_PID}"
WAIT_EXIT=$?
set -e

if [ "${WAIT_EXIT}" -ne 0 ]; then
    err "A service exited unexpectedly (exit code: ${WAIT_EXIT})."
    err "Check logs in ${LOG_DIR}/ for details."
fi

exit "${WAIT_EXIT}"

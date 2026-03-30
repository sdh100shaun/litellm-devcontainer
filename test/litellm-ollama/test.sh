#!/usr/bin/env bats
# test.sh
# Purpose: Bats test suite for the litellm-ollama devcontainer feature.
#
# These tests run INSIDE the container after the feature has been installed.
# They verify binary presence, script executability, config validity,
# environment variable defaults, and negative assertions.
#
# Relation to feature: Tests are discovered and executed by the devcontainer
# CLI (`devcontainer features test`) using the scenarios defined in
# scenarios.json in this directory.
#
# Run manually: bats test/litellm-ollama/test.sh
# Requires:     bats-core (https://github.com/bats-core/bats-core)

# ==========================================================================
# Binary presence tests
# ==========================================================================

@test "ollama binary is present in PATH" {
    run which ollama
    [ "$status" -eq 0 ]
}

@test "ollama binary is executable and returns a version" {
    run ollama --version
    [ "$status" -eq 0 ]
    [[ "$output" == *"ollama"* ]]
}

@test "litellm binary is present in PATH" {
    run which litellm
    [ "$status" -eq 0 ]
}

@test "litellm binary is executable and returns a version" {
    run litellm --version
    [ "$status" -eq 0 ]
}

# ==========================================================================
# Script presence and executability tests
# ==========================================================================

@test "start-ai-services.sh exists at /usr/local/bin" {
    [ -f "/usr/local/bin/start-ai-services.sh" ]
}

@test "start-ai-services.sh is executable" {
    [ -x "/usr/local/bin/start-ai-services.sh" ]
}

# ==========================================================================
# Config file validity tests
# ==========================================================================

@test "litellm config directory /etc/litellm exists" {
    [ -d "/etc/litellm" ]
}

@test "litellm config file /etc/litellm/config.yaml exists" {
    [ -f "/etc/litellm/config.yaml" ]
}

@test "litellm config.yaml is valid YAML (parseable by python3)" {
    # Design decision: python3+yaml is already a LiteLLM dependency,
    # so it is always available and avoids adding a new test dependency.
    run python3 -c "import yaml; yaml.safe_load(open('/etc/litellm/config.yaml'))"
    [ "$status" -eq 0 ]
}

@test "litellm config.yaml contains model_list key" {
    run grep -q "^model_list:" /etc/litellm/config.yaml
    [ "$status" -eq 0 ]
}

@test "litellm config.yaml contains a 'default' model alias" {
    run grep -q 'model_name: "default"' /etc/litellm/config.yaml
    [ "$status" -eq 0 ]
}

@test "litellm config.yaml contains litellm_settings section" {
    run grep -q "^litellm_settings:" /etc/litellm/config.yaml
    [ "$status" -eq 0 ]
}

# ==========================================================================
# Environment variable tests
# ==========================================================================

@test "profile.d file /etc/profile.d/litellm-ollama.sh exists" {
    [ -f "/etc/profile.d/litellm-ollama.sh" ]
}

@test "LITELLM_PORT is set and non-empty in profile.d" {
    run bash -c 'source /etc/profile.d/litellm-ollama.sh && echo "${LITELLM_PORT}"'
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "LITELLM_PORT is a valid port number (1024-65535)" {
    run bash -c 'source /etc/profile.d/litellm-ollama.sh && echo "${LITELLM_PORT}"'
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -ge 1024 ]
    [ "$output" -le 65535 ]
}

@test "OLLAMA_MODEL is set and non-empty in profile.d" {
    run bash -c 'source /etc/profile.d/litellm-ollama.sh && echo "${OLLAMA_MODEL}"'
    [ "$status" -eq 0 ]
    [ -n "$output" ]
}

@test "LITELLM_BASE_URL is set and starts with http in profile.d" {
    run bash -c 'source /etc/profile.d/litellm-ollama.sh && echo "${LITELLM_BASE_URL}"'
    [ "$status" -eq 0 ]
    [[ "$output" == http* ]]
}

@test "LITELLM_CONFIG env var points to an existing file" {
    run bash -c 'source /etc/profile.d/litellm-ollama.sh && test -f "${LITELLM_CONFIG}" && echo "exists"'
    [ "$status" -eq 0 ]
    [ "$output" = "exists" ]
}

# ==========================================================================
# Negative tests — verify disabled providers are absent
# ==========================================================================

@test "config does NOT contain Bedrock stanza when enableBedrock=false (default scenario)" {
    # In the default test scenario no options are set, so Bedrock must be absent.
    # This guards against accidental provider leakage in the base config.
    run grep -qi "bedrock" /etc/litellm/config.yaml
    [ "$status" -ne 0 ]
}

@test "config does NOT contain OpenAI stanza when enableOpenAI=false (default scenario)" {
    run grep -q "openai/gpt-4o" /etc/litellm/config.yaml
    [ "$status" -ne 0 ]
}

@test "config does NOT contain Anthropic stanza when enableAnthropic=false (default scenario)" {
    run grep -q "anthropic/claude" /etc/litellm/config.yaml
    [ "$status" -ne 0 ]
}

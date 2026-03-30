# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository is a [Dev Container feature](https://containers.dev/implementors/features/) for [LiteLLM](https://github.com/BerriAI/litellm), which acts as a proxy/gateway for LLM APIs. The goal is to allow developers to easily add LiteLLM to their dev container setup.

## Dev Container Feature Structure

Dev Container features follow a standard layout:

```
src/
  <feature-name>/
    devcontainer-feature.json   # Feature metadata and options
    install.sh                  # Installation script run inside the container
test/
  <feature-name>/
    test.sh                     # Smoke tests for the feature
    scenarios.json              # (optional) Test matrix
.github/
  workflows/                    # CI for releasing and testing features
```

The `devcontainer-feature.json` defines the feature name, version, options, and install entrypoint. `install.sh` is the shell script that runs inside the container to install LiteLLM and configure it.

## Testing

Dev Container features are tested using the [dev container CLI](https://github.com/devcontainers/cli):

```bash
# Install the CLI
npm install -g @devcontainers/cli

# Run feature tests (from repo root)
devcontainer features test --base-image mcr.microsoft.com/devcontainers/base:ubuntu --features src/<feature-name>
```

## Publishing

Features are published to the GitHub Container Registry (ghcr.io) via GitHub Actions. The release workflow is typically triggered by tagging or merging to main.

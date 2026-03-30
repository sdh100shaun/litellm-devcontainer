# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repository is a [Dev Container feature](https://containers.dev/implementors/features/) for [LiteLLM](https://github.com/BerriAI/litellm), which acts as a proxy/gateway for LLM APIs. The goal is to allow developers to easily add LiteLLM to their dev container setup.

The tooling (build, test, scripts) is written in **TypeScript**, using **Biome** for linting/formatting and **Jest** for unit/integration testing.

## Dev Container Feature Structure

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

## Common Commands

```bash
# Install dependencies
npm install

# Build TypeScript
npm run build

# Lint & format (Biome)
npm run lint
npm run format

# Run all tests
npm test

# Run a single test file
npx jest path/to/file.test.ts

# Run devcontainer feature tests
devcontainer features test --base-image mcr.microsoft.com/devcontainers/base:ubuntu --features src/litellm-ollama --test-folder test/litellm-ollama
```

## Tooling

- **TypeScript**: strict mode; `tsconfig.json` at root
- **Biome**: replaces ESLint + Prettier; config in `biome.json`
- **Jest**: configured via `jest.config.ts`; test files use `.test.ts` suffix

## Branch Strategy

Each feature or task is developed on its own branch. Branch naming convention:

```
feature/<short-description>
```

Every item in the project plan maps to exactly one feature branch, merged to `main` via pull request.

## Publishing

Features are published to the GitHub Container Registry (ghcr.io) via GitHub Actions, triggered on merge to `main` or by tagging a release.

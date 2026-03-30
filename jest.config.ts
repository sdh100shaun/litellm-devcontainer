// jest.config.ts
// Jest configuration for TypeScript tooling scripts.
// BATS (bats-core) is used for the devcontainer feature shell tests;
// Jest is used for any TypeScript utility scripts under scripts/.
import type { Config } from "jest";

const config: Config = {
  preset: "ts-jest",
  testEnvironment: "node",
  roots: ["<rootDir>/scripts"],
  testMatch: ["**/*.test.ts"],
  collectCoverageFrom: ["scripts/**/*.ts", "!scripts/**/*.test.ts"],
  coverageDirectory: "coverage",
};

export default config;

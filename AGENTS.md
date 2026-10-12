# Repository Guidelines

## Project Structure & Module Organization

This repository currently has no source files, tests, assets, build configuration, or Git history. Update this guide as the implementation takes shape. Organize new code around stable domain, capability, runtime, or ownership boundaries. Create folders when they improve discovery or isolate meaningful dependencies, not merely to reduce file counts.

Keep related behavior together and dependency direction clear. Avoid cross-imports into unrelated sibling internals and bidirectional dependencies. Use names that describe the owned concept or responsibility; avoid dumping grounds such as `utils`, `helpers`, `common`, and `misc`.

## Build, Test, and Development Commands

No build, test, lint, or local-run commands are configured yet. When adding tooling, document exact commands and prerequisites here. Do not describe unverified commands as supported. Use `Get-ChildItem -Force` to inspect the repository, including hidden configuration files.

## Coding Style & Naming Conventions

Follow the language and formatter selected by the first implementation; indentation and lint rules are not established yet. Keep style consistent within each file. Introduce architectural filename prefixes or suffixes only when they have stable, documented repository-wide meaning.

## Abstraction and File-Shape Rules

Apply the **delete test** before introducing or retaining an abstraction: mentally inline its behavior into callers. Keep it when it owns meaningful policy, translation, lifecycle, dependencies, or domain knowledge; protects a boundary; or keeps changes together. Avoid pass-through layers when inlining improves clarity. Judge semantic depth, not size or call-site count; repetition alone does not justify extraction.

Treat roughly **300 lines of handwritten source** as a review trigger, not a limit. Before adding substantial behavior, explicitly decide whether to keep or split the file. Keep cohesive responsibilities together; require a concrete cohesion reason for substantially larger files. Split only along genuine responsibility or ownership seams, preserve dependency direction, expose minimal contracts, and choose discoverable names and locations. Do not create micro-files solely to meet a threshold.

## Testing Guidelines

Tests protect runtime code only. Tests are not for layouts, copy text, or deployment.

Keep tests focused on behavior, data integrity, and meaningful regressions. Do not assert cosmetic wording, colors, coordinates, frame structure, library packaging, or deployment details. Prefer observable outcomes over assertions that mirror implementation.

In-game Lua suites live in `Tests/`. Run `/wsgs test all` or a specific suite (`scanner`, `comparator`, `importer`, `ui`) inside MoP Classic. Tests must not modify the player's equipment, settings, or managed builds; use temporary in-memory builds. Do not claim in-game passes without executing them in the client.

## Commit & Pull Request Guidelines

No existing commit convention can be inferred. Use concise, imperative subjects describing the change. Pull requests should explain the problem, resulting behavior, validation performed, and relevant limitations. Link applicable issues and include screenshots for visible UI changes.
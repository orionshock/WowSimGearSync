# Repository Guidelines

## Project Structure & Module Organization

This repository is a WoW Forever Lua addon using the retail client APIs with production modules grouped by ownership under `Addon/`, `Builds/`, `Character/`, `Equipment/`, `Enhancements/`, `EquipmentSets/`, `Shopping/`, `Interaction/`, `Views/`, and `Diagnostics/`, bundled libraries under `Libs/`, and implementation notes under `docs/`. Organize new code around stable domain, capability, runtime, or ownership boundaries. Create folders when they improve discovery or isolate meaningful dependencies, not merely to reduce file counts.

`Bootstrap.lua` establishes public feature tables and the temporary implementation registry. `Addon/Composition.lua` loads last, wires runtime collaborators, and removes the registry from the addon namespace. Follow the ownership and runtime contracts in `docs/architecture.md`.

Features implement their public methods directly in the files that own the behavior; do not add forwarding facades in composition. Other features use the public interfaces on `WSGS`; they must not access a sibling's implementation registry. Files inside one feature may share that feature's private modules. The composition root is the only place that wires implementations across features. `WSGS.Equipment.Slots` is shared read-only domain metadata.

Keep related behavior together and dependency direction clear. Avoid cross-imports into unrelated sibling internals and bidirectional dependencies. Use names that describe the owned concept or responsibility; avoid dumping grounds such as `utils`, `helpers`, `common`, and `misc`.

## Build, Test, and Development Commands

Release packaging runs through `.github/workflows/release.yml` on version tags such as `v0.3.0` and `v0.3.0-alpha1`, using BigWigsMods/packager@v2. Use annotated tags. The workflow fetches full history and uses GitHub's built-in token for Releases; no external upload credentials are needed. For local staging without publishing, run the upstream `release.sh -d -z -n "{package-name}-{project-version}"` under Bash with Git and the standard Unix tools available. This command skips ZIP creation; the hosted workflow creates the ZIP. Unpackaged checkouts use the TOC version placeholder and report Development in addon diagnostics; packaged versions come from the tag. No automated tests or local WoW runner are configured. Use `Get-ChildItem -Force` to inspect the repository, including hidden configuration files.

## Coding Style & Naming Conventions

Follow the language and formatter selected by the first implementation; indentation and lint rules are not established yet. Keep style consistent within each file. Introduce architectural filename prefixes or suffixes only when they have stable, documented repository-wide meaning.

## Abstraction and File-Shape Rules

### The Delete Test

Apply the delete test before introducing or retaining helpers, wrappers, adapters, abstractions, or extracted units: mentally remove the abstraction and inline its behavior into its callers without changing behavior. Keep it when inlining would duplicate domain knowledge, scatter behavior that must change together, expose implementation details across a boundary, erase a useful concept, or spread one future change across several owners. Delete or avoid it when inlining makes the code clearer with only trivial duplication or reveals a pass-through layer with no meaningful ownership, policy, translation, lifecycle, or dependency role. Judge semantic depth rather than helper size, call-site count, or lines changed: a single-use boundary may be valuable, while a widely used trivial wrapper may still be needless indirection. Repetition is evidence to evaluate, not an automatic extraction rule.

### File Shape

Treat roughly **300 lines of handwritten source** as a review trigger, not a limit. Before adding substantial behavior, explicitly decide whether to keep or split the file. Keep cohesive responsibilities together; require a concrete cohesion reason for substantially larger files. Split only along genuine responsibility or ownership seams, preserve dependency direction, expose minimal contracts, and choose discoverable names and locations. Do not create micro-files solely to meet a threshold.

## Runtime Validation Guidelines

Do not create automated test suites or mock-client tests. Validate behavior in the actual WoW Forever client and use structured runtime debug logging to investigate behavior. Tests must not be reintroduced without explicit instruction.

## Commit & Pull Request Guidelines

No existing commit convention can be inferred. Use concise, imperative subjects describing the change. Pull requests should explain the problem, resulting behavior, validation performed, and relevant limitations. Link applicable issues and include screenshots for visible UI changes.

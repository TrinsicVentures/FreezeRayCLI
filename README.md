# FreezeRay CLI

Command-line tool for freezing SwiftData schemas and scaffolding migration tests.

> **Note:** This repository is currently being split from the main FreezeRay monorepo. Installation instructions will be updated once the split is complete.

## What is FreezeRay?

FreezeRay prevents accidental SwiftData schema changes from reaching production by creating immutable schema snapshots (fixtures) and generating validation tests.

**This repository contains the CLI tool.** For the Swift package (macros + runtime), see [FreezeRay](https://github.com/TrinsicVentures/FreezeRay).

## Repository Structure

```
FreezeRayCLI/
├── Sources/
│   ├── freezeray-cli/        # CLI library (testable)
│   └── freezeray-bin/        # CLI executable
├── Tests/
│   └── FreezeRayCLITests/    # CLI unit tests
├── docs/                      # Mintlify documentation
└── Package.swift
```

## Building

```bash
swift build
```

## Testing

```bash
swift test
```

## License

MIT License - See [LICENSE](LICENSE) for details

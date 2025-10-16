# FreezeRay CLI

Command-line tool for freezing SwiftData schemas and scaffolding migration tests.

**This repository contains the CLI tool.** For the Swift package (macros + runtime), see [FreezeRay](https://github.com/TrinsicVentures/FreezeRay).

## What is FreezeRay?

FreezeRay prevents accidental SwiftData schema changes from reaching production by creating immutable schema snapshots (fixtures) and generating validation tests.

The CLI tool (`freezeray`) orchestrates the freezing workflow:
- Auto-detects your Xcode project structure
- Runs tests in iOS Simulator to export schemas
- Extracts fixtures via `/tmp` (works in simulator sandbox)
- Scaffolds drift detection and migration tests
- Auto-adds test files to your Xcode project

## Installation

> **Note:** Distribution (Homebrew/npm) coming soon. For now, build from source.

### Build from Source

```bash
git clone https://github.com/TrinsicVentures/FreezeRayCLI.git
cd FreezeRayCLI
swift build -c release
cp .build/release/freezeray /usr/local/bin/
```

Verify installation:
```bash
freezeray --version
```

## Requirements

- **macOS 14+** (CLI requirement)
- **Xcode 16+** (Swift 6.0 support)
- **FreezeRay package** must be added to your Xcode project

## Usage

### Initialize Your Project

```bash
cd /path/to/your/project
freezeray init
```

This:
- Creates `FreezeRay/Fixtures/` and `FreezeRay/Tests/` directories
- Adds FreezeRay folder as yellow folder reference (auto-syncs with filesystem)
- Adds FreezeRay package dependency
- Configures test target to include fixtures as bundle resources

### Freeze a Schema Version

```bash
freezeray freeze 1.0.0
```

This:
- Discovers schemas annotated with `@FreezeSchema(version: "1.0.0")`
- Builds and runs your app in iOS Simulator
- Exports schema to `FreezeRay/Fixtures/1.0.0/`
- Generates checksums for drift detection
- Scaffolds drift detection test
- Scaffolds migration tests (if you have multiple versions)
- Auto-adds test files to your Xcode project

**What gets generated:**
```
FreezeRay/
├── Fixtures/
│   └── 1.0.0/
│       ├── App-1_0_0.sqlite
│       ├── schema-1_0_0.json
│       ├── schema-1_0_0.sql
│       ├── schema-1_0_0.sha256
│       └── export_metadata.txt
└── Tests/
    └── SchemaV1_DriftTests.swift  (auto-added to test target)
```

### Run Tests

Press ⌘U in Xcode or:
```bash
xcodebuild test \
  -project YourApp.xcodeproj \
  -scheme YourApp \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

### Options

```bash
freezeray init --help
freezeray freeze --help
```

Common options:
- `--project <path>` - Path to .xcodeproj (auto-detected if only one exists)
- `--scheme <name>` - Scheme name (auto-detected from project name)
- `--simulator <name>` - Simulator name (default: "iPhone 17")
- `--force` - Overwrite existing fixtures (use with caution!)

## Development

### Build & Test

```bash
swift build          # Build CLI
swift test           # Run 22 unit tests
```

### Testing with Local Changes

If you're developing both FreezeRay package and CLI simultaneously:

1. Update Package.swift to use local path:
```swift
.package(path: "../FreezeRay"),
```

2. Build and test:
```bash
swift build && swift test
```

## Repository Structure

```
FreezeRayCLI/
├── Sources/
│   ├── freezeray-cli/            # CLI library (testable)
│   │   ├── Commands/
│   │   │   ├── InitCommand.swift
│   │   │   ├── FreezeCommand.swift
│   │   │   └── TestScaffolding.swift
│   │   ├── Parser/
│   │   │   └── MacroDiscovery.swift
│   │   ├── Simulator/
│   │   │   └── SimulatorManager.swift
│   │   └── CLI.swift
│   └── freezeray-bin/            # CLI executable (thin wrapper)
│       └── main.swift
├── Tests/
│   └── FreezeRayCLITests/        # 22 unit tests
│       ├── FreezeCommandTests.swift
│       └── InitCommandTests.swift
├── docs/                          # Mintlify documentation
└── Package.swift
```

## Documentation

Full documentation available at: **[docs.freezeray.dev](https://docs.freezeray.dev)**

## Related Projects

- **[FreezeRay](https://github.com/TrinsicVentures/FreezeRay)** - Swift package (macros + runtime)

## Contributing

See the main [FreezeRay repository](https://github.com/TrinsicVentures/FreezeRay) for contributing guidelines and architecture documentation.

## License

MIT License - See [LICENSE](LICENSE) for details

---

**Maintained by:** Geordie Kaytes ([@didgeoridoo](https://github.com/didgeoridoo))
**Organization:** [Trinsic Ventures](https://github.com/TrinsicVentures)

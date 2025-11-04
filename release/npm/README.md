# FreezeRay CLI

CLI tool for freezing SwiftData schemas and validating migration paths.

**Note:** This package contains a precompiled binary for Apple Silicon (ARM64) only. Intel Macs are not supported via npm - please build from source.

## Installation

```bash
npm install -g @trinsicventures/freezeray
```

## Quick Start

```bash
# Initialize FreezeRay in your project
cd YourProject
freezeray init

# Annotate your schema
# (Add @FreezeSchema(version: "1.0.0") to your schema)

# Freeze the schema
freezeray freeze 1.0.0
```

## Requirements

- macOS 14+
- **Apple Silicon (ARM64) only**
- Xcode 15+
- iOS 17+ or macOS 14+ project with SwiftData

## Building from Source (Intel Macs)

```bash
git clone https://github.com/TrinsicVentures/FreezeRay.git
cd FreezeRay
swift build -c release
cp .build/release/freezeray /usr/local/bin/
```

## Documentation

Full documentation: https://docs.freezeray.dev

## Issues

Report issues: https://github.com/TrinsicVentures/FreezeRay/issues

## License

MIT License - see [LICENSE](https://github.com/TrinsicVentures/FreezeRay/blob/master/LICENSE)

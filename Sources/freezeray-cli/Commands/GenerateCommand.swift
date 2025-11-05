import ArgumentParser
import Foundation

/// Generate FreezeRay artifacts (fixtures, schema tests, or migration tests)
public struct GenerateCommand: ParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate FreezeRay artifacts (fixtures, schema tests, or migration tests)",
        discussion: """
            The generate command provides granular control over FreezeRay artifact generation.

            Use this for fine-grained workflow control, such as:
            - Generating migration tests early in development (before freeze)
            - Regenerating tests without re-running fixture generation
            - Customizing the freeze workflow

            Examples:
              freezeray generate fixtures --schema 3.0.0
              freezeray generate schema-tests --schema 3.0.0
              freezeray generate migration-tests --from-schema 2.0.0 --to-schema 3.0.0
            """,
        subcommands: [
            GenerateFixturesCommand.self,
            GenerateSchemaTestsCommand.self,
            GenerateMigrationTestsCommand.self
        ],
        defaultSubcommand: nil
    )

    public init() {}
}

// MARK: - Generate Fixtures

struct GenerateFixturesCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fixtures",
        abstract: "Generate frozen fixtures for a schema version",
        discussion: """
            Generates frozen SwiftData fixtures for a specific schema version.

            This command:
            1. Discovers @FreezeSchema annotation for the specified version
            2. Runs the freeze test in iOS simulator
            3. Extracts fixtures from /tmp to FreezeRay/Fixtures/<version>/

            Generated artifacts:
            - FreezeRay/Fixtures/<version>/App-<version>.sqlite
            - FreezeRay/Fixtures/<version>/schema-<version>.sql
            - FreezeRay/Fixtures/<version>/schema-<version>.json
            - FreezeRay/Fixtures/<version>/schema-<version>.sha256
            - FreezeRay/Fixtures/<version>/export_metadata.txt

            Example:
              freezeray generate fixtures --schema 3.0.0
              freezeray g fixtures -s 3.0.0
            """
    )

    @Option(name: [.short, .long], help: "Schema version to freeze (e.g., \"1.0.0\")")
    var schema: String

    @Option(help: "Path to FreezeRay.yaml config file")
    var config: String?

    @Option(help: "iOS simulator to use (default: iPhone 17)")
    var simulator: String = "iPhone 17"

    @Option(help: "Xcode scheme to build (auto-detected if not provided)")
    var scheme: String?

    @Flag(help: "Overwrite existing fixtures")
    var force: Bool = false

    @Option(help: "Output directory for fixtures (default: FreezeRay/Fixtures)")
    var output: String?

    func run() throws {
        let workingDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        print("🔍 Generating fixtures for schema version \(schema)...")

        // Discover project structure
        let projectPath = try SimulatorManager.discoverProject(in: workingDir)
        let resolvedScheme = try scheme ?? SimulatorManager.discoverScheme(projectPath: projectPath)
        let testTarget = SimulatorManager.inferTestTarget(from: resolvedScheme)

        // Discover schemas
        let discovery = try discoverMacros(in: [workingDir.path])

        guard let freezeAnnotation = discovery.freezeAnnotations.first(where: { $0.version == schema }) else {
            throw FreezeError.schemaNotFound(version: schema, available: discovery.freezeAnnotations.map(\.version))
        }

        // Determine app target
        let appTarget = String(freezeAnnotation.typeName.prefix(while: { $0 != "." }))

        // Check if fixtures already exist
        let fixturesBaseDir = output.map { URL(fileURLWithPath: $0) } ?? workingDir.appendingPathComponent("FreezeRay/Fixtures")
        let fixturesDir = fixturesBaseDir.appendingPathComponent(schema)

        if FileManager.default.fileExists(atPath: fixturesDir.path) && !force {
            print("⚠️  Fixtures already exist at \(fixturesDir.path)")
            print("   Use --force to overwrite")
            return
        }

        // Generate temporary freeze test
        let testFilePath = try FreezeCommand.generateFreezeTest(
            workingDir: workingDir,
            testTarget: testTarget,
            appTarget: appTarget,
            schemaType: freezeAnnotation.typeName,
            version: schema
        )

        defer {
            try? FileManager.default.removeItem(at: testFilePath)
        }

        // Run test in simulator to generate fixtures
        print("📱 Running freeze test in simulator (\(simulator))...")
        let manager = SimulatorManager()
        let simulatorFixturesURL = try manager.runFreezeInSimulator(
            projectPath: projectPath,
            scheme: resolvedScheme,
            testTarget: testTarget,
            schemaType: freezeAnnotation.typeName,
            version: schema,
            simulator: simulator
        )

        // Extract fixtures from /tmp
        print("📦 Extracting fixtures from simulator...")
        try FileManager.default.createDirectory(at: fixturesBaseDir, withIntermediateDirectories: true)

        if FileManager.default.fileExists(atPath: fixturesDir.path) {
            try FileManager.default.removeItem(at: fixturesDir)
        }

        try FileManager.default.copyItem(at: simulatorFixturesURL, to: fixturesDir)

        print("✅ Generated fixtures: \(fixturesDir.path)/")

        // List generated files
        let files = try FileManager.default.contentsOfDirectory(at: fixturesDir, includingPropertiesForKeys: nil)
        for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            print("   - \(file.lastPathComponent)")
        }
    }
}

// MARK: - Generate Schema Tests

struct GenerateSchemaTestsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "schema-tests",
        abstract: "Generate drift tests for a schema version",
        discussion: """
            Generates a drift test file that validates a frozen schema hasn't changed.

            This command:
            1. Discovers @FreezeSchema annotation for the specified version
            2. Creates FreezeRay/Tests/<SchemaType>_DriftTests.swift
            3. Adds test file to Xcode project

            The generated test calls the macro-generated check function to ensure
            the schema definition hasn't drifted from the frozen version.

            Note: This command requires that fixtures already exist for the version.
            Run 'freezeray generate fixtures' first if needed.

            Example:
              freezeray generate schema-tests --schema 3.0.0
              freezeray g schema-tests -s 3.0.0
            """
    )

    @Option(name: [.short, .long], help: "Schema version (e.g., \"1.0.0\")")
    var schema: String

    @Option(help: "Path to FreezeRay.yaml config file")
    var config: String?

    @Flag(help: "Overwrite existing test file")
    var force: Bool = false

    func run() throws {
        let workingDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        print("🔍 Generating schema tests for version \(schema)...")

        // Discover project structure
        let projectPath = try SimulatorManager.discoverProject(in: workingDir)
        let resolvedScheme = try SimulatorManager.discoverScheme(projectPath: projectPath)
        let testTarget = SimulatorManager.inferTestTarget(from: resolvedScheme)

        // Discover schemas
        let discovery = try discoverMacros(in: [workingDir.path])

        guard let freezeAnnotation = discovery.freezeAnnotations.first(where: { $0.version == schema }) else {
            throw FreezeError.schemaNotFound(version: schema, available: discovery.freezeAnnotations.map(\.version))
        }

        let appTarget = String(freezeAnnotation.typeName.prefix(while: { $0 != "." }))

        // Check that fixtures exist
        let fixturesDir = workingDir.appendingPathComponent("FreezeRay/Fixtures/\(schema)")
        guard FileManager.default.fileExists(atPath: fixturesDir.path) else {
            throw FreezeError.fixturesNotFound(version: schema, path: fixturesDir.path)
        }

        // Generate drift test
        let testsDir = workingDir.appendingPathComponent("FreezeRay/Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)

        let scaffolding = TestScaffolding()
        let scaffoldResult = try scaffolding.scaffoldDriftTest(
            testsDir: testsDir,
            schemaType: freezeAnnotation.typeName,
            appTarget: appTarget,
            version: schema,
            force: force
        )

        guard let testFile = scaffoldResult.createdFile else {
            if scaffoldResult.skipped {
                print("⚠️  Test file already exists: \(scaffoldResult.targetPath?.lastPathComponent ?? "")")
                print("   Use --force to overwrite")
            }
            return
        }

        // Add test file to Xcode project
        try FreezeCommand.addTestFilesToXcodeProject(
            projectPath: projectPath,
            testTarget: testTarget,
            testFiles: [testFile]
        )

        print("✅ Generated drift test: \(testFile.lastPathComponent)")
    }
}

// MARK: - Generate Migration Tests

struct GenerateMigrationTestsCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "migration-tests",
        abstract: "Generate migration test from one schema version to another",
        discussion: """
            Generates a migration test file that validates data migration between versions.

            This command:
            1. Discovers @FreezeSchema annotations for both versions
            2. Discovers SchemaMigrationPlan with the migration stage
            3. Creates FreezeRay/Tests/MigrateV<from>toV<to>_Tests.swift
            4. Adds test file to Xcode project

            The generated test includes:
            - @Suite(.serialized) to prevent parallel execution issues
            - Loads frozen fixtures from source version
            - Runs migration to target version
            - Basic validation (with TODOs for custom assertions)

            Requirements:
            - Fixtures must exist for --from-schema version
            - @FreezeSchema must exist in code for --to-schema version
            - MigrationPlan must have a migration stage between versions

            Behavior if test file exists:
            - Does NOT overwrite (preserves user's custom assertions)
            - Prints skip message
            - Use --force to overwrite

            Example:
              freezeray generate migration-tests --from-schema 2.0.0 --to-schema 3.0.0
              freezeray g migration-tests -f 2.0.0 -t 3.0.0
            """
    )

    @Option(name: [.customShort("f"), .long], help: "Source schema version (e.g., \"2.0.0\")")
    var fromSchema: String

    @Option(name: [.customShort("t"), .long], help: "Target schema version (e.g., \"3.0.0\")")
    var toSchema: String

    @Option(help: "Path to FreezeRay.yaml config file")
    var config: String?

    @Flag(help: "Overwrite existing test file")
    var force: Bool = false

    func run() throws {
        let workingDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        print("🔍 Generating migration test: v\(fromSchema) → v\(toSchema)...")

        // Discover project structure
        let projectPath = try SimulatorManager.discoverProject(in: workingDir)
        let resolvedScheme = try SimulatorManager.discoverScheme(projectPath: projectPath)
        let testTarget = SimulatorManager.inferTestTarget(from: resolvedScheme)

        // Discover schemas and migration plans
        let discovery = try discoverMacros(in: [workingDir.path])

        // Validate from-schema (should have fixtures)
        guard let fromAnnotation = discovery.freezeAnnotations.first(where: { $0.version == fromSchema }) else {
            throw FreezeError.schemaNotFound(version: fromSchema, available: discovery.freezeAnnotations.map(\.version))
        }

        let fromFixturesDir = workingDir.appendingPathComponent("FreezeRay/Fixtures/\(fromSchema)")
        guard FileManager.default.fileExists(atPath: fromFixturesDir.path) else {
            throw FreezeError.fixturesNotFound(version: fromSchema, path: fromFixturesDir.path)
        }

        // Validate to-schema (should exist in code)
        guard let toAnnotation = discovery.freezeAnnotations.first(where: { $0.version == toSchema }) else {
            throw FreezeError.schemaNotFound(version: toSchema, available: discovery.freezeAnnotations.map(\.version))
        }

        // Validate migration plan exists
        guard let migrationPlan = discovery.migrationPlans.first else {
            throw FreezeError.migrationPlanNotFound
        }

        let appTarget = String(fromAnnotation.typeName.prefix(while: { $0 != "." }))

        // Generate migration test
        let testsDir = workingDir.appendingPathComponent("FreezeRay/Tests")
        try FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)

        let scaffolding = TestScaffolding()
        let scaffoldResult = try scaffolding.scaffoldMigrationTest(
            testsDir: testsDir,
            migrationPlan: migrationPlan.typeName,
            fromVersion: fromSchema,
            fromSchemaType: fromAnnotation.typeName,
            toVersion: toSchema,
            toSchemaType: toAnnotation.typeName,
            appTarget: appTarget,
            force: force
        )

        guard let testFile = scaffoldResult.createdFile else {
            if scaffoldResult.skipped {
                print("⚠️  Migration test already exists: \(scaffoldResult.targetPath?.lastPathComponent ?? "")")
                print("   Preserving user's custom assertions (use --force to overwrite)")
            }
            return
        }

        // Add test file to Xcode project
        try FreezeCommand.addTestFilesToXcodeProject(
            projectPath: projectPath,
            testTarget: testTarget,
            testFiles: [testFile]
        )

        print("✅ Generated migration test: \(testFile.lastPathComponent)")
        print("   Edit this file to add custom migration assertions")
    }
}

// MARK: - Error Types

enum FreezeError: LocalizedError {
    case schemaNotFound(version: String, available: [String])
    case fixturesNotFound(version: String, path: String)
    case migrationPlanNotFound

    var errorDescription: String? {
        switch self {
        case .schemaNotFound(let version, let available):
            if available.isEmpty {
                return "❌ Error: No @FreezeSchema annotations found in codebase"
            } else {
                return """
                ❌ Error: No @FreezeSchema found for version \(version)
                   Available versions: \(available.joined(separator: ", "))
                """
            }
        case .fixturesNotFound(let version, let path):
            return """
            ❌ Error: No fixtures found for version \(version)
               Expected at: \(path)
               Run 'freezeray generate fixtures --schema \(version)' first
            """
        case .migrationPlanNotFound:
            return """
            ❌ Error: No SchemaMigrationPlan found in codebase
               Define a migration plan conforming to SchemaMigrationPlan before generating migration tests
            """
        }
    }
}

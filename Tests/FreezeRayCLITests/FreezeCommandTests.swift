import Testing
import Foundation
@testable import freezeray_cli

/// Unit tests for TestScaffolding helper functions
/// These tests validate the scaffolding and version discovery logic
@Suite("TestScaffolding Helper Tests")
struct FreezeCommandTests {

    // MARK: - findPreviousVersion Tests

    @Test("findPreviousVersion returns nil when fixtures directory doesn't exist")
    func testFindPreviousVersion_NoDirectory() throws {
        let scaffolding = TestScaffolding()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        let result = scaffolding.findPreviousVersion(current: "2.0.0", fixturesDir: tempDir)

        #expect(result == nil)
    }

    @Test("findPreviousVersion returns nil when no previous versions exist")
    func testFindPreviousVersion_NoPreviousVersions() throws {
        let scaffolding = TestScaffolding()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create current version directory
        try FileManager.default.createDirectory(
            at: tempDir.appendingPathComponent("2.0.0"),
            withIntermediateDirectories: true
        )

        let result = scaffolding.findPreviousVersion(current: "2.0.0", fixturesDir: tempDir)

        #expect(result == nil)
    }

    @Test("findPreviousVersion returns highest version less than current")
    func testFindPreviousVersion_MultipleVersions() throws {
        let scaffolding = TestScaffolding()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create version directories
        for version in ["1.0.0", "1.5.0", "2.0.0", "3.0.0"] {
            try FileManager.default.createDirectory(
                at: tempDir.appendingPathComponent(version),
                withIntermediateDirectories: true
            )
        }

        let result = scaffolding.findPreviousVersion(current: "3.0.0", fixturesDir: tempDir)

        #expect(result == "2.0.0")
    }

    @Test("findPreviousVersion handles semantic versioning correctly")
    func testFindPreviousVersion_SemanticVersioning() throws {
        let scaffolding = TestScaffolding()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create versions with different minor/patch numbers
        for version in ["1.0.0", "1.9.0", "1.10.0", "1.11.0", "2.0.0"] {
            try FileManager.default.createDirectory(
                at: tempDir.appendingPathComponent(version),
                withIntermediateDirectories: true
            )
        }

        let result = scaffolding.findPreviousVersion(current: "2.0.0", fixturesDir: tempDir)

        // Should return 1.11.0, not 1.9.0 (semantic versioning, not lexicographic)
        #expect(result == "1.11.0")
    }

    @Test("findPreviousVersion ignores non-version directories")
    func testFindPreviousVersion_IgnoresNonVersions() throws {
        let scaffolding = TestScaffolding()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create version directories and some junk
        for dir in ["1.0.0", ".git", "README.md", "v1.5.0", "2.0.0"] {
            try FileManager.default.createDirectory(
                at: tempDir.appendingPathComponent(dir),
                withIntermediateDirectories: true
            )
        }

        let result = scaffolding.findPreviousVersion(current: "2.0.0", fixturesDir: tempDir)

        // Should only consider valid semantic versions (1.0.0)
        #expect(result == "1.0.0")
    }

    @Test("findPreviousVersion handles patch version increments")
    func testFindPreviousVersion_PatchVersions() throws {
        let scaffolding = TestScaffolding()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create patch versions
        for version in ["1.0.0", "1.0.1", "1.0.2", "1.0.5"] {
            try FileManager.default.createDirectory(
                at: tempDir.appendingPathComponent(version),
                withIntermediateDirectories: true
            )
        }

        let result = scaffolding.findPreviousVersion(current: "1.0.5", fixturesDir: tempDir)

        #expect(result == "1.0.2")
    }

    // MARK: - scaffoldDriftTest Tests

    @Test("scaffoldDriftTest creates new file when it doesn't exist")
    func testScaffoldDriftTest_CreatesNewFile() throws {
        let scaffolding = TestScaffolding()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try scaffolding.scaffoldDriftTest(
            testsDir: tempDir,
            schemaType: "AppSchemaV1",
            appTarget: "MyApp",
            version: "1.0.0"
        )

        #expect(result.created == true)
        #expect(result.fileName == "AppSchemaV1_DriftTests.swift")

        // Verify file was created
        let filePath = tempDir.appendingPathComponent(result.fileName)
        #expect(FileManager.default.fileExists(atPath: filePath.path))

        // Verify content contains expected elements
        let content = try String(contentsOf: filePath)
        #expect(content.contains("import Testing"))
        #expect(content.contains("@testable import MyApp"))
        #expect(content.contains("AppSchemaV1.__freezeray_check_1_0_0()"))
        #expect(content.contains("TODO"))
    }

    @Test("scaffoldDriftTest skips existing file")
    func testScaffoldDriftTest_SkipsExistingFile() throws {
        let scaffolding = TestScaffolding()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create existing file
        let fileName = "AppSchemaV1_DriftTests.swift"
        let filePath = tempDir.appendingPathComponent(fileName)
        try "// Existing user content".write(to: filePath, atomically: true, encoding: .utf8)

        let result = try scaffolding.scaffoldDriftTest(
            testsDir: tempDir,
            schemaType: "AppSchemaV1",
            appTarget: "MyApp",
            version: "1.0.0"
        )

        #expect(result.created == false)
        #expect(result.fileName == fileName)

        // Verify existing content wasn't modified
        let content = try String(contentsOf: filePath)
        #expect(content == "// Existing user content")
    }

    // MARK: - scaffoldMigrationTest Tests

    @Test("scaffoldMigrationTest creates new file when it doesn't exist")
    func testScaffoldMigrationTest_CreatesNewFile() throws {
        let scaffolding = TestScaffolding()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let result = try scaffolding.scaffoldMigrationTest(
            testsDir: tempDir,
            migrationPlan: "AppMigrations",
            fromVersion: "1.0.0",
            fromSchemaType: "AppSchemaV1",
            toVersion: "2.0.0",
            toSchemaType: "AppSchemaV2",
            appTarget: "MyApp"
        )

        #expect(result.created == true)
        #expect(result.fileName == "MigrateV1_0_0toV2_0_0_Tests.swift")

        // Verify file was created
        let filePath = tempDir.appendingPathComponent(result.fileName)
        #expect(FileManager.default.fileExists(atPath: filePath.path))

        // Verify content contains expected elements
        let content = try String(contentsOf: filePath)
        #expect(content.contains("import Testing"))
        #expect(content.contains("@testable import MyApp"))
        #expect(content.contains("FreezeRayRuntime.testMigration"))
        #expect(content.contains("AppSchemaV1.self"))
        #expect(content.contains("AppSchemaV2.self"))
        #expect(content.contains("AppMigrations.self"))
        #expect(content.contains("TODO"))
        #expect(content.contains("v1.0.0 → v2.0.0"))
    }

    @Test("scaffoldMigrationTest skips existing file")
    func testScaffoldMigrationTest_SkipsExistingFile() throws {
        let scaffolding = TestScaffolding()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create existing file
        let fileName = "MigrateV1_0_0toV2_0_0_Tests.swift"
        let filePath = tempDir.appendingPathComponent(fileName)
        try "// Existing migration test".write(to: filePath, atomically: true, encoding: .utf8)

        let result = try scaffolding.scaffoldMigrationTest(
            testsDir: tempDir,
            migrationPlan: "AppMigrations",
            fromVersion: "1.0.0",
            fromSchemaType: "AppSchemaV1",
            toVersion: "2.0.0",
            toSchemaType: "AppSchemaV2",
            appTarget: "MyApp"
        )

        #expect(result.created == false)
        #expect(result.fileName == fileName)

        // Verify existing content wasn't modified
        let content = try String(contentsOf: filePath)
        #expect(content == "// Existing migration test")
    }

    // MARK: - Migration Plan Discovery Tests

    @Test("discoverMacros finds SchemaMigrationPlan conformance")
    func testDiscoverMacros_FindsMigrationPlan() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a test Swift file with both @FreezeSchema and SchemaMigrationPlan
        let testFile = tempDir.appendingPathComponent("Schemas.swift")
        let testContent = """
        import SwiftData
        import FreezeRay

        @FreezeSchema(version: "1.0.0")
        enum AppSchemaV1: VersionedSchema {
            static let versionIdentifier = Schema.Version(1, 0, 0)
        }

        @FreezeSchema(version: "2.0.0")
        enum AppSchemaV2: VersionedSchema {
            static let versionIdentifier = Schema.Version(2, 0, 0)
        }

        enum AppMigrations: SchemaMigrationPlan {
            static var schemas: [any VersionedSchema.Type] {
                [AppSchemaV1.self, AppSchemaV2.self]
            }
        }
        """
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let result = try discoverMacros(in: [tempDir.path])

        // Should find both freeze annotations
        #expect(result.freezeAnnotations.count == 2)
        #expect(result.freezeAnnotations.contains(where: { $0.version == "1.0.0" }))
        #expect(result.freezeAnnotations.contains(where: { $0.version == "2.0.0" }))

        // Should find the migration plan
        #expect(result.migrationPlans.count == 1)
        #expect(result.migrationPlans.first?.typeName == "AppMigrations")
    }

    @Test("discoverMacros handles files without migration plan")
    func testDiscoverMacros_NoMigrationPlan() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create a test Swift file with only @FreezeSchema
        let testFile = tempDir.appendingPathComponent("Schemas.swift")
        let testContent = """
        import SwiftData
        import FreezeRay

        @FreezeSchema(version: "1.0.0")
        enum AppSchemaV1: VersionedSchema {
            static let versionIdentifier = Schema.Version(1, 0, 0)
        }
        """
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let result = try discoverMacros(in: [tempDir.path])

        // Should find freeze annotation
        #expect(result.freezeAnnotations.count == 1)

        // Should not find any migration plans
        #expect(result.migrationPlans.isEmpty)
    }

    @Test("discoverMacros handles multiple migration plans")
    func testDiscoverMacros_MultipleMigrationPlans() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create test Swift files with multiple migration plans (edge case)
        let testFile1 = tempDir.appendingPathComponent("Migrations1.swift")
        let testContent1 = """
        import SwiftData

        enum AppMigrations: SchemaMigrationPlan {
            static var schemas: [any VersionedSchema.Type] { [] }
        }
        """
        try testContent1.write(to: testFile1, atomically: true, encoding: .utf8)

        let testFile2 = tempDir.appendingPathComponent("Migrations2.swift")
        let testContent2 = """
        import SwiftData

        enum LegacyMigrations: SchemaMigrationPlan {
            static var schemas: [any VersionedSchema.Type] { [] }
        }
        """
        try testContent2.write(to: testFile2, atomically: true, encoding: .utf8)

        let result = try discoverMacros(in: [tempDir.path])

        // Should find both migration plans
        #expect(result.migrationPlans.count == 2)
        #expect(result.migrationPlans.contains(where: { $0.typeName == "AppMigrations" }))
        #expect(result.migrationPlans.contains(where: { $0.typeName == "LegacyMigrations" }))
    }

    @Test("discoverMacros finds @FreezeRay.FreezeSchema fully qualified syntax")
    func testDiscoverMacros_FullyQualifiedMacro() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create test file with fully qualified macro syntax
        let testFile = tempDir.appendingPathComponent("Schemas.swift")
        let testContent = """
        import SwiftData

        @FreezeRay.FreezeSchema(version: "1.0.0")
        enum AppSchemaV1: VersionedSchema {
            static let versionIdentifier = Schema.Version(1, 0, 0)
        }
        """
        try testContent.write(to: testFile, atomically: true, encoding: .utf8)

        let result = try discoverMacros(in: [tempDir.path])

        // Should find the freeze annotation even with fully qualified syntax
        #expect(result.freezeAnnotations.count == 1)
        #expect(result.freezeAnnotations.first?.version == "1.0.0")
        #expect(result.freezeAnnotations.first?.typeName == "AppSchemaV1")
    }
}

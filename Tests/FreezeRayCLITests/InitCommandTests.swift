import Testing
import Foundation
@testable import freezeray_cli

/// Unit tests for InitCommand helper functions
@Suite("InitCommand Helper Tests")
struct InitCommandTests {

    // MARK: - Project Type Detection Tests

    @Test("detectProjectType finds Swift Package")
    func testDetectProjectType_SwiftPackage() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create Package.swift
        let packageSwiftPath = tempDir.appendingPathComponent("Package.swift")
        try "// swift-tools-version: 5.9\nimport PackageDescription".write(to: packageSwiftPath, atomically: true, encoding: .utf8)

        let projectType = try detectProjectType(in: tempDir)

        switch projectType {
        case .swiftPackage(let path):
            #expect(path == packageSwiftPath.path)
        case .xcodeProject:
            Issue.record("Expected Swift Package, got Xcode Project")
        }
    }

    @Test("detectProjectType finds Xcode project")
    func testDetectProjectType_XcodeProject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create .xcodeproj directory
        let projectPath = tempDir.appendingPathComponent("TestApp.xcodeproj")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)

        let projectType = try detectProjectType(in: tempDir)

        switch projectType {
        case .swiftPackage:
            Issue.record("Expected Xcode Project, got Swift Package")
        case .xcodeProject(let path):
            // Normalize paths to handle /var vs /private/var symlink on macOS
            let normalizedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
            let normalizedExpected = projectPath.resolvingSymlinksInPath().path
            #expect(normalizedPath == normalizedExpected)
        }
    }

    @Test("detectProjectType prefers Package.swift when both exist")
    func testDetectProjectType_PreferPackageSwift() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create both Package.swift and .xcodeproj
        let packageSwiftPath = tempDir.appendingPathComponent("Package.swift")
        try "// swift-tools-version: 5.9\nimport PackageDescription".write(to: packageSwiftPath, atomically: true, encoding: .utf8)

        let projectPath = tempDir.appendingPathComponent("TestApp.xcodeproj")
        try FileManager.default.createDirectory(at: projectPath, withIntermediateDirectories: true)

        let projectType = try detectProjectType(in: tempDir)

        // Should prefer Package.swift
        switch projectType {
        case .swiftPackage:
            break // Expected
        case .xcodeProject:
            Issue.record("Expected Swift Package (should prefer Package.swift when both exist)")
        }
    }

    @Test("detectProjectType throws when no project found")
    func testDetectProjectType_NoProject() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        do {
            _ = try detectProjectType(in: tempDir)
            Issue.record("Expected error to be thrown")
        } catch is InitError {
            // Expected
        } catch {
            Issue.record("Expected InitError, got \(type(of: error))")
        }
    }

    // MARK: - Directory Structure Tests

    @Test("createDirectoryStructure creates expected directories")
    func testCreateDirectoryStructure_CreatesDirectories() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try createDirectoryStructure(in: tempDir)

        // Check FreezeRay directory exists
        let freezeRayDir = tempDir.appendingPathComponent("FreezeRay")
        #expect(FileManager.default.fileExists(atPath: freezeRayDir.path))

        // Check Fixtures subdirectory
        let fixturesDir = freezeRayDir.appendingPathComponent("Fixtures")
        #expect(FileManager.default.fileExists(atPath: fixturesDir.path))

        // Check Tests subdirectory
        let testsDir = freezeRayDir.appendingPathComponent("Tests")
        #expect(FileManager.default.fileExists(atPath: testsDir.path))

        // Check README exists
        let readmePath = freezeRayDir.appendingPathComponent("README.md")
        #expect(FileManager.default.fileExists(atPath: readmePath.path))

        // Verify README content
        let readmeContent = try String(contentsOf: readmePath)
        #expect(readmeContent.contains("FreezeRay"))
        #expect(readmeContent.contains("Fixtures"))
        #expect(readmeContent.contains("Tests"))
    }

    @Test("createDirectoryStructure is idempotent")
    func testCreateDirectoryStructure_Idempotent() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create once
        try createDirectoryStructure(in: tempDir)

        // Create again - should not throw
        try createDirectoryStructure(in: tempDir)

        // Verify structure still exists
        let freezeRayDir = tempDir.appendingPathComponent("FreezeRay")
        #expect(FileManager.default.fileExists(atPath: freezeRayDir.path))
    }

    // MARK: - Package.swift Modification Tests

    @Test("addDependencyToPackage adds FreezeRay dependency")
    func testAddDependencyToPackage_AddsDependency() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create Package.swift
        let packageSwiftPath = tempDir.appendingPathComponent("Package.swift")
        let packageContent = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "TestApp",
            dependencies: [
                .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.0.0"),
            ],
            targets: []
        )
        """
        try packageContent.write(to: packageSwiftPath, atomically: true, encoding: .utf8)

        try addDependencyToPackage(packagePath: packageSwiftPath.path)

        // Verify FreezeRay was added
        let modifiedContent = try String(contentsOf: packageSwiftPath)
        #expect(modifiedContent.contains("FreezeRay"))
        #expect(modifiedContent.contains("TrinsicVentures/FreezeRay"))
        #expect(modifiedContent.contains("0.4.0"))
    }

    @Test("addDependencyToPackage skips if already exists")
    func testAddDependencyToPackage_SkipsIfExists() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create Package.swift with FreezeRay already added
        let packageSwiftPath = tempDir.appendingPathComponent("Package.swift")
        let packageContent = """
        // swift-tools-version: 5.9
        import PackageDescription

        let package = Package(
            name: "TestApp",
            dependencies: [
                .package(url: "https://github.com/TrinsicVentures/FreezeRay.git", from: "0.4.0"),
            ],
            targets: []
        )
        """
        try packageContent.write(to: packageSwiftPath, atomically: true, encoding: .utf8)

        // Should not throw, should skip
        try addDependencyToPackage(packagePath: packageSwiftPath.path)

        // Verify FreezeRay only appears once
        let modifiedContent = try String(contentsOf: packageSwiftPath)
        let occurrences = modifiedContent.components(separatedBy: "FreezeRay").count - 1
        #expect(occurrences == 1, "FreezeRay should only appear once")
    }
}

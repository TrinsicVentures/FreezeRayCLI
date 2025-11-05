import ArgumentParser
import Foundation
import XcodeProj
import PathKit

struct FreezeCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "freeze",
        abstract: "Freeze a schema version by generating immutable fixture artifacts"
    )

    @Argument(help: "Schema version to freeze (e.g., \"1.0.0\")")
    var version: String

    @Option(name: .long, help: "Path to .freezeray.yml config file")
    var config: String?

    @Option(name: .long, help: "Simulator to use (default: iPhone 17)")
    var simulator: String = "iPhone 17"

    @Option(name: .long, help: "Xcode scheme to use (auto-detected if not specified)")
    var scheme: String?

    @Flag(name: .long, help: "Overwrite existing frozen fixtures (dangerous!)")
    var force: Bool = false

    @Option(name: .long, help: "Override output directory for fixtures")
    var output: String?

    func run() throws {
        print("🔹 FreezeRay v0.5.0")
        print("🔹 Freezing schema version: \(version)")
        print("")

        // 1. Auto-detect project
        print("🔹 Auto-detecting project configuration...")
        let workingDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let projectPath = try SimulatorManager.discoverProject(in: workingDir)
        print("   Found: \(projectPath.components(separatedBy: "/").last ?? projectPath)")

        let discoveredScheme: String
        if let userScheme = scheme {
            discoveredScheme = userScheme
            print("   Scheme: \(discoveredScheme) (user-specified)")
        } else {
            discoveredScheme = try SimulatorManager.discoverScheme(projectPath: projectPath)
            print("   Scheme: \(discoveredScheme) (auto-detected)")
        }

        let testTarget = SimulatorManager.inferTestTarget(from: discoveredScheme)
        print("   Test target: \(testTarget) (inferred)")
        print("")

        // 2. Discover @Freeze(version: "X.X.X") annotations
        print("🔹 Parsing source files for @Freeze(version: \"\(version)\")...")
        let sourcePaths = [workingDir.path]  // TODO: Support custom source paths from config
        let discovery = try discoverMacros(in: sourcePaths)

        guard let freezeAnnotation = discovery.freezeAnnotations.first(where: { $0.version == version }) else {
            throw FreezeRayError.schemaNotFound(version: version)
        }

        print("   Found: \(freezeAnnotation.typeName) in \(freezeAnnotation.filePath)")
        print("")

        // 3. Check if fixtures already exist
        let fixturesDir = output.map { URL(fileURLWithPath: $0) } ??
            workingDir.appendingPathComponent("FreezeRay/Fixtures/\(version)")

        if FileManager.default.fileExists(atPath: fixturesDir.path) && !force {
            throw FreezeRayError.fixturesAlreadyExist(path: fixturesDir.path, version: version)
        }

        if force {
            print("⚠️  WARNING: Overwriting existing fixtures for v\(version)")
            print("⚠️  Frozen schemas should be immutable once shipped to production!")
            print("")
            try? FileManager.default.removeItem(at: fixturesDir)
        }

        // 4. Generate temporary freeze test
        print("🔹 Generating freeze test...")
        // Convention: app target is test target without "Tests" suffix
        let appTarget = testTarget.replacingOccurrences(of: "Tests", with: "")
        let testFilePath = try FreezeCommand.generateFreezeTest(
            workingDir: workingDir,
            testTarget: testTarget,
            appTarget: appTarget,
            schemaType: freezeAnnotation.typeName,
            version: version
        )
        defer {
            // Clean up temporary test file
            try? FileManager.default.removeItem(at: testFilePath)
        }

        // 5. Run freeze operation in simulator
        let manager = SimulatorManager()
        let simulatorFixturesURL = try manager.runFreezeInSimulator(
            projectPath: projectPath,
            scheme: discoveredScheme,
            testTarget: testTarget,
            schemaType: freezeAnnotation.typeName,
            version: version,
            simulator: simulator
        )

        // 6. Copy fixtures from simulator to project
        print("🔹 Extracting fixtures from simulator...")
        try FileManager.default.createDirectory(
            at: fixturesDir.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try FileManager.default.copyItem(at: simulatorFixturesURL, to: fixturesDir)

        let files = try FileManager.default.contentsOfDirectory(atPath: fixturesDir.path)
        for file in files {
            print("   Copied: \(file) → \(fixturesDir.path)/")
        }
        print("")

        // 7. Scaffold drift test
        print("🔹 Scaffolding drift test...")
        let testsDir = workingDir.appendingPathComponent("FreezeRay/Tests")
        try? FileManager.default.createDirectory(at: testsDir, withIntermediateDirectories: true)

        let scaffolding = TestScaffolding()
        let scaffoldResult = try scaffolding.scaffoldDriftTest(
            testsDir: testsDir,
            schemaType: freezeAnnotation.typeName,
            appTarget: appTarget,
            version: version
        )

        var createdTestFiles: [String] = []
        if scaffoldResult.created {
            print("   Created: \(scaffoldResult.fileName)")
            createdTestFiles.append(scaffoldResult.fileName)
        } else {
            print("   Skipped: \(scaffoldResult.fileName) (already exists)")
        }

        // 8. Add scaffolded test files to Xcode test target (if Xcode project)
        if projectPath.hasSuffix(".xcodeproj") {
            do {
                // Add test files to sources
                if !createdTestFiles.isEmpty {
                    try FreezeCommand.addTestFilesToXcodeProject(
                        projectPath: projectPath,
                        testTarget: testTarget,
                        testFiles: createdTestFiles,
                        testsDir: testsDir
                    )
                    print("   ✅ Added test files to \(testTarget) target")
                }

                // Add fixtures folder as bundle resource (if not already added)
                try FreezeCommand.addFixturesToTestTarget(
                    projectPath: projectPath,
                    testTarget: testTarget,
                    fixturesDir: fixturesDir.deletingLastPathComponent().deletingLastPathComponent() // FreezeRay folder
                )
                print("   ✅ Added FreezeRay/Fixtures to test bundle resources")
            } catch {
                print("   ⚠️  Could not update Xcode project: \(error)")
                print("   You may need to manually add files/resources to the test target")
            }
        }
        print("")

        print("✅ Schema v\(version) frozen successfully!")
        print("")
        print("📝 Next steps:")
        print("   1. Review fixtures: \(fixturesDir.path)")
        if scaffoldResult.created {
            print("   2. Customize drift test: FreezeRay/Tests/\(scaffoldResult.fileName)")
            print("   3. Add FreezeRay/ folder to Xcode project if needed")
        } else {
            print("   2. Add FreezeRay/ folder to Xcode project if needed")
        }
        print("   4. Run tests: xcodebuild test -scheme \(discoveredScheme)")
        print("   5. Commit to git: git add FreezeRay/")
    }
}

enum FreezeRayError: Error, CustomStringConvertible {
    case custom(String)
    case schemaNotFound(version: String)
    case fixturesAlreadyExist(path: String, version: String)

    var description: String {
        switch self {
        case .custom(let message):
            return "❌ \(message)"
        case .schemaNotFound(let version):
            return """
            ❌ No @Freeze(version: "\(version)") annotation found in source files

            Please add @Freeze(version: "\(version)") to your schema:

            @Freeze(version: "\(version)")
            enum SchemaV\(version.replacingOccurrences(of: ".", with: "_")): VersionedSchema {
                // ...
            }
            """
        case .fixturesAlreadyExist(let path, let version):
            return """
            ❌ Fixtures for v\(version) already exist at \(path)

            Frozen schemas are immutable. If you need to update the schema:
              1. Create a new schema version (e.g., v\(nextVersion(version)))
              2. Add a migration from v\(version) → v\(nextVersion(version))
              3. Freeze the new version: freezeray freeze \(nextVersion(version))

            To overwrite existing fixtures (⚠️  DANGEROUS):
              freezeray freeze \(version) --force
            """
        }
    }

    private func nextVersion(_ version: String) -> String {
        let components = version.split(separator: ".").compactMap { Int($0) }
        guard components.count == 3 else { return version }
        return "\(components[0]).\(components[1]).\(components[2] + 1)"
    }
}

// MARK: - Freeze Test Generation

extension FreezeCommand {

    /// Generates a temporary test file that calls the macro-generated freeze function
    /// Returns the path to the generated test file
    public static func generateFreezeTest(
        workingDir: URL,
        testTarget: String,
        appTarget: String,
        schemaType: String,
        version: String
    ) throws -> URL {
        let versionSafe = version.replacingOccurrences(of: ".", with: "_")
        let functionName = "__freezeray_freeze_\(versionSafe)"

        let testContent = """
        // AUTO-GENERATED by FreezeRay CLI - DO NOT EDIT
        // This file is temporary and will be deleted after the freeze operation

        import XCTest
        import FreezeRay
        @testable import \(appTarget)

        /// Temporary freeze test for schema version \(version)
        /// Invoked by: freezeray freeze \(version)
        final class FreezeSchemaV\(versionSafe)_Test: XCTestCase {

            func testFreezeSchemaV\(versionSafe)() throws {
                try \(schemaType).\(functionName)()
            }
        }

        """

        // Write to test target directory
        let testTargetDir = workingDir.appendingPathComponent(testTarget)
        let testFilePath = testTargetDir.appendingPathComponent("FreezeSchemaV\(versionSafe)_Test.swift")

        // Ensure test target directory exists before writing
        if !FileManager.default.fileExists(atPath: testTargetDir.path) {
            try FileManager.default.createDirectory(at: testTargetDir, withIntermediateDirectories: true)
        }

        try testContent.write(to: testFilePath, atomically: true, encoding: .utf8)
        print("   Generated: \(testFilePath.lastPathComponent)")

        return testFilePath
    }

    /// Adds FreezeRay/Fixtures folder to the test target's resources build phase
    public static func addFixturesToTestTarget(
        projectPath: String,
        testTarget: String,
        fixturesDir: URL
    ) throws {
        let path = Path(projectPath)
        let xcodeproj = try XcodeProj(path: path)
        guard let project = xcodeproj.pbxproj.projects.first else {
            throw FreezeRayError.custom("No project found in .pbxproj")
        }

        // Find the test target
        guard let target = project.targets.first(where: { $0.name == testTarget }) else {
            throw FreezeRayError.custom("Could not find test target: \(testTarget)")
        }

        // Get or create resources build phase
        let resourcesBuildPhase: PBXResourcesBuildPhase
        if let existing = target.buildPhases.first(where: { $0 is PBXResourcesBuildPhase }) as? PBXResourcesBuildPhase {
            resourcesBuildPhase = existing
        } else {
            // Create new resources build phase if none exists
            resourcesBuildPhase = PBXResourcesBuildPhase()
            xcodeproj.pbxproj.add(object: resourcesBuildPhase)
            target.buildPhases.append(resourcesBuildPhase)
        }

        // Check if FreezeRay folder reference already exists
        let freezeRayPath = "FreezeRay"
        let alreadyAdded = resourcesBuildPhase.files?.contains(where: { buildFile in
            buildFile.file?.path == freezeRayPath || buildFile.file?.name == "FreezeRay"
        }) ?? false

        if !alreadyAdded {
            // Create folder reference for FreezeRay directory
            let folderRef = PBXFileReference(
                sourceTree: .group,
                name: "FreezeRay",
                lastKnownFileType: "folder",
                path: freezeRayPath
            )
            xcodeproj.pbxproj.add(object: folderRef)

            // Create build file
            let buildFile = PBXBuildFile(file: folderRef)
            xcodeproj.pbxproj.add(object: buildFile)

            // Add to resources build phase
            if resourcesBuildPhase.files == nil {
                resourcesBuildPhase.files = []
            }
            resourcesBuildPhase.files?.append(buildFile)
        }

        // Save modified project
        try xcodeproj.write(path: path)
    }

    /// Adds scaffolded test files to the Xcode test target's sources build phase
    public static func addTestFilesToXcodeProject(
        projectPath: String,
        testTarget: String,
        testFiles: [String],
        testsDir: URL
    ) throws {
        let path = Path(projectPath)
        let xcodeproj = try XcodeProj(path: path)
        guard let project = xcodeproj.pbxproj.projects.first else {
            throw FreezeRayError.custom("No project found in .pbxproj")
        }

        // Find the test target
        guard let target = project.targets.first(where: { $0.name == testTarget }) else {
            throw FreezeRayError.custom("Could not find test target: \(testTarget)")
        }

        // Get or create sources build phase
        guard let sourcesBuildPhase = target.buildPhases.first(where: { $0 is PBXSourcesBuildPhase }) as? PBXSourcesBuildPhase else {
            throw FreezeRayError.custom("Could not find sources build phase for \(testTarget)")
        }

        // Add each test file
        for testFile in testFiles {
            let testFilePath = "FreezeRay/Tests/\(testFile)"

            // Check if file is already in build phase
            let alreadyAdded = sourcesBuildPhase.files?.contains(where: { buildFile in
                buildFile.file?.path == testFilePath || buildFile.file?.name == testFile
            }) ?? false

            if !alreadyAdded {
                // Create file reference
                let fileRef = PBXFileReference(
                    sourceTree: .group,
                    name: testFile,
                    lastKnownFileType: "sourcecode.swift",
                    path: testFilePath
                )
                xcodeproj.pbxproj.add(object: fileRef)

                // Create build file
                let buildFile = PBXBuildFile(file: fileRef)
                xcodeproj.pbxproj.add(object: buildFile)

                // Add to sources build phase
                if sourcesBuildPhase.files == nil {
                    sourcesBuildPhase.files = []
                }
                sourcesBuildPhase.files?.append(buildFile)
            }
        }

        // Save modified project
        try xcodeproj.write(path: path)
    }

    /// Convenience overload that accepts URL array instead of String array
    public static func addTestFilesToXcodeProject(
        projectPath: String,
        testTarget: String,
        testFiles: [URL]
    ) throws {
        let fileNames = testFiles.map { $0.lastPathComponent }
        try addTestFilesToXcodeProject(
            projectPath: projectPath,
            testTarget: testTarget,
            testFiles: fileNames,
            testsDir: testFiles.first?.deletingLastPathComponent() ?? URL(fileURLWithPath: "")
        )
    }

}

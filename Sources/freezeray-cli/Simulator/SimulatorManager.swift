// Sources/freezeray-cli/Simulator/SimulatorManager.swift

import Foundation

enum SimulatorError: Error, CustomStringConvertible {
    case simulatorNotFound(String)
    case buildFailed(output: String)
    case testFailed(output: String)
    case containerNotFound(bundleID: String)
    case fixturesNotFound(URL)
    case invalidOutput(String)

    var description: String {
        switch self {
        case .simulatorNotFound(let name):
            return "Simulator '\(name)' not found. Use 'xcrun simctl list devices' to see available simulators."
        case .buildFailed(let output):
            return "Build failed:\n\(output)"
        case .testFailed(let output):
            return "Test execution failed:\n\(output)"
        case .containerNotFound(let bundleID):
            return "Could not find app container for bundle ID: \(bundleID)"
        case .fixturesNotFound(let url):
            return "Fixtures not found at expected location: \(url.path)"
        case .invalidOutput(let message):
            return "Invalid command output: \(message)"
        }
    }
}

struct SimulatorManager {

    /// Runs the freeze operation in iOS simulator and extracts fixtures
    /// - Parameters:
    ///   - projectPath: Path to .xcodeproj or .xcworkspace
    ///   - scheme: Xcode scheme name
    ///   - testTarget: Test target name
    ///   - schemaType: Schema type name (e.g., "SchemaV1")
    ///   - version: Version string (e.g., "1.0.0")
    ///   - simulator: Simulator name (e.g., "iPhone 17")
    /// - Returns: URL to the extracted fixtures directory
    func runFreezeInSimulator(
        projectPath: String,
        scheme: String,
        testTarget: String,
        schemaType: String,
        version: String,
        simulator: String = "iPhone 17"
    ) throws -> URL {
        // Validate simulator exists and get its UUID
        let simulatorID = try getSimulatorID(simulator)
        print("   Simulator ID: \(simulatorID)")

        // Boot simulator if not already booted
        print("   Booting simulator...")
        try bootSimulator(simulatorID)

        // Build and run freeze test in one step
        // Using 'test' instead of 'build-for-testing' + 'test-without-building'
        // This ensures the newly generated test file gets compiled
        print("🔹 Building and running freeze test in simulator...")
        _ = try buildAndRunFreezeTest(
            projectPath: projectPath,
            scheme: scheme,
            testTarget: testTarget,
            version: version,
            simulator: simulator
        )

        // 3. Extract fixtures from /tmp (where FreezeRayRuntime exports them)
        // The runtime automatically copies fixtures to /tmp during test execution
        // because XCTestDevices directories are ephemeral
        print("🔹 Extracting fixtures from /tmp...")
        let fixturesURL = URL(fileURLWithPath: "/tmp/FreezeRay/Fixtures/\(version)")

        // Verify fixtures exist
        guard FileManager.default.fileExists(atPath: fixturesURL.path) else {
            throw SimulatorError.fixturesNotFound(fixturesURL)
        }

        // List fixtures found
        if let files = try? FileManager.default.contentsOfDirectory(atPath: fixturesURL.path) {
            print("   Found \(files.count) fixture files:")
            for file in files.sorted() {
                print("      - \(file)")
            }
        }

        return fixturesURL
    }

    // MARK: - Private Helpers

    private func validateSimulator(_ name: String) throws {
        // List available simulators
        let output = try shell("xcrun", "simctl", "list", "devices", "available")

        // Check if simulator exists
        if !output.contains(name) {
            throw SimulatorError.simulatorNotFound(name)
        }
    }

    private func buildAndRunFreezeTest(
        projectPath: String,
        scheme: String,
        testTarget: String,
        version: String,
        simulator: String
    ) throws -> String {
        let projectArg: String
        if projectPath.hasSuffix(".xcworkspace") {
            projectArg = "-workspace"
        } else {
            projectArg = "-project"
        }

        let destination = "platform=iOS Simulator,name=\(simulator)"

        // The test should be named FreezeSchemaV{version}
        // e.g., for version "1.0.0", test name is "FreezeSchemaV1_0_0_Test"
        let versionSafe = version.replacingOccurrences(of: ".", with: "_")
        let testName = "\(testTarget)/FreezeSchemaV\(versionSafe)_Test"

        // Use 'test' (not 'build-for-testing' + 'test-without-building')
        // This ensures the newly generated test file gets compiled
        let output = try shell(
            "xcodebuild",
            projectArg, projectPath,
            "-scheme", scheme,
            "-destination", destination,
            "test",
            "-only-testing:\(testName)"
        )

        // Check for build failures
        if output.contains("** BUILD FAILED **") {
            throw SimulatorError.buildFailed(output: output)
        }

        // Check for test failures
        if output.contains("** TEST FAILED **") {
            throw SimulatorError.testFailed(output: output)
        }

        // Get bundle ID from the built app's Info.plist
        let bundleID = try extractBundleID(scheme: scheme)
        return bundleID
    }

    private func extractBundleID(scheme: String) throws -> String {
        // For an iOS app, the bundle ID is typically reverse DNS like com.company.AppName
        // We'll try to read it from the most recently built app
        // For now, use a reasonable default based on scheme name
        // TODO: Actually parse Info.plist from DerivedData
        return "com.example.\(scheme)"
    }

    private func getSimulatorID(_ name: String) throws -> String {
        // List all devices and find the UUID for the given simulator name
        let output = try shell("xcrun", "simctl", "list", "devices", "available")

        // Parse output to find simulator UUID
        // Format: "iPhone 17 (EF44DCDC-18F2-470E-A901-1B8C19A6D2E5) (Shutdown)"
        let lines = output.components(separatedBy: .newlines)
        for line in lines {
            if line.contains(name) {
                // Extract UUID from parentheses
                if let uuidStart = line.range(of: "("),
                   let uuidEnd = line.range(of: ")", range: uuidStart.upperBound..<line.endIndex) {
                    let uuid = String(line[uuidStart.upperBound..<uuidEnd.lowerBound])
                    // Validate it's a UUID format
                    if uuid.count == 36 && uuid.contains("-") {
                        return uuid
                    }
                }
            }
        }

        throw SimulatorError.simulatorNotFound(name)
    }

    private func bootSimulator(_ simulatorID: String) throws {
        // Try to boot the simulator, ignore if already booted
        _ = try? shell("xcrun", "simctl", "boot", simulatorID)
    }

    private func findSimulatorContainer(
        bundleID: String,
        simulatorID: String
    ) throws -> URL {
        // Get app container path using simulator ID (not "booted")
        // This avoids race conditions when simulator shuts down after test
        let output = try shell(
            "xcrun", "simctl", "get_app_container",
            simulatorID,
            bundleID,
            "data"
        )

        let path = output.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !path.isEmpty else {
            throw SimulatorError.containerNotFound(bundleID: bundleID)
        }

        return URL(fileURLWithPath: path)
    }

    private func shell(_ args: String...) throws -> String {
        let process = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = errorPipe

        // Read output asynchronously to prevent pipe buffer deadlock
        var outputData = Data()
        var errorData = Data()

        let outputHandle = pipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading

        // Set up background reading to prevent deadlock
        let outputQueue = DispatchQueue(label: "com.freezeray.stdout")
        let errorQueue = DispatchQueue(label: "com.freezeray.stderr")

        outputQueue.async {
            outputData = outputHandle.readDataToEndOfFile()
        }

        errorQueue.async {
            errorData = errorHandle.readDataToEndOfFile()
        }

        try process.run()
        process.waitUntilExit()

        // Wait for background reads to complete
        outputQueue.sync {}
        errorQueue.sync {}

        let output = String(data: outputData, encoding: .utf8) ?? ""
        let errorOutput = String(data: errorData, encoding: .utf8) ?? ""

        if process.terminationStatus != 0 {
            throw SimulatorError.invalidOutput(
                "Command failed: \(args.joined(separator: " "))\n\(errorOutput)"
            )
        }

        return output + errorOutput
    }
}

// MARK: - Project Discovery

extension SimulatorManager {

    /// Auto-discovers project file (*.xcodeproj or *.xcworkspace)
    static func discoverProject(in directory: URL) throws -> String {
        let fm = FileManager.default
        let contents = try fm.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )

        // Prefer workspace over project
        if let workspace = contents.first(where: { $0.pathExtension == "xcworkspace" }) {
            return workspace.path
        }

        if let project = contents.first(where: { $0.pathExtension == "xcodeproj" }) {
            return project.path
        }

        throw SimulatorError.invalidOutput("No .xcodeproj or .xcworkspace found in \(directory.path)")
    }

    /// Auto-discovers scheme by listing available schemes
    static func discoverScheme(projectPath: String) throws -> String {
        let projectArg: String
        if projectPath.hasSuffix(".xcworkspace") {
            projectArg = "-workspace"
        } else {
            projectArg = "-project"
        }

        let manager = SimulatorManager()
        let output = try manager.shell("xcodebuild", projectArg, projectPath, "-list")

        // Parse output to find schemes
        // Output format:
        // Schemes:
        //     Clearly
        //     ClearlyTests

        let lines = output.components(separatedBy: .newlines)
        var inSchemesSection = false
        var schemes: [String] = []

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "Schemes:" {
                inSchemesSection = true
                continue
            }

            if inSchemesSection {
                if trimmed.isEmpty {
                    // Empty line marks end of schemes section
                    break
                } else if !trimmed.isEmpty {
                    schemes.append(trimmed)
                }
            }
        }

        guard !schemes.isEmpty else {
            throw SimulatorError.invalidOutput("No schemes found in project")
        }

        // Smart scheme selection: prefer app schemes over library/test schemes
        // Priority:
        // 1. Schemes ending with "App" (e.g., "FreezeRayTestApp")
        // 2. Schemes NOT containing Tests/CLI/E2E
        // 3. First scheme as fallback

        // First, try to find schemes ending with "App"
        if let appScheme = schemes.first(where: { $0.hasSuffix("App") }) {
            return appScheme
        }

        // Second, filter out obvious non-app schemes
        let appSchemes = schemes.filter { scheme in
            !scheme.hasSuffix("Tests") &&
            !scheme.hasSuffix("CLI") &&
            !scheme.contains("E2E")
        }

        // If we found app-like schemes, prefer ones with more specific names
        // (longer names are usually more specific, like "MyProjectTestApp" vs "freezeray")
        if let appScheme = appSchemes.max(by: { $0.count < $1.count }) {
            return appScheme
        }

        // Otherwise, fall back to first scheme (better than nothing)
        return schemes.first!
    }

    /// Infers test target from scheme name (typically {SchemeName}Tests)
    static func inferTestTarget(from scheme: String) -> String {
        return "\(scheme)Tests"
    }
}

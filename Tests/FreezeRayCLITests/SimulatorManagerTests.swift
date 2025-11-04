import Testing
import Foundation
@testable import freezeray_cli

/// Tests for SimulatorManager test target inference logic
/// Ensures build configuration suffixes are properly stripped to match actual test targets
@Suite("SimulatorManager Helper Tests")
struct SimulatorManagerTests {

    @Test("inferTestTarget strips DEBUG suffix - original bug case")
    func testInferTestTarget_DEBUGSuffix() {
        // Bug: "Clearly DEBUG" was producing "Clearly DEBUGTests" instead of "ClearlyTests"
        let result = SimulatorManager.inferTestTarget(from: "Clearly DEBUG")
        #expect(result == "ClearlyTests")
    }

    @Test("inferTestTarget strips RELEASE suffix")
    func testInferTestTarget_RELEASESuffix() {
        let result = SimulatorManager.inferTestTarget(from: "MyApp RELEASE")
        #expect(result == "MyAppTests")
    }

    @Test("inferTestTarget handles scheme without build config")
    func testInferTestTarget_NoSuffix() {
        let result = SimulatorManager.inferTestTarget(from: "Clearly")
        #expect(result == "ClearlyTests")
    }

    @Test("inferTestTarget strips hyphenated build configs")
    func testInferTestTarget_HyphenatedSuffix() {
        let result = SimulatorManager.inferTestTarget(from: "MyApp-DEBUG")
        #expect(result == "MyAppTests")
    }
}

// DictusCore/Tests/DictusCoreTests/DeviceCapabilitiesTests.swift
import XCTest
@testable import DictusCore

/// Covers the device-tier rules that decide how Whisper is compiled (issue #370)
/// and which hardware families are Argmax-restricted (issue #362).
final class DeviceCapabilitiesTests: XCTestCase {

    private func makeCapabilities(
        ramGB: Int = 4,
        availableMB: Int = 3000,
        model: String,
        thermal: ProcessInfo.ThermalState = .nominal
    ) -> DeviceCapabilities {
        DeviceCapabilities(
            physicalMemoryGB: ramGB,
            availableMemoryMB: availableMB,
            deviceModelIdentifier: model,
            thermalState: thermal
        )
    }

    // MARK: - A12/A13 detection (issue #362)

    func testA12AndA13FamiliesAreDetected() {
        // iPhone11,x = XS / XS Max / XR (A12). iPhone12,x = 11 / 11 Pro / SE 2 (A13).
        for identifier in ["iPhone11,2", "iPhone11,4", "iPhone11,6", "iPhone11,8",
                           "iPhone12,1", "iPhone12,3", "iPhone12,5", "iPhone12,8"] {
            XCTAssertTrue(makeCapabilities(model: identifier).isA12OrA13iPhone, identifier)
        }
    }

    func testNewerAndOlderFamiliesAreNotDetected() {
        // iPhone13,x is A14 — the first tier Argmax lists Small for, and the reason
        // RAM alone cannot make this call: iPhone13,2 is 4 GB, same as an iPhone 11.
        // iPhone10,x is A11. iPhone1,x guards the prefix against a substring match.
        for identifier in ["iPhone13,2", "iPhone14,5", "iPhone15,4", "iPhone16,2",
                           "iPhone18,1", "iPhone10,3", "iPhone1,1", "iPad11,1", "arm64"] {
            XCTAssertFalse(makeCapabilities(model: identifier).isA12OrA13iPhone, identifier)
        }
    }

    /// `hasPrefix("iPhone11,")` must not be satisfied by a longer family number.
    /// Without the trailing comma, "iPhone110,1" would match — no such device exists
    /// today, but the guard costs nothing and the failure would be silent.
    func testPrefixMatchIsBoundedByTheComma() {
        XCTAssertFalse(makeCapabilities(model: "iPhone110,1").isA12OrA13iPhone)
        XCTAssertFalse(makeCapabilities(model: "iPhone120,1").isA12OrA13iPhone)
        XCTAssertFalse(makeCapabilities(model: "iPhone1,1").isA12OrA13iPhone)
    }

    // MARK: - Audio encoder compute policy (issue #370)

    func testA12A13GetCpuAndGpuAudioEncoder() {
        for identifier in ["iPhone11,2", "iPhone11,8", "iPhone12,1", "iPhone12,8"] {
            XCTAssertEqual(makeCapabilities(model: identifier).audioEncoderComputePolicy,
                           .cpuAndGPU,
                           "\(identifier) must keep the audio encoder off the Neural Engine")
        }
    }

    /// The blast-radius guarantee: every other device keeps WhisperKit's own default,
    /// which the app expresses by passing no compute options at all.
    func testEveryOtherDeviceKeepsTheWhisperKitDefault() {
        for identifier in ["iPhone13,2", "iPhone14,5", "iPhone15,4", "iPhone16,2",
                           "iPhone17,3", "iPhone18,1", "iPhone10,3", "arm64"] {
            XCTAssertEqual(makeCapabilities(model: identifier).audioEncoderComputePolicy,
                           .whisperKitDefault,
                           "\(identifier) must not have its compute path changed")
        }
    }

    /// The policy is a hardware-generation call, never a memory one. An A12/A13 with
    /// plenty of RAM still needs it; a 4 GB A14 still must not get it.
    func testPolicyIgnoresRamAndThermalState() {
        for ram in [3, 4, 6, 8, 12] {
            XCTAssertEqual(makeCapabilities(ramGB: ram, model: "iPhone12,1").audioEncoderComputePolicy,
                           .cpuAndGPU)
            XCTAssertEqual(makeCapabilities(ramGB: ram, model: "iPhone13,2").audioEncoderComputePolicy,
                           .whisperKitDefault)
        }
        XCTAssertEqual(makeCapabilities(model: "iPhone12,1", thermal: .critical).audioEncoderComputePolicy,
                       .cpuAndGPU)
    }

    /// The policy and the catalog gate must key off the same hardware test, so a
    /// device can never be handed Base by one rule and compiled for the ANE by the other.
    func testPolicyTracksTheSamePredicateAsTheCatalogGate() {
        for identifier in ["iPhone11,2", "iPhone12,1", "iPhone13,2", "iPhone16,2", "arm64"] {
            let device = makeCapabilities(model: identifier)
            XCTAssertEqual(device.audioEncoderComputePolicy == .cpuAndGPU,
                           device.isA12OrA13iPhone,
                           identifier)
        }
    }
}

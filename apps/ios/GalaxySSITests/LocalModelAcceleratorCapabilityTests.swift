import XCTest
@testable import GalaxySSI

final class LocalModelAcceleratorCapabilityTests: XCTestCase {
  func testLocalModelAcceleratorPolicyReportsAllBackendsReady() {
    let snapshot = LocalModelAcceleratorPolicy.evaluate(probe(), checkedAtMillis: 1_000)

    XCTAssertTrue(snapshot.capabilities.allSatisfy { $0.ready })
    XCTAssertEqual(snapshot[.vendorSDK].provider, "Apple Silicon")
    XCTAssertEqual(snapshot.checkedAtMillis, 1_000)
    XCTAssertEqual(snapshot.readyKinds, [.cpu, .gpu, .coreMLNeuralEngine, .vendorSDK])
  }

  func testLocalModelAcceleratorPolicyDoesNotPretendMetalDelegateIsBundled() {
    let capability = LocalModelAcceleratorPolicy.evaluate(
      probe(gpuRuntimeAvailable: false)
    )[.gpu]

    XCTAssertEqual(capability.state, .hardwareOnly)
    XCTAssertFalse(capability.ready)
    XCTAssertTrue(capability.hardwareEvidence.contains("Metal"))
    XCTAssertTrue(capability.runtimeEvidence.contains("not bundled"))
  }

  func testLocalModelAcceleratorPolicyRequiresCoreMLRuntimeForNeuralEngine() {
    let runtimeMissing = LocalModelAcceleratorPolicy.evaluate(
      probe(neuralEngineRuntimeAvailable: false)
    )[.coreMLNeuralEngine]
    let hardwareMissing = LocalModelAcceleratorPolicy.evaluate(
      probe(neuralEngineHardwareAvailable: false, neuralEngineRuntimeAvailable: true)
    )[.coreMLNeuralEngine]

    XCTAssertEqual(runtimeMissing.state, .hardwareOnly)
    XCTAssertTrue(runtimeMissing.runtimeEvidence.contains("does not expose"))
    XCTAssertEqual(hardwareMissing.state, .unavailable)
  }

  func testLocalModelAcceleratorPolicyVendorFamilyWithoutBundledAdapterIsHardwareOnly() {
    let capability = LocalModelAcceleratorPolicy.evaluate(
      probe(vendorSdkAvailable: false)
    )[.vendorSDK]

    XCTAssertEqual(capability.state, .hardwareOnly)
    XCTAssertTrue(capability.runtimeEvidence.contains("not bundled"))
  }

  func testLocalModelAcceleratorPolicyUnknownVendorIsUnavailableRatherThanGuessed() {
    let capability = LocalModelAcceleratorPolicy.evaluate(
      probe(
        vendorFamily: "",
        vendorHardwareEvidence: "Unknown Apple platform",
        vendorSdkAvailable: false
      )
    )[.vendorSDK]

    XCTAssertEqual(capability.state, .unavailable)
    XCTAssertEqual(capability.provider, "Vendor accelerator")
  }

  func testLocalModelAcceleratorPolicyCpuAndGpuCannotBecomeReadyFromRuntimeAlone() {
    let cpuHardwareOnly = LocalModelAcceleratorPolicy.evaluate(
      probe(cpuRuntimeAvailable: false)
    )[.cpu]
    let gpuRuntimeOnly = LocalModelAcceleratorPolicy.evaluate(
      probe(gpuHardwareAvailable: false, gpuRuntimeAvailable: true)
    )[.gpu]

    XCTAssertEqual(cpuHardwareOnly.state, .hardwareOnly)
    XCTAssertEqual(gpuRuntimeOnly.state, .unavailable)
  }

  func testLocalModelAcceleratorModelsUseAndroidWireNamesAndStableOrdering() throws {
    let snapshot = LocalModelAcceleratorPolicy.evaluate(
      probe(gpuRuntimeAvailable: false, vendorSdkAvailable: false),
      checkedAtMillis: 2_000
    )
    let encoded = try JSONEncoder().encode(snapshot)
    let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
    let capabilities = try XCTUnwrap(object["capabilities"] as? [[String: Any]])
    let probeObject = try XCTUnwrap(
      JSONSerialization.jsonObject(with: try JSONEncoder().encode(probe())) as? [String: Any]
    )

    XCTAssertEqual((object["checked_at_millis"] as? NSNumber)?.int64Value ?? 0, 2_000)
    XCTAssertEqual(capabilities.map { $0["kind"] as? String ?? "" }, [
      "CPU",
      "GPU",
      "CORE_ML_NEURAL_ENGINE",
      "VENDOR_SDK",
    ])
    XCTAssertEqual(capabilities[1]["state"] as? String, "HARDWARE_ONLY")
    XCTAssertEqual(capabilities[1]["hardware_evidence"] as? String, "Metal device: Apple GPU")
    XCTAssertEqual(capabilities[2]["provider"] as? String, "Core ML Neural Engine")
    XCTAssertEqual(probeObject["neural_engine_hardware_available"] as? Bool, true)
    XCTAssertEqual(probeObject["vendor_family"] as? String, "Apple Silicon")
    XCTAssertEqual(LocalModelAcceleratorKind.fromWireValue("gpu"), Optional(.gpu))
    XCTAssertEqual(LocalModelAcceleratorState.fromWireValue("HARDWARE_ONLY"), .hardwareOnly)
  }

  func testLocalModelAcceleratorDetectorBuildsIOSProbeFromRuntimeNames() {
    let probe = LocalModelAcceleratorDetector.probe(
      runtimeLibraryNames: [
        "libggml-metal.dylib",
        "onnxruntime-coreml.framework",
        "Accelerate.framework",
      ],
      cpuCoreCount: 6,
      machineIdentifier: "iPhone15,2",
      metalHardwareAvailable: true,
      metalDescription: "Metal device: Apple GPU",
      neuralEngineHardwareAvailable: true,
      neuralEngineDescription: "iPhone15,2 can use Core ML Neural Engine scheduling"
    )
    let snapshot = LocalModelAcceleratorPolicy.evaluate(probe)

    XCTAssertTrue(probe.cpuRuntimeAvailable)
    XCTAssertTrue(probe.gpuRuntimeAvailable)
    XCTAssertTrue(probe.neuralEngineRuntimeAvailable)
    XCTAssertEqual(probe.vendorFamily, "Apple Silicon")
    XCTAssertTrue(probe.vendorSdkAvailable)
    XCTAssertEqual(snapshot[.gpu].state, .ready)
    XCTAssertEqual(snapshot[.coreMLNeuralEngine].state, .ready)
  }

  func testLocalModelAcceleratorDetectorLeavesSimulatorStyleHardwareUnavailable() {
    let probe = LocalModelAcceleratorDetector.probe(
      runtimeLibraryNames: ["libggml-metal.dylib"],
      cpuCoreCount: 4,
      machineIdentifier: "x86_64",
      metalHardwareAvailable: false,
      metalDescription: "No Metal device is available",
      neuralEngineHardwareAvailable: false,
      neuralEngineDescription: "iOS Simulator does not expose Apple Neural Engine"
    )
    let snapshot = LocalModelAcceleratorPolicy.evaluate(probe)

    XCTAssertEqual(snapshot[.cpu].state, .ready)
    XCTAssertEqual(snapshot[.gpu].state, .unavailable)
    XCTAssertEqual(snapshot[.coreMLNeuralEngine].state, .unavailable)
    XCTAssertEqual(snapshot[.vendorSDK].state, .unavailable)
  }

  private func probe(
    cpuHardwareAvailable: Bool = true,
    cpuRuntimeAvailable: Bool = true,
    gpuHardwareAvailable: Bool = true,
    gpuRuntimeAvailable: Bool = true,
    neuralEngineHardwareAvailable: Bool = true,
    neuralEngineRuntimeAvailable: Bool = true,
    vendorFamily: String = "Apple Silicon",
    vendorHardwareEvidence: String = "iPhone15,2",
    vendorSdkAvailable: Bool = true
  ) -> LocalModelAcceleratorProbe {
    LocalModelAcceleratorProbe(
      cpuHardwareAvailable: cpuHardwareAvailable,
      cpuDescription: "6 cores / iPhone15,2",
      cpuRuntimeAvailable: cpuRuntimeAvailable,
      cpuRuntimeDescription: cpuRuntimeAvailable ? "CPU backend bundled" : "CPU backend missing",
      gpuHardwareAvailable: gpuHardwareAvailable,
      gpuDescription: "Metal device: Apple GPU",
      gpuRuntimeAvailable: gpuRuntimeAvailable,
      gpuRuntimeDescription: gpuRuntimeAvailable ? "Metal backend bundled" : "Metal backend not bundled",
      neuralEngineHardwareAvailable: neuralEngineHardwareAvailable,
      neuralEngineRuntimeAvailable: neuralEngineRuntimeAvailable,
      neuralEngineDescription: "iPhone15,2 can use Core ML Neural Engine scheduling",
      vendorFamily: vendorFamily,
      vendorHardwareEvidence: vendorHardwareEvidence,
      vendorSdkAvailable: vendorSdkAvailable,
      vendorRuntimeEvidence: vendorSdkAvailable ? "Vendor SDK bundled" : "Vendor SDK not bundled"
    )
  }
}
